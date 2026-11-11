import Foundation
import Observation
import os

/// 計時的可觀察狀態根：對外只暴露操作意圖與可觀察狀態。形態（畫面上有哪些介面）另由 `PresentationModel` 持有。
///
/// 時間相關的值（`status`、`remaining`、`isOvertime`、`overtime`）每次讀取都向注入的時鐘取「現在」，
/// 本身不會因時間流逝而發出變更通知；UI 需以 `TimelineView` 定期取用 `display`。
///
/// 倒數到 0 只是由時間推導出的超時（ADR-0006）：`refresh()` 發現時送出提醒，階段不前進；
/// 使用者按「完成」（`finish()`）才確立完成、記錄並前進到下一段。
///
/// 內部時刻都在 `clock.now()` 那一套不受系統時間調動的時間裡；交給畫面、提醒與儲存的時刻
/// 換算成目前的系統時間，讀回儲存時反向換算（ADR-0020）。
@MainActor
@Observable
final class AppModel {
    static let idleResetInterval = PhaseRun.idleResetInterval
    /// 跳過、重設、完成之後可以復原的時間。
    nonisolated static let undoWindow: TimeInterval = 5
    nonisolated static let completionSummaryDuration = PhaseRun.completionSummaryDuration
    /// 執行期間每五秒保存一份進度；系統延後排程或寫入失敗時，以最後成功點為準。
    nonisolated static let recoveryCheckpointInterval: TimeInterval = 5

    @ObservationIgnored private let clock: any TimeSource
    /// 使用者設定；階段長度與長休息間隔每次需要時才讀，改動從下一段生效。
    @ObservationIgnored let settings: AppSettings
    /// 完成的專注紀錄，統計頁由此彙總；本身可觀察。
    @ObservationIgnored let focusLog: FocusLog
    @ObservationIgnored private let presence: any UserPresence
    @ObservationIgnored private let reminderSound: any ReminderSound
    @ObservationIgnored private let alarm: any PhaseEndAlarm
    @ObservationIgnored private let notifier: any PhaseNotifier
    private static let recoveryLogger = Logger(subsystem: "com.latteine.ripen", category: "recovery")
    @ObservationIgnored private let recoveryStorage: any TimerRecoveryStorage
    private(set) var recovery: TimerRecovery?
    private(set) var recoveryIssue: FocusLogIssue? {
        didSet { if recoveryIssue != nil && recoveryIssue != oldValue { onRecoveryIssue?() } }
    }
    @ObservationIgnored var onRecoveryIssue: (() -> Void)?
    /// 等待恢復決定時按了全域熱鍵；App 叫出主視窗的恢復畫面並發出提示音（#79）。
    @ObservationIgnored var onHotkeyBlockedByRecovery: (() -> Void)?
    /// 可觀察：載入失敗時 `requiresRecoveryDecision` 不會讀到 `recovery`，重試成功後靜止的介面要靠它解除閘門。
    private var recoveryLoaded = false
    @ObservationIgnored private var lastRecoveryCheckpointAt: Date?
    private enum RecoveryAction { case continueSaved, discard, save }
    @ObservationIgnored private var failedRecoveryAction: RecoveryAction?
    /// 尚未決定或載入失敗時，所有入口維持同一份恢復資料，不允許另開計時。
    var requiresRecoveryDecision: Bool { !recoveryLoaded || recovery != nil }
    /// 恢復進度的提示還在時不另外顯示紀錄的提示：它的重試也會重試紀錄，同一次失敗只有一則提示與一個重試。
    /// 恢復點之後保存成功、紀錄仍未寫入時，這則提示才接手，未保存的紀錄不會沒有提示。
    var showsFocusStorageNotice: Bool { recoveryIssue == nil && focusLog.issue != nil }

    private var run: PhaseRun {
        // 結束時刻一變就重排到點計時器；所有操作都經過這裡，不必逐一記得重排。
        // 超時中繼續時結束時刻在過去，不再排：提醒每段只送一次
        didSet {
            // 離開超時就是這一段結束了；所有操作都經過這裡，通知中心不留下過期的提醒
            if oldValue.reachedZero && !run.reachedZero { notifier.clearPhaseEndNotification() }
            guard run.engine.endDate != oldValue.engine.endDate else { return }
            scheduleAlarm()
        }
    }
    /// 可觀察：每段只在跨過 0 時變一次，選單列選單靠它在那一刻換成「完成」，不必隨時間文字重建。
    var reachedZero: Bool { run.reachedZero }
    /// 離開期間倒數到 0、還沒播的提醒；回來時播。
    @ObservationIgnored private var pendingReminder: Phase?
    /// 使用者離開電腦的時刻；在場時為 nil。超時只算到這一刻（ADR-0006）。
    @ObservationIgnored private var awaySince: Date?
    /// 最後一次播出的提醒；各介面觀察它的 `id` 播提醒動畫。
    private(set) var lastReminder: PhaseReminder?
    /// 目前可以復原的操作；各介面依它顯示復原膠囊，期限以系統時間表示。
    var undoOffer: UndoOffer? {
        pendingUndo.map { UndoOffer(action: $0.offer.action, expiresAt: clock.systemDate(for: $0.offer.expiresAt)) }
    }
    /// 可以復原的操作與操作前的狀態，同生同滅；結束時一併確立（期限過了、有其他操作）或捨棄（復原）暫存的完成紀錄。
    private var pendingUndo: PendingUndo?
    /// 進行中專注的歸屬；開始專注時取自下次選擇，途中更正時一併改寫（ADR-0010）。
    private var focusProjectID: UUID?
    /// 完成摘要；由 `refresh()` 收起。
    var completionSummary: CompletedFocus? { run.completionSummary }
    var recapShortcut: CompletedFocus? { run.recapShortcut }
    /// 緊接專注的休息期間、完成摘要已收起；拖出圓環的一次性提示在這時出現，不擋住摘要（#40）。
    var isRestingAfterFocus: Bool { recapShortcut != nil && completionSummary == nil }

    private struct PendingUndo {
        let offer: UndoOffer
        let snapshot: PhaseRun
    }

    /// 未指定的依賴一律用不碰系統的版本：測試與預覽不讀寫真正的設定與紀錄、不出聲。
    ///
    /// 完成紀錄與恢復進度共用同一份儲存：檢查點與完成日誌靠同一交易保持一致（ADR-0014）。
    init(
        clock: any TimeSource = SystemTimeSource(),
        settings: AppSettings = AppSettings(storage: InMemorySettingsStorage()),
        storage: any FocusStorage = InMemoryFocusStorage(),
        presence: any UserPresence = AlwaysPresent(),
        reminderSound: any ReminderSound = SilentReminderSound(),
        alarm: any PhaseEndAlarm = NoPhaseEndAlarm(),
        notifier: any PhaseNotifier = NoPhaseNotifier()
    ) {
        self.clock = clock
        self.settings = settings
        self.focusLog = FocusLog(storage: storage)
        self.presence = presence
        self.reminderSound = reminderSound
        self.alarm = alarm
        self.notifier = notifier
        self.recoveryStorage = storage
        let configuration = settings.cycleConfiguration
        cachedConfiguration = (settings.revision, configuration)
        run = PhaseRun(configuration: configuration, idleSince: clock.now())
        presence.onLeave = { [weak self] leftAgo in self?.userDidLeave(leftAgo: leftAgo) }
        presence.onReturn = { [weak self] in self?.userDidReturn() }
        alarm.onFire = { [weak self] in self?.alarmDidFire() }
        loadRecovery()
        // 包含歷史頁直接重試在內，正式完成必須先有可重播的保存點。
        focusLog.persistRecoveryBeforeCommit = { [weak self] in
            guard let self, self.recoveryLoaded, self.saveCurrentRecovery() else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }

    /// 只讀取一次注入時鐘；不呼叫 refresh，不發出提醒或確立完成。
    var display: PhaseDisplay {
        let now = clock.now()
        return PhaseDisplay(
            phase: run.engine.phase, status: run.engine.status(at: now), remaining: run.engine.remaining(at: now),
            isOvertime: run.engine.isOvertime(at: now), overtime: run.engine.overtime(at: now),
            phaseDuration: run.engine.duration, endDate: run.engine.endDate.map(clock.systemDate(for:)),
            completedFocusesInCycle: run.cycle.completedFocuses, longBreakInterval: configuration.longBreakInterval
        )
    }

    var phase: Phase { run.engine.phase }

    var status: TimerStatus { run.engine.status(at: clock.now()) }
    /// 倒數到 0 之後（含暫停中）；此時「跳過」「重設」由「完成」取代。
    var isOvertime: Bool { run.engine.isOvertime(at: clock.now()) }
    /// 目前階段的總長度，供進度計算。
    var phaseDuration: TimeInterval { run.engine.duration }
    var longBreakInterval: Int { configuration.longBreakInterval }

    // MARK: - 分類

    /// 已開始（含暫停與超時）的專注；此時選分類是更正當次歸屬，其餘時候只影響下一次。
    var isFocusInProgress: Bool { run.engine.phase == .focus && run.engine.startedAt != nil }

    /// 分類選單目前呈現的歸屬：進行中的專注顯示當次分類，否則是下一次的選擇。nil 是未分類。
    var currentProject: FocusProject? {
        focusLog.project(withID: isFocusInProgress ? focusProjectID : settings.lastProjectID)
    }

    /// 選擇分類（nil 為未分類）。專注進行中時整次專注改歸這個分類，不拆分時間；
    /// 休息或尚未開始時只改下一次。不是計時操作，不結束復原機會，也不改動暫存的完成紀錄。
    func selectProject(_ id: UUID?) {
        guard !requiresRecoveryDecision else { return }
        settings.lastProjectID = id
        if isFocusInProgress { focusProjectID = id }
        _ = saveCurrentRecovery()
    }

    /// 新增並直接選取分類；空白名稱不建立，回傳 nil。
    @discardableResult
    func createProject(named name: String, color: ProjectColor? = nil) -> FocusProject? {
        guard !requiresRecoveryDecision else { return nil }
        guard let project = focusLog.addProject(named: name, color: color) else { return nil }
        selectProject(project.id)
        return project
    }
    /// 刪除分類（ADR-0012）：紀錄改為未分類；進行中的專注、下次的選擇、完成摘要與成果卡入口指向它的，也都改為未分類。
    ///
    /// 復原會換回操作前的摘要與入口；其中指向這個分類時就結束復原機會，暫存的完成照常寫入（已是未分類）。
    func deleteProject(_ id: UUID) {
        guard !requiresRecoveryDecision else { return }
        guard focusLog.project(withID: id) != nil else { return }
        let undoRefersToIt = [pendingUndo?.snapshot.completionSummary, pendingUndo?.snapshot.recapShortcut]
            .contains { $0??.projectID == id }
        if undoRefersToIt || completionSummary?.projectID == id || recapShortcut?.projectID == id { closeUndoOffer() }
        focusLog.deleteProject(id)
        if settings.lastProjectID == id { settings.lastProjectID = nil }
        if focusProjectID == id { focusProjectID = nil }
        run.completionSummary = movingToUncategorized(run.completionSummary, from: id)
        run.recapShortcut = movingToUncategorized(run.recapShortcut, from: id)
        _ = saveCurrentRecovery()
    }

    /// 分類改名（ADR-0019）；空白名稱或不存在的分類不改。
    @discardableResult
    func renameProject(_ id: UUID, to name: String) -> Bool {
        guard !requiresRecoveryDecision else { return false }
        return focusLog.renameProject(id, to: name)
    }

    /// 更正或重新歸類一筆已保存的紀錄（ADR-0019）。開始時刻或長度有變時才檢查時間：
    /// 時鐘被往回調過的舊紀錄，只換分類時不該被擋下。完成摘要維持完成那一刻的數字。
    @discardableResult
    func editRecord(_ id: UUID, to record: FocusRecord) -> Bool {
        guard !requiresRecoveryDecision,
              let current = focusLog.entries.first(where: { $0.id == id })?.record
        else { return false }
        let timeChanged = record.startedAt != current.startedAt || record.duration != current.duration
        if timeChanged,
           FocusRecord.correctionIssue(startedAt: record.startedAt, duration: record.duration,
                                       now: clock.systemDate(for: clock.now())) != nil {
            return false
        }
        return focusLog.updateRecord(id, to: record)
    }

    /// 刪除一筆已保存的紀錄，不能復原（ADR-0019）。
    @discardableResult
    func deleteRecord(_ id: UUID) -> Bool {
        guard !requiresRecoveryDecision else { return false }
        return focusLog.deleteRecord(id)
    }

    /// 這一次的長度不變；分類累積改為未分類的最新累積。
    private func movingToUncategorized(_ completed: CompletedFocus?, from id: UUID) -> CompletedFocus? {
        guard let completed, completed.projectID == id else { return completed }
        return CompletedFocus(
            projectID: nil,
            focus: completed.focus,
            projectTotal: FocusStatistics(records: focusLog.records.belonging(to: nil), calendar: .current).total,
            completedAt: completed.completedAt
        )
    }

    /// 只在設定寫入後重算：UI 每 0.25 秒刷新，每次都從 UserDefaults 讀多個 key 太浪費。
    private var configuration: CycleConfiguration {
        if let cached = cachedConfiguration, cached.revision == settings.revision { return cached.value }
        let value = settings.cycleConfiguration
        cachedConfiguration = (settings.revision, value)
        return value
    }
    @ObservationIgnored private var cachedConfiguration: (revision: Int, value: CycleConfiguration)?

    // MARK: - 刷新

    /// 套用由時間推導出的變化：離開時暫停超時、倒數到 0 的提醒、閒置歸零、改過的階段長度。
    ///
    /// 只送提醒，不會結束階段。intent、UI 刷新與系統喚醒時都應呼叫；重複呼叫無妨。
    func refresh() {
        guard !requiresRecoveryDecision else { return }
        let now = clock.now()
        let previous = run
        let configuration = self.configuration
        let crossedZero = updateRun {
            $0.pauseOvertimeIfAway(since: awaySince, at: now)
            return $0.markReachedZero(at: now)
        }
        if crossedZero {
            pendingReminder = run.engine.phase
            deliverPendingReminder()
        }
        updateRun {
            $0.resetCountIfIdle(at: now, configuration: configuration)
            $0.applyChangedLength(at: now, configuration: configuration)
        }
        expireUndoOffer(at: now)
        updateRun { $0.expireCompletionSummary(at: now) }
        checkpointRecovery(at: now, force: run.engine != previous.engine || run.cycle != previous.cycle
                           || run.reachedZero != previous.reachedZero)
    }

    /// 只在真的有變化時寫入：刷新每 0.25 秒一次，對 `run` 呼叫 mutating 方法即使沒變也會通知觀察者，靜止的介面會一直重繪。
    @discardableResult
    private func updateRun<Result>(_ change: (inout PhaseRun) -> Result) -> Result {
        var next = run
        let result = change(&next)
        if next != run { run = next }
        return result
    }

    // MARK: - 完成的確立

    /// 這一段若在 `now` 完成會是怎樣的完成；倒數到 0 前為 nil。
    private func completion(at now: Date) -> PhaseCompletion? {
        guard run.engine.isOvertime(at: now), let startedAt = run.engine.startedAt else { return nil }
        return PhaseCompletion(phase: run.engine.phase, startedAt: startedAt, duration: run.engine.elapsed(at: now))
    }

    /// 完成的專注記錄實際長度，依開始時刻歸日（GLOSSARY）。
    /// 按「完成」時先暫存（還能復原）。回傳暫存的紀錄（分類已確認）；休息不回傳。
    @discardableResult
    private func recordIfFocus(_ completion: PhaseCompletion) -> FocusRecord? {
        guard completion.phase == .focus else { return nil }
        let record = FocusRecord(startedAt: clock.systemDate(for: completion.startedAt), duration: completion.duration,
                                 projectID: focusProjectID)
        return focusLog.stage(record)
    }

    /// 摘要與入口都只回饋完成的專注；分類累積已含剛暫存的這一筆。
    private func presentCompletion(of record: FocusRecord, at now: Date) {
        let completed = CompletedFocus(
            projectID: record.projectID,
            focus: FocusStatistics(records: [record], calendar: .current).total,
            projectTotal: FocusStatistics(records: focusLog.records.belonging(to: record.projectID), calendar: .current).total,
            completedAt: now
        )
        run.completionSummary = completed
        run.recapShortcut = completed
    }

    // MARK: - 復原

    /// 復原上一個跳過、重設或完成：換回操作前的狀態，暫存的完成紀錄一併捨棄。期限已過則不做任何事。
    ///
    /// 日誌先更新成功才生效（ADR-0014）：否則畫面已復原，當機後這筆完成仍會從日誌確立。
    /// 保存失敗時狀態與復原機會都不變，可以再按一次；期限到了照一般流程確立。
    func undo() {
        guard !requiresRecoveryDecision else { return }
        refresh()
        guard let snapshot = pendingUndo?.snapshot else { return }
        let restored = storable(snapshot.engine.recovery(at: clock.now(), projectID: focusProjectID,
                                                         completedFocuses: snapshot.cycle.completedFocuses))
        guard writeRecovery(restored, completions: focusLog.completionsWithoutStaged, action: .save) else { return }
        focusLog.discardStaged()
        run = snapshot
        // 換回的摘要可能已過了顯示時間，不重播
        run.expireCompletionSummary(at: clock.now())
        pendingUndo = nil
    }

    private func offerUndo(_ action: UndoableAction, restoring snapshot: PhaseRun) {
        pendingUndo = PendingUndo(
            offer: UndoOffer(action: action, expiresAt: clock.now() + Self.undoWindow), snapshot: snapshot
        )
    }

    /// 其他操作出現或期限已過，復原機會結束；暫存的完成紀錄在此寫入。
    private func closeUndoOffer() {
        pendingUndo = nil
        focusLog.commitStaged()
    }

    private func expireUndoOffer(at now: Date) {
        guard let pendingUndo, now >= pendingUndo.offer.expiresAt else { return }
        closeUndoOffer()
    }

    // MARK: - 提醒與離開

    /// 使用者在場才播；離開時留在待播，回來再播（ADR-0002）。
    private func deliverPendingReminder() {
        guard let phase = pendingReminder, !presence.isAway else { return }
        pendingReminder = nil
        if settings.completionSoundEnabled { reminderSound.play(named: settings.reminderSoundName) }
        if settings.phaseEndNotificationEnabled { notifier.notifyPhaseEnded(phase) }
        lastReminder = PhaseReminder(id: (lastReminder?.id ?? 0) + 1, phase: phase)
    }

    /// 鎖定、睡眠或螢幕關閉：記下離開的時刻；已在超時中就立即暫停。
    /// 螢幕睡眠與螢幕保護程式的通知較晚送達，離開時刻回推 `leftAgo`。
    private func userDidLeave(leftAgo: TimeInterval) {
        awaySince = clock.now() - leftAgo
        refresh()
    }

    /// 解鎖或喚醒：先依離開時刻暫停睡眠中跨過 0 的倒數並送出提醒（睡眠時 App 不執行），回來後停在暫停。
    private func userDidReturn() {
        refresh()
        awaySince = nil
        deliverPendingReminder()
    }

    /// 系統時間被調動的次數；畫面的刷新節拍以系統時間排格線，帶上它才會在時間變更後重排（ADR-0020）。
    private(set) var systemClockRevision = 0

    /// 系統時間被調動（`NSSystemClockDidChange`）：倒數不受影響，到點提醒與畫面節拍依新的系統時間重排。
    func systemClockDidChange() {
        refresh()
        scheduleAlarm()
        systemClockRevision += 1
    }

    private func alarmDidFire() {
        refresh()
        // 計時器可能比結束時刻早一點觸發；還沒到 0 就重排，否則視窗關閉時提醒永遠不會送出
        let now = clock.now()
        if run.engine.status(at: now) == .running, !run.engine.isOvertime(at: now) {
            alarm.schedule(at: run.engine.endDate.map(clock.systemDate(for:)))
        }
    }

    /// 超時中繼續時結束時刻在過去，不再排：提醒每段只送一次。到點計時器以系統時間排定。
    private func scheduleAlarm() {
        alarm.schedule(at: run.engine.endDate.flatMap { $0 > clock.now() ? clock.systemDate(for: $0) : nil })
    }

    // MARK: - 設定的套用

    /// 「自動開始下一段」開啟時，按完成的那一刻就開始下一段（ADR-0006）。
    private func startNextPhaseAutomatically(now: Date) {
        guard settings.autoStartNextPhase else { return }
        startEngine(at: now)
    }

    // MARK: - 操作意圖

    // 每個意圖先 refresh()：倒數到 0 的提醒與離開時的暫停要先套用，再處理意圖。
    // 除了 undo() 之外的意圖都會結束上一個操作的復原機會。

    func start() {
        guard !requiresRecoveryDecision else { return }
        refresh()
        closeUndoOffer()
        startRefreshed()
    }

    func pause() {
        guard !requiresRecoveryDecision else { return }
        refresh()
        closeUndoOffer()
        pauseRefreshed()
    }

    func resume() {
        guard !requiresRecoveryDecision else { return }
        refresh()
        closeUndoOffer()
        resumeRefreshed()
    }

    /// 單一按鍵的開始／暫停：依目前狀態開始、暫停或繼續。全域熱鍵與選單共用。
    ///
    /// 超時中同樣是暫停／繼續；結束這一段要按「完成」（ADR-0006）。
    /// 先刷新再看狀態：離開時自動暫停的超時要先套用，才會選到「繼續」。
    func toggleStartPause() {
        guard !requiresRecoveryDecision else { return }
        refresh()
        closeUndoOffer()
        switch status {
        case .idle: startRefreshed()
        case .running: pauseRefreshed()
        case .paused: resumeRefreshed()
        }
    }

    /// 全域熱鍵的開始／暫停。其他入口在畫面上顯示停用原因，熱鍵按下時畫面可能不在，
    /// 等待恢復決定時改請 App 叫出恢復畫面，不默默失效（#79）；其餘狀態與 `toggleStartPause()` 相同。
    func toggleStartPauseFromHotkey() {
        guard !requiresRecoveryDecision else {
            onHotkeyBlockedByRecovery?()
            return
        }
        toggleStartPause()
    }

    // 以下是已刷新過的意圖本體，讓 toggleStartPause() 只刷新一次。

    private func startRefreshed() {
        startEngine(at: clock.now())
        run.updateIdle(at: clock.now())
        _ = saveCurrentRecovery()
    }

    /// 專注從起點開始時確定當次歸屬。選擇是否已失效由 `FocusLog` 在歷史載入後判定，
    /// 載入失敗時不能把仍有效的選擇當成未分類。
    private func startEngine(at now: Date) {
        if run.engine.phase == .focus, run.engine.status(at: now) == .idle {
            focusProjectID = settings.lastProjectID
        }
        run.engine.start(at: now)
    }

    private func pauseRefreshed() {
        run.engine.pause(at: clock.now())
        run.updateIdle(at: clock.now())
        _ = saveCurrentRecovery()
    }

    private func resumeRefreshed() {
        run.resume(at: clock.now())
        run.updateIdle(at: clock.now())
        _ = saveCurrentRecovery()
    }

    /// 「完成」：結束超時中的這一段、確立完成並進到下一段（ADR-0006）。倒數到 0 前不做任何事。
    func finish() {
        guard !requiresRecoveryDecision else { return }
        refresh()
        let now = clock.now()
        guard let completion = completion(at: now) else { return }
        closeUndoOffer()
        let before = run
        // 前進後已是下一段的起點，再按一次完成不會重複記錄
        let record = recordIfFocus(completion)
        run.advance(completed: true, configuration: configuration)
        if let record { presentCompletion(of: record, at: now) }
        startNextPhaseAutomatically(now: now)
        run.updateIdle(at: clock.now())
        offerUndo(.finish, restoring: before)
        _ = saveCurrentRecovery()
    }

    /// 直接進到下一段的起點；跳過的階段不算完成。超時中由「完成」取代，不做任何事。
    func skip() {
        guard !requiresRecoveryDecision else { return }
        refresh()
        guard !isOvertime else { return }
        closeUndoOffer()
        let before = run
        run.advance(completed: false, configuration: configuration)
        run.updateIdle(at: clock.now())
        offerUndo(.skip, restoring: before)
        _ = saveCurrentRecovery()
    }

    /// 目前階段回到完整長度並停止；重設的階段不算完成。超時中由「完成」取代，不做任何事。
    func reset() {
        guard !requiresRecoveryDecision else { return }
        refresh()
        // 停在起點時重設沒有變化，也就沒有可復原的
        guard !isOvertime, status != .idle else { return }
        closeUndoOffer()
        let before = run
        run.loadCurrentPhase(configuration)
        run.updateIdle(at: clock.now())
        offerUndo(.reset, restoring: before)
        _ = saveCurrentRecovery()
    }

    /// 退出先暫停目前階段，先前已按完成的紀錄才確立；取消退出也不自動完成或前進。
    @discardableResult
    func prepareToQuit() -> Bool {
        focusLog.retryIfNeeded()
        if requiresRecoveryDecision {
            return recoveryIssue == nil && !focusLog.hasUnsavedChanges
        }
        refresh()
        closeUndoOffer()
        run.engine.pause(at: clock.now())
        run.updateIdle(at: clock.now())
        let saved = saveCurrentRecovery()
        return saved && !focusLog.hasUnsavedChanges
    }

    // MARK: - 跨啟動恢復

    private func loadRecovery() {
        do {
            let completedWereRecovered = try recoveryStorage.recoverCompletions()
            // 先前交易可能已提交但遺失回報；重試也要讀回實際歷史。
            if completedWereRecovered || recoveryIssue == .load { focusLog.retry() }
            let loaded = try recoveryStorage.loadRecovery()
            if let loaded {
                guard loaded.isValid else { throw FocusStorageError.invalidData }
                run = PhaseRun(recovery: loaded.shiftingStart(by: -clock.systemClockOffset))
                focusProjectID = loaded.projectID
            }
            recovery = loaded
            recoveryLoaded = true
            recoveryIssue = nil
            run.idleSince = nil
        } catch {
            recoveryIssue = .load
            Self.recoveryLogger.error("載入恢復進度失敗，保留原資料：\(error)")
        }
    }

    private func checkpointRecovery(at now: Date, force: Bool) {
        guard recoveryIssue == nil,
              force || (run.engine.status(at: now) == .running
                        && (lastRecoveryCheckpointAt.map({ now.timeIntervalSince($0) >= Self.recoveryCheckpointInterval }) ?? true))
        else { return }
        _ = saveCurrentRecovery()
    }

    private func saveCurrentRecovery() -> Bool {
        writeRecovery(storable(run.engine.recovery(at: clock.now(), projectID: focusProjectID,
                                               completedFocuses: run.cycle.completedFocuses)), action: .save)
    }

    /// 存下的開始時刻是系統時間，重新開啟後才不會依上次啟動的時間解讀。
    private func storable(_ recovery: TimerRecovery?) -> TimerRecovery? {
        recovery?.shiftingStart(by: clock.systemClockOffset)
    }

    @discardableResult
    private func writeRecovery(
        _ value: TimerRecovery?, completions: [StoredFocusRecord]? = nil, action: RecoveryAction
    ) -> Bool {
        do {
            try recoveryStorage.saveCheckpoint(value, completions: completions ?? focusLog.recoveryCompletions)
            lastRecoveryCheckpointAt = clock.now()
            failedRecoveryAction = nil
            recoveryIssue = nil
            return true
        } catch {
            failedRecoveryAction = action
            recoveryIssue = .save
            Self.recoveryLogger.error("保存恢復進度失敗，等待重試：\(error)")
            return false
        }
    }

    func continueRecovery() {
        guard recovery != nil, recoveryLoaded else { return }
        // 分類還沒載入時不能把未知分類當作未分類完成。
        focusLog.retryIfNeeded()
        guard focusLog.issue != .load, writeRecovery(recovery, action: .continueSaved) else { return }
        recovery = nil
        run.resume(at: clock.now())
        run.idleSince = nil
    }

    func discardRecovery() {
        guard recovery != nil, recoveryLoaded, writeRecovery(nil, action: .discard) else { return }
        recovery = nil
        focusProjectID = nil
        run = PhaseRun(configuration: configuration, idleSince: clock.now())
    }

    func retryRecovery() {
        guard recoveryLoaded else { loadRecovery(); return }
        switch failedRecoveryAction {
        case .continueSaved: continueRecovery()
        case .discard: discardRecovery()
        case .save:
            focusLog.retryIfNeeded()
            _ = saveCurrentRecovery()
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
