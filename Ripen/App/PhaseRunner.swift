import Foundation
import Observation
import os

/// 會改變階段執行狀態的操作意圖；全部經 `PhaseRunner.apply(_:)` 套用。
enum PhaseRunIntent: Equatable, Sendable {
    case start
    case pause
    case resume
    /// 單一按鍵的開始／暫停：依目前狀態開始、暫停或繼續。超時中同樣是暫停／繼續（ADR-0006）。
    case toggleStartPause
    /// 結束超時中的這一段、確立完成並進到下一段（ADR-0006）。倒數到 0 前不適用。
    case finish
    /// 直接進到下一段的起點，不算完成。超時中由「完成」取代，不適用。
    case skip
    /// 目前階段回到完整長度並停止，不算完成。超時中或停在起點時不適用。
    case reset
    /// 復原上一個跳過、重設或完成；期限已過則不適用。
    case undo
    /// 選擇分類（nil 為未分類）。專注進行中時整次專注改歸這個分類；其餘時候只改下一次（ADR-0010）。
    /// 不是計時操作：不先刷新、不結束復原機會。
    case selectProject(UUID?)
    /// 分類已被刪除、紀錄已改為未分類（ADR-0012）：指向它的歸屬與完成回饋也改為未分類。
    case uncategorize(projectID: UUID)
    /// 退出前暫停目前階段，先前已按完成的紀錄確立；不完成也不前進（ADR-0014）。
    case pauseForQuit

    /// 先套用由時間推導出的變化（倒數到 0 的提醒、離開時的暫停）再處理意圖；分類的異動不是計時操作。
    fileprivate var refreshesFirst: Bool {
        switch self {
        case .selectProject, .uncategorize: false
        default: true
        }
    }
}

/// 套用一次意圖或刷新的結果。
enum PhaseRunOutcome: Equatable, Sendable {
    /// 等待恢復決定（或恢復進度載入失敗）：什麼都沒做。
    case awaitingRecoveryDecision
    /// 此刻不適用（例如倒數到 0 前按完成）：狀態不變，不寫檢查點。
    case unchanged
    /// 已生效。檢查點寫入失敗時為假，留下保存提示等待重試；刷新時未到期不寫也為真。
    case applied(checkpointSaved: Bool)
    /// 檢查點寫入失敗，整份不生效（復原）。
    case rolledBack
}

/// 階段執行狀態的唯一變更入口：每一次意圖與刷新都是一筆轉移，閘門、復原快照、暫存的完成、
/// 狀態變更與檢查點在 `transact` 內一次完成（ADR-0014）。
///
/// 轉移在工作副本上進行，結束時才整份換上可觀察的狀態：意圖不適用時不留下任何變更，
/// 檢查點必須先成功的轉移（復原）失敗時整份捨棄。新增一種意圖只需在 `plan(_:)` 加一個 case，
/// 而 `plan(_:)` 只能經 `transact` 呼叫，不可能略過閘門或檢查點。
///
/// 提醒、到點計時器與通知不在這裡：由 `onReachedZero` 與 `onRunChange` 交給組裝它的 `AppModel`。
@MainActor
@Observable
final class PhaseRunner {
    /// 跳過、重設、完成之後可以復原的時間。
    nonisolated static let undoWindow: TimeInterval = 5
    /// 執行期間每五秒保存一份進度；系統延後排程或寫入失敗時，以最後成功點為準。
    nonisolated static let recoveryCheckpointInterval: TimeInterval = 5

    /// 可以復原的操作與操作前的狀態，同生同滅；結束時一併確立（期限過了、有其他操作）或捨棄（復原）暫存的完成紀錄。
    struct PendingUndo: Equatable {
        let offer: UndoOffer
        let snapshot: PhaseRun
    }

    /// 一筆轉移操作的對象：階段執行狀態、進行中專注的歸屬與復原機會。
    private struct State: Equatable {
        var run: PhaseRun
        var focusProjectID: UUID?
        var pendingUndo: PendingUndo?
    }

    /// 一筆轉移的檢查點規則；由 `plan(_:)` 為每種意圖選定，`transact` 依它寫入。
    private enum Checkpoint {
        /// 關鍵操作：寫入失敗時照樣生效，留下保存提示供重試。
        case always
        /// 刷新：狀態有變化才寫；執行中另每五秒寫一次，已有保存錯誤時等重試。
        case whenDue
        /// 復原：日誌先移除暫存的完成、寫入成功才生效，失敗時整份不變（ADR-0014）。
        /// 否則畫面已復原，當機後這筆完成仍會從日誌確立。
        case beforeDiscardingStaged
    }

    private enum RecoveryAction { case continueSaved, discard, save }

    private static let logger = Logger(subsystem: "com.latteine.ripen", category: "recovery")

    @ObservationIgnored private let clock: any TimeSource
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let focusLog: FocusLog
    @ObservationIgnored private let storage: any TimerRecoveryStorage

    // 可觀察的狀態分開保存：刷新每 0.25 秒一次，只換上真的有變化的部分，靜止的介面才不會一直重繪。
    private(set) var run: PhaseRun {
        didSet { onRunChange?(oldValue) }
    }
    /// 進行中專注的歸屬；開始專注時取自下次選擇，途中更正時一併改寫（ADR-0010）。
    private(set) var focusProjectID: UUID?
    private(set) var pendingUndo: PendingUndo?
    /// 轉移中的工作副本；轉移之外與可觀察的狀態相同。轉移內的讀寫（含暫存確立前的保存點）都以它為準。
    @ObservationIgnored private var working: State

    private(set) var recovery: TimerRecovery?
    private(set) var recoveryIssue: FocusLogIssue? {
        didSet { if recoveryIssue != nil && recoveryIssue != oldValue { onRecoveryIssue?() } }
    }
    /// 可觀察：載入失敗時 `requiresRecoveryDecision` 不會讀到 `recovery`，重試成功後靜止的介面要靠它解除閘門。
    private var recoveryLoaded = false
    @ObservationIgnored private var lastCheckpointAt: Date?
    @ObservationIgnored private var failedRecoveryAction: RecoveryAction?

    /// 使用者離開電腦的時刻；在場時為 nil。超時只算到這一刻（ADR-0006）。不屬於階段執行狀態，復原不還原它。
    @ObservationIgnored var awaySince: Date?
    /// 換上新的階段執行狀態之後，帶上舊值；到點計時器與通知據此重排。
    @ObservationIgnored var onRunChange: ((_ oldValue: PhaseRun) -> Void)?
    /// 刷新時目前階段第一次跨過 0，帶上該階段；轉移換上之後才呼叫。
    @ObservationIgnored var onReachedZero: ((Phase) -> Void)?
    @ObservationIgnored var onRecoveryIssue: (() -> Void)?

    /// 尚未決定或載入失敗時，所有入口維持同一份恢復資料，不允許另開計時。
    var requiresRecoveryDecision: Bool { !recoveryLoaded || recovery != nil }

    /// 完成紀錄與恢復進度共用同一份儲存：檢查點與完成日誌靠同一交易保持一致（ADR-0014）。
    init(clock: any TimeSource, settings: AppSettings, focusLog: FocusLog, storage: any TimerRecoveryStorage) {
        self.clock = clock
        self.settings = settings
        self.focusLog = focusLog
        self.storage = storage
        let configuration = settings.cycleConfiguration
        cachedConfiguration = (settings.revision, configuration)
        let initial = State(run: PhaseRun(configuration: configuration, idleSince: clock.now()))
        run = initial.run
        working = initial
        loadRecovery()
        // 包含歷史頁直接重試在內，正式完成必須先有可重播的保存點。
        focusLog.persistRecoveryBeforeCommit = { [weak self] in
            guard let self, self.recoveryLoaded, self.saveCheckpoint() else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        // 等待恢復決定時拒絕所有分類與紀錄的異動；更正檢查用系統時間的現在（ADR-0020）
        focusLog.isAwaitingRecoveryDecision = { [weak self] in self?.requiresRecoveryDecision ?? true }
        focusLog.now = { [weak self] in
            guard let self else { return Date() }
            return self.clock.systemDate(for: self.clock.now())
        }
        focusLog.onProjectDeleted = { [weak self] id in _ = self?.apply(.uncategorize(projectID: id)) }
    }

    /// 已開始（含暫停與超時）的專注；此時選分類是更正當次歸屬，其餘時候只影響下一次。
    var isFocusInProgress: Bool { Self.isFocusInProgress(run) }

    private static func isFocusInProgress(_ run: PhaseRun) -> Bool {
        run.engine.phase == .focus && run.engine.startedAt != nil
    }

    /// 只在設定寫入後重算：UI 每 0.25 秒刷新，每次都從 UserDefaults 讀多個 key 太浪費。
    var configuration: CycleConfiguration {
        if let cached = cachedConfiguration, cached.revision == settings.revision { return cached.value }
        let value = settings.cycleConfiguration
        cachedConfiguration = (settings.revision, value)
        return value
    }
    @ObservationIgnored private var cachedConfiguration: (revision: Int, value: CycleConfiguration)?

    // MARK: - 轉移

    /// 套用一個操作意圖。除了復原與分類的異動，意圖都會結束上一個操作的復原機會。
    @discardableResult
    func apply(_ intent: PhaseRunIntent) -> PhaseRunOutcome {
        if intent.refreshesFirst { refresh() }
        return transact { plan(intent) }
    }

    /// 套用由時間推導出的變化：離開時暫停超時、倒數到 0、閒置歸零、改過的階段長度、復原期限與完成摘要。
    ///
    /// 只標記倒數到 0，不會結束階段。重複呼叫無妨。
    @discardableResult
    func refresh() -> PhaseRunOutcome {
        var crossed: Phase?
        let outcome = transact {
            let now = clock.now()
            let configuration = self.configuration
            working.run.pauseOvertimeIfAway(since: awaySince, at: now)
            if working.run.markReachedZero(at: now) { crossed = working.run.engine.phase }
            working.run.resetCountIfIdle(at: now, configuration: configuration)
            working.run.applyChangedLength(at: now, configuration: configuration)
            expireUndoOffer(at: now)
            working.run.expireCompletionSummary(at: now)
            return .whenDue
        }
        if let crossed { onReachedZero?(crossed) }
        return outcome
    }

    /// 唯一寫入可觀察狀態的轉移：閘門與檢查點只在這裡。
    ///
    /// `change` 在工作副本上進行，回傳 nil 表示不適用，工作副本換回原狀。
    private func transact(_ change: () -> Checkpoint?) -> PhaseRunOutcome {
        guard !requiresRecoveryDecision else { return .awaitingRecoveryDecision }
        let before = working
        guard let checkpoint = change() else {
            working = before
            return .unchanged
        }
        let saved: Bool
        switch checkpoint {
        case .always:
            saved = saveCheckpoint()
        case .whenDue:
            saved = isCheckpointDue(since: before) ? saveCheckpoint() : true
        case .beforeDiscardingStaged:
            guard saveCheckpoint(completions: focusLog.completionsWithoutStaged) else {
                working = before
                return .rolledBack
            }
            focusLog.discardStaged()
            saved = true
        }
        install()
        return .applied(checkpointSaved: saved)
    }

    /// 每種意圖對工作副本的變更與它的檢查點規則；只由 `transact` 呼叫。
    private func plan(_ intent: PhaseRunIntent) -> Checkpoint? {
        let now = clock.now()
        switch intent {
        case .start:
            closeUndoOffer()
            start(at: now)
        case .pause:
            closeUndoOffer()
            pause(at: now)
        case .resume:
            closeUndoOffer()
            resume(at: now)
        case .toggleStartPause:
            closeUndoOffer()
            switch working.run.engine.status(at: now) {
            case .idle: start(at: now)
            case .running: pause(at: now)
            case .paused: resume(at: now)
            }
        case .finish:
            guard let completion = completion(at: now) else { return nil }
            closeUndoOffer()
            let before = working.run
            // 前進後已是下一段的起點，再按一次完成不會重複記錄
            let record = recordIfFocus(completion)
            working.run.advance(completed: true, configuration: configuration)
            if let record { presentCompletion(of: record, at: now) }
            // 「自動開始下一段」開啟時，按完成的那一刻就開始下一段（ADR-0006）
            if settings.autoStartNextPhase { startEngine(at: now) }
            working.run.updateIdle(at: now)
            offerUndo(.finish, restoring: before, at: now)
        case .skip:
            guard !working.run.engine.isOvertime(at: now) else { return nil }
            closeUndoOffer()
            let before = working.run
            working.run.advance(completed: false, configuration: configuration)
            working.run.updateIdle(at: now)
            offerUndo(.skip, restoring: before, at: now)
        case .reset:
            // 停在起點時重設沒有變化，也就沒有可復原的
            guard !working.run.engine.isOvertime(at: now), working.run.engine.status(at: now) != .idle else { return nil }
            closeUndoOffer()
            let before = working.run
            working.run.loadCurrentPhase(configuration)
            working.run.updateIdle(at: now)
            offerUndo(.reset, restoring: before, at: now)
        case .undo:
            guard let snapshot = working.pendingUndo?.snapshot else { return nil }
            working.run = snapshot
            // 換回的摘要可能已過了顯示時間，不重播
            working.run.expireCompletionSummary(at: now)
            working.pendingUndo = nil
            return .beforeDiscardingStaged
        case .selectProject(let id):
            settings.lastProjectID = id
            if Self.isFocusInProgress(working.run) { working.focusProjectID = id }
        case .uncategorize(let id):
            uncategorize(id)
        case .pauseForQuit:
            closeUndoOffer()
            working.run.engine.pause(at: now)
            working.run.updateIdle(at: now)
        }
        return .always
    }

    /// 只換上真的有變化的部分。
    private func install() {
        if working.run != run { run = working.run }
        if working.focusProjectID != focusProjectID { focusProjectID = working.focusProjectID }
        if working.pendingUndo != pendingUndo { pendingUndo = working.pendingUndo }
    }

    // MARK: - 意圖本體

    private func start(at now: Date) {
        startEngine(at: now)
        working.run.updateIdle(at: now)
    }

    /// 專注從起點開始時確定當次歸屬。選擇是否已失效由 `FocusLog` 在歷史載入後判定，
    /// 載入失敗時不能把仍有效的選擇當成未分類。
    private func startEngine(at now: Date) {
        if working.run.engine.phase == .focus, working.run.engine.status(at: now) == .idle {
            working.focusProjectID = settings.lastProjectID
        }
        working.run.engine.start(at: now)
    }

    private func pause(at now: Date) {
        working.run.engine.pause(at: now)
        working.run.updateIdle(at: now)
    }

    private func resume(at now: Date) {
        working.run.resume(at: now)
        working.run.updateIdle(at: now)
    }

    /// 刪除的分類改為未分類：下次的選擇、進行中的專注、完成摘要與成果卡入口。
    ///
    /// 復原會換回操作前的摘要與入口；其中指向這個分類時就結束復原機會，暫存的完成照常寫入（已是未分類）。
    private func uncategorize(_ id: UUID) {
        let undoRefersToIt = [working.pendingUndo?.snapshot.completionSummary, working.pendingUndo?.snapshot.recapShortcut]
            .contains { $0??.projectID == id }
        if undoRefersToIt || working.run.completionSummary?.projectID == id || working.run.recapShortcut?.projectID == id {
            closeUndoOffer()
        }
        if settings.lastProjectID == id { settings.lastProjectID = nil }
        if working.focusProjectID == id { working.focusProjectID = nil }
        working.run.completionSummary = movingToUncategorized(working.run.completionSummary, from: id)
        working.run.recapShortcut = movingToUncategorized(working.run.recapShortcut, from: id)
    }

    /// 這一次的長度不變；分類累積改為未分類的最新累積。
    private func movingToUncategorized(_ completed: CompletedFocus?, from id: UUID) -> CompletedFocus? {
        guard let completed, completed.projectID == id else { return completed }
        return CompletedFocus(
            projectID: nil,
            focus: completed.focus,
            projectTotal: focusLog.total(ofProject: nil),
            completedAt: completed.completedAt
        )
    }

    // MARK: - 完成的確立

    /// 這一段若在 `now` 完成會是怎樣的完成；倒數到 0 前為 nil。
    private func completion(at now: Date) -> PhaseCompletion? {
        guard working.run.engine.isOvertime(at: now), let startedAt = working.run.engine.startedAt else { return nil }
        return PhaseCompletion(phase: working.run.engine.phase, startedAt: startedAt,
                               duration: working.run.engine.elapsed(at: now))
    }

    /// 完成的專注記錄實際長度，依開始時刻歸日（GLOSSARY）。
    /// 按「完成」時先暫存（還能復原）。回傳暫存的紀錄（分類已確認）；休息不回傳。
    private func recordIfFocus(_ completion: PhaseCompletion) -> FocusRecord? {
        guard completion.phase == .focus else { return nil }
        let record = FocusRecord(startedAt: clock.systemDate(for: completion.startedAt), duration: completion.duration,
                                 projectID: working.focusProjectID)
        return focusLog.stage(record)
    }

    /// 摘要與入口都只回饋完成的專注；分類累積已含剛暫存的這一筆。
    private func presentCompletion(of record: FocusRecord, at now: Date) {
        let completed = CompletedFocus(
            projectID: record.projectID,
            focus: FocusStatistics(records: [record], calendar: .current).total,
            projectTotal: focusLog.total(ofProject: record.projectID),
            completedAt: now
        )
        working.run.completionSummary = completed
        working.run.recapShortcut = completed
    }

    // MARK: - 復原機會

    private func offerUndo(_ action: UndoableAction, restoring snapshot: PhaseRun, at now: Date) {
        working.pendingUndo = PendingUndo(offer: UndoOffer(action: action, expiresAt: now + Self.undoWindow),
                                          snapshot: snapshot)
    }

    /// 其他操作出現或期限已過，復原機會結束；暫存的完成紀錄在此寫入。
    private func closeUndoOffer() {
        working.pendingUndo = nil
        focusLog.commitStaged()
    }

    private func expireUndoOffer(at now: Date) {
        guard let pendingUndo = working.pendingUndo, now >= pendingUndo.offer.expiresAt else { return }
        closeUndoOffer()
    }

    // MARK: - 檢查點

    /// 刷新時：狀態有變化，或執行中距上次成功保存滿五秒。已有保存錯誤時等使用者重試。
    private func isCheckpointDue(since before: State) -> Bool {
        let now = clock.now()
        let changed = working.run.engine != before.run.engine || working.run.cycle != before.run.cycle
            || working.run.reachedZero != before.run.reachedZero
        return recoveryIssue == nil
            && (changed || (working.run.engine.status(at: now) == .running
                            && (lastCheckpointAt.map({ now.timeIntervalSince($0) >= Self.recoveryCheckpointInterval }) ?? true)))
    }

    /// 保存工作副本的進度；`completions` 預設為尚未確立與未保存的完成。
    @discardableResult
    private func saveCheckpoint(completions: [StoredFocusRecord]? = nil) -> Bool {
        let checkpoint = working.run.engine.recovery(at: clock.now(), projectID: working.focusProjectID,
                                                     completedFocuses: working.run.cycle.completedFocuses)
        return writeRecovery(storable(checkpoint), completions: completions, action: .save)
    }

    /// 存下的開始時刻是系統時間，重新開啟後才不會依上次啟動的時間解讀。
    private func storable(_ recovery: TimerRecovery?) -> TimerRecovery? {
        recovery?.shiftingStart(by: clock.systemClockOffset)
    }

    private func writeRecovery(
        _ value: TimerRecovery?, completions: [StoredFocusRecord]? = nil, action: RecoveryAction
    ) -> Bool {
        do {
            try storage.saveCheckpoint(value, completions: completions ?? focusLog.recoveryCompletions)
            lastCheckpointAt = clock.now()
            failedRecoveryAction = nil
            recoveryIssue = nil
            return true
        } catch {
            failedRecoveryAction = action
            recoveryIssue = .save
            Self.logger.error("保存恢復進度失敗，等待重試：\(error)")
            return false
        }
    }

    // MARK: - 跨啟動恢復

    // 恢復決定本身就是解除閘門的入口，不經 `transact`；各自先寫入成功才換上狀態。

    private func loadRecovery() {
        do {
            let completedWereRecovered = try storage.recoverCompletions()
            // 先前交易可能已提交但遺失回報；重試也要讀回實際歷史。
            if completedWereRecovered || recoveryIssue == .load { focusLog.retry() }
            let loaded = try storage.loadRecovery()
            if let loaded {
                guard loaded.isValid else { throw FocusStorageError.invalidData }
                working.run = PhaseRun(recovery: loaded.shiftingStart(by: -clock.systemClockOffset))
                working.focusProjectID = loaded.projectID
            }
            recovery = loaded
            recoveryLoaded = true
            recoveryIssue = nil
            working.run.idleSince = nil
            install()
        } catch {
            recoveryIssue = .load
            Self.logger.error("載入恢復進度失敗，保留原資料：\(error)")
        }
    }

    func continueRecovery() {
        guard recovery != nil, recoveryLoaded else { return }
        // 分類還沒載入時不能把未知分類當作未分類完成。
        focusLog.retryIfNeeded()
        guard focusLog.issue != .load, writeRecovery(recovery, action: .continueSaved) else { return }
        recovery = nil
        working.run.resume(at: clock.now())
        working.run.idleSince = nil
        install()
    }

    func discardRecovery() {
        guard recovery != nil, recoveryLoaded, writeRecovery(nil, action: .discard) else { return }
        recovery = nil
        working.focusProjectID = nil
        working.run = PhaseRun(configuration: configuration, idleSince: clock.now())
        install()
    }

    func retryRecovery() {
        guard recoveryLoaded else { loadRecovery(); return }
        switch failedRecoveryAction {
        case .continueSaved: continueRecovery()
        case .discard: discardRecovery()
        case .save:
            focusLog.retryIfNeeded()
            saveCheckpoint()
        case nil: break
        }
    }
}

/// 一段倒數到過 0、由「完成」確立完成的階段。
struct PhaseCompletion: Equatable, Sendable {
    let phase: Phase
    /// 第一次開始的時刻；完成的專注歸屬於它所在的日期（ADR-0002）。
    let startedAt: Date
    /// 實際長度：設定長度加超時，扣掉暫停。
    let duration: TimeInterval
}
