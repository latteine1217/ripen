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
@MainActor
@Observable
final class AppModel {
    /// 閒置滿這麼久，長休息間隔就重新計數（GLOSSARY）。
    static let idleResetInterval: TimeInterval = 2 * 60 * 60
    /// 跳過、重設、完成之後可以復原的時間。
    nonisolated static let undoWindow: TimeInterval = 5
    /// 完成摘要停留的時間；比復原期限短，收起後仍可復原。
    nonisolated static let completionSummaryDuration: TimeInterval = 3
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
    private static let recoveryLogger = Logger(subsystem: "com.latteine.ripen", category: "recovery")
    @ObservationIgnored private let recoveryStorage: any TimerRecoveryStorage
    private(set) var recovery: TimerRecovery?
    private(set) var recoveryIssue: FocusLogIssue? {
        didSet { if recoveryIssue != nil && recoveryIssue != oldValue { onRecoveryIssue?() } }
    }
    @ObservationIgnored var onRecoveryIssue: (() -> Void)?
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

    private var cycle = PhaseCycle()
    private var engine: TimerEngine {
        // 結束時刻一變就重排到點計時器；所有操作都經過 engine，不必逐一記得重排。
        // 超時中繼續時結束時刻在過去，不再排：提醒每段只送一次
        didSet {
            guard engine.endDate != oldValue.endDate else { return }
            alarm.schedule(at: engine.endDate.flatMap { $0 > clock.now() ? $0 : nil })
        }
    }
    /// 這段閒置開始的時刻；不在閒置時為 nil。沒有階段在跑就是閒置（暫停也算），
    /// 超時中則只有離開時被自動暫停才算，從自動暫停的那一刻起算。
    @ObservationIgnored private var idleSince: Date?
    /// 目前的暫停是離開時自動暫停的超時；使用者按繼續或換階段時清掉。
    @ObservationIgnored private var isPausedWhileAway = false
    /// 目前階段倒數到 0 的提醒是否已送出（含待播）；換階段時歸零。
    /// 可觀察：每段只在跨過 0 時變一次，選單列選單靠它在那一刻換成「完成」，不必隨時間文字重建。
    private(set) var reachedZero = false
    /// 離開期間倒數到 0、還沒播的提醒；回來時播。
    @ObservationIgnored private var pendingReminder: Phase?
    /// 使用者離開電腦的時刻；在場時為 nil。超時只算到這一刻（ADR-0006）。
    @ObservationIgnored private var awaySince: Date?
    /// 最後一次播出的提醒；各介面觀察它的 `id` 播提醒動畫。
    private(set) var lastReminder: PhaseReminder?
    /// 目前可以復原的操作；各介面依它顯示復原膠囊。
    var undoOffer: UndoOffer? { pendingUndo?.offer }
    /// 可以復原的操作與操作前的狀態，同生同滅；結束時一併確立（期限過了、有其他操作）或捨棄（復原）暫存的完成紀錄。
    private var pendingUndo: PendingUndo?
    /// 進行中專注的歸屬；開始專注時取自下次選擇，途中更正時一併改寫（ADR-0010）。
    private var focusProjectID: UUID?
    /// 完成摘要；完成專注後 3 秒內存在，由 `refresh()` 收起。
    private(set) var completionSummary: CompletedFocus?
    /// 休息期間的成果卡入口；保留到緊接的休息結束或被跳過。
    private(set) var recapShortcut: CompletedFocus?
    /// 緊接專注的休息期間、完成摘要已收起；拖出圓環的一次性提示在這時出現，不擋住摘要（#40）。
    var isRestingAfterFocus: Bool { recapShortcut != nil && completionSummary == nil }

    /// 操作前的計時狀態。引擎記的是結束時刻，換回後時間照牆上時鐘接著走（ADR-0002）。
    private struct Snapshot {
        let cycle: PhaseCycle
        let engine: TimerEngine
        let reachedZero: Bool
        let isPausedWhileAway: Bool
        let idleSince: Date?
        let completionSummary: CompletedFocus?
        let recapShortcut: CompletedFocus?
    }

    private struct PendingUndo {
        let offer: UndoOffer
        let snapshot: Snapshot
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
        alarm: any PhaseEndAlarm = NoPhaseEndAlarm()
    ) {
        self.clock = clock
        self.settings = settings
        self.focusLog = FocusLog(storage: storage)
        self.presence = presence
        self.reminderSound = reminderSound
        self.alarm = alarm
        self.recoveryStorage = storage
        let configuration = settings.cycleConfiguration
        cachedConfiguration = (settings.revision, configuration)
        engine = TimerEngine(phase: .focus, duration: configuration.duration(for: .focus))
        idleSince = clock.now()
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
            phase: engine.phase, status: engine.status(at: now), remaining: engine.remaining(at: now),
            isOvertime: engine.isOvertime(at: now), overtime: engine.overtime(at: now),
            phaseDuration: engine.duration, endDate: engine.endDate,
            completedFocusesInCycle: cycle.completedFocuses, longBreakInterval: configuration.longBreakInterval
        )
    }

    var phase: Phase { engine.phase }

    var status: TimerStatus { engine.status(at: clock.now()) }
    /// 倒數到 0 之後（含暫停中）；此時「跳過」「重設」由「完成」取代。
    var isOvertime: Bool { engine.isOvertime(at: clock.now()) }
    /// 目前階段的總長度，供進度計算。
    var phaseDuration: TimeInterval { engine.duration }
    var longBreakInterval: Int { configuration.longBreakInterval }

    // MARK: - 分類

    /// 已開始（含暫停與超時）的專注；此時選分類是更正當次歸屬，其餘時候只影響下一次。
    var isFocusInProgress: Bool { engine.phase == .focus && engine.startedAt != nil }

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
        completionSummary = movingToUncategorized(completionSummary, from: id)
        recapShortcut = movingToUncategorized(recapShortcut, from: id)
        _ = saveCurrentRecovery()
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
        let previousEngine = engine
        let previousCycle = cycle
        let previouslyReachedZero = reachedZero
        pauseOvertimeWhileAway(at: now)
        remindIfReachedZero(at: now)
        resetCountIfIdle(at: now)
        applyChangedLength(at: now)
        expireUndoOffer(at: now)
        expireCompletionSummary(at: now)
        checkpointRecovery(at: now, force: engine != previousEngine || cycle != previousCycle
                           || reachedZero != previouslyReachedZero)
    }

    /// 離開期間的超時不算：在離開的那一刻暫停；離開時還在倒數則停在 0（ADR-0006）。
    ///
    /// 睡眠時 App 不執行，可能要到回來才走到這裡；暫停時刻取自記下的離開時刻與結束時刻，不受刷新時機影響。
    /// 自動暫停的超時算閒置，從暫停的那一刻起算：整晚睡著時倒數跨過 0，隔天回來計數也會歸零。
    private func pauseOvertimeWhileAway(at now: Date) {
        guard let awaySince, let endDate = engine.endDate, endDate <= now else { return }
        let pausedAt = max(awaySince, endDate)
        engine.pause(at: pausedAt)
        isPausedWhileAway = true
        idleSince = pausedAt
    }

    /// 每段只提醒一次：繼續、重複刷新、到點計時器再觸發都不重播。
    private func remindIfReachedZero(at now: Date) {
        guard !reachedZero, engine.isOvertime(at: now) else { return }
        reachedZero = true
        pendingReminder = engine.phase
        deliverPendingReminder()
    }

    // MARK: - 完成的確立

    /// 這一段若在 `now` 完成會是怎樣的完成；倒數到 0 前為 nil。
    private func completion(at now: Date) -> PhaseCompletion? {
        guard engine.isOvertime(at: now), let startedAt = engine.startedAt else { return nil }
        return PhaseCompletion(phase: engine.phase, startedAt: startedAt, duration: engine.elapsed(at: now))
    }

    /// 完成的專注記錄實際長度，依開始時刻歸日（GLOSSARY）。
    /// 按「完成」時先暫存（還能復原）。回傳暫存的紀錄（分類已確認）；休息不回傳。
    @discardableResult
    private func recordIfFocus(_ completion: PhaseCompletion) -> FocusRecord? {
        guard completion.phase == .focus else { return nil }
        let record = FocusRecord(startedAt: completion.startedAt, duration: completion.duration, projectID: focusProjectID)
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
        completionSummary = completed
        recapShortcut = completed
    }

    private func expireCompletionSummary(at now: Date) {
        guard let completionSummary, now >= completionSummary.completedAt + Self.completionSummaryDuration else { return }
        self.completionSummary = nil
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
        let restored = snapshot.engine.recovery(at: clock.now(), projectID: focusProjectID,
                                                completedFocuses: snapshot.cycle.completedFocuses)
        guard writeRecovery(restored, completions: focusLog.completionsWithoutStaged, action: .save) else { return }
        focusLog.discardStaged()
        cycle = snapshot.cycle
        engine = snapshot.engine
        reachedZero = snapshot.reachedZero
        isPausedWhileAway = snapshot.isPausedWhileAway
        idleSince = snapshot.idleSince
        completionSummary = snapshot.completionSummary
        recapShortcut = snapshot.recapShortcut
        // 換回的摘要可能已過了顯示時間，不重播
        expireCompletionSummary(at: clock.now())
        pendingUndo = nil
    }

    private func snapshot() -> Snapshot {
        Snapshot(cycle: cycle, engine: engine, reachedZero: reachedZero,
                 isPausedWhileAway: isPausedWhileAway, idleSince: idleSince,
                 completionSummary: completionSummary, recapShortcut: recapShortcut)
    }

    private func offerUndo(_ action: UndoableAction, restoring snapshot: Snapshot) {
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
        guard let undoOffer, now >= undoOffer.expiresAt else { return }
        closeUndoOffer()
    }

    // MARK: - 提醒與離開

    /// 使用者在場才播；離開時留在待播，回來再播（ADR-0002）。
    private func deliverPendingReminder() {
        guard let phase = pendingReminder, !presence.isAway else { return }
        pendingReminder = nil
        if settings.completionSoundEnabled { reminderSound.play(named: settings.reminderSoundName) }
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

    private func alarmDidFire() {
        refresh()
        // 計時器可能比結束時刻早一點觸發；還沒到 0 就重排，否則視窗關閉時提醒永遠不會送出
        let now = clock.now()
        if engine.status(at: now) == .running, !engine.isOvertime(at: now) {
            alarm.schedule(at: engine.endDate)
        }
    }

    private func resetCountIfIdle(at now: Date) {
        guard let idleSince, now.timeIntervalSince(idleSince) >= Self.idleResetInterval else { return }
        // 只在真的有變化時寫入：閒置期間每次刷新都會走到這裡，避免無謂的觀察通知
        // 停在休息起點等待的話，改從第 1 次專注開始；暫停中的階段（含自動暫停的超時）保留，由使用者決定
        if engine.status(at: now) == .idle, cycle.phase != .focus {
            cycle = PhaseCycle()
            loadCurrentPhase()
        } else if cycle.completedFocuses != 0 {
            cycle.resetCount()
        }
    }

    // MARK: - 設定的套用

    /// 「自動開始下一段」開啟時，按完成的那一刻就開始下一段（ADR-0006）。
    private func startNextPhaseAutomatically(now: Date) {
        guard settings.autoStartNextPhase else { return }
        startEngine(at: now)
    }

    /// 改階段長度從下一段生效；停在起點、還沒開始的階段不算在跑，直接換成新長度。
    private func applyChangedLength(at now: Date) {
        guard engine.status(at: now) == .idle,
              engine.duration != configuration.duration(for: engine.phase)
        else { return }
        loadCurrentPhase()
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

    // 以下是已刷新過的意圖本體，讓 toggleStartPause() 只刷新一次。

    private func startRefreshed() {
        startEngine(at: clock.now())
        updateIdleSince()
        _ = saveCurrentRecovery()
    }

    /// 專注從起點開始時確定當次歸屬。選擇是否已失效由 `FocusLog` 在歷史載入後判定，
    /// 載入失敗時不能把仍有效的選擇當成未分類。
    private func startEngine(at now: Date) {
        if engine.phase == .focus, engine.status(at: now) == .idle {
            focusProjectID = settings.lastProjectID
        }
        engine.start(at: now)
    }

    private func pauseRefreshed() {
        engine.pause(at: clock.now())
        updateIdleSince()
        _ = saveCurrentRecovery()
    }

    private func resumeRefreshed() {
        engine.resume(at: clock.now())
        isPausedWhileAway = false
        updateIdleSince()
        _ = saveCurrentRecovery()
    }

    /// 「完成」：結束超時中的這一段、確立完成並進到下一段（ADR-0006）。倒數到 0 前不做任何事。
    func finish() {
        guard !requiresRecoveryDecision else { return }
        refresh()
        let now = clock.now()
        guard let completion = completion(at: now) else { return }
        closeUndoOffer()
        let before = snapshot()
        // 前進後已是下一段的起點，再按一次完成不會重複記錄
        let record = recordIfFocus(completion)
        cycle.advance(completed: true, longBreakInterval: configuration.longBreakInterval)
        loadCurrentPhase()
        if let record { presentCompletion(of: record, at: now) }
        startNextPhaseAutomatically(now: now)
        updateIdleSince()
        offerUndo(.finish, restoring: before)
        _ = saveCurrentRecovery()
    }

    /// 直接進到下一段的起點；跳過的階段不算完成。超時中由「完成」取代，不做任何事。
    func skip() {
        guard !requiresRecoveryDecision else { return }
        refresh()
        guard !isOvertime else { return }
        closeUndoOffer()
        let before = snapshot()
        cycle.advance(completed: false, longBreakInterval: configuration.longBreakInterval)
        loadCurrentPhase()
        updateIdleSince()
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
        let before = snapshot()
        loadCurrentPhase()
        updateIdleSince()
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
        engine.pause(at: clock.now())
        updateIdleSince()
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
                engine = TimerEngine(recovery: loaded)
                cycle = PhaseCycle(phase: loaded.phase, completedFocuses: loaded.completedFocuses)
                focusProjectID = loaded.projectID
                reachedZero = loaded.remaining <= 0
            }
            recovery = loaded
            recoveryLoaded = true
            recoveryIssue = nil
            idleSince = nil
        } catch {
            recoveryIssue = .load
            Self.recoveryLogger.error("載入恢復進度失敗，保留原資料：\(error)")
        }
    }

    private func checkpointRecovery(at now: Date, force: Bool) {
        guard recoveryIssue == nil,
              force || (engine.status(at: now) == .running
                        && (lastRecoveryCheckpointAt.map({ now.timeIntervalSince($0) >= Self.recoveryCheckpointInterval }) ?? true))
        else { return }
        _ = saveCurrentRecovery()
    }

    private func saveCurrentRecovery() -> Bool {
        writeRecovery(engine.recovery(at: clock.now(), projectID: focusProjectID,
                                      completedFocuses: cycle.completedFocuses), action: .save)
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
        engine.resume(at: clock.now())
        idleSince = nil
        isPausedWhileAway = false
    }

    func discardRecovery() {
        guard recovery != nil, recoveryLoaded, writeRecovery(nil, action: .discard) else { return }
        recovery = nil
        focusProjectID = nil
        cycle = PhaseCycle()
        loadCurrentPhase()
        idleSince = clock.now()
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

    /// 開始跑或在超時中就不是閒置，離開時自動暫停的超時除外；停下來的那一刻開始閒置。已在閒置中的操作不重新計時。
    private func updateIdleSince() {
        let now = clock.now()
        if engine.status(at: now) == .running || (engine.isOvertime(at: now) && !isPausedWhileAway) {
            idleSince = nil
        } else if idleSince == nil {
            idleSince = now
        }
    }

    /// 換上循環目前所在的階段，處於起點、尚未開始。
    /// 回到專注就離開了緊接完成的那段休息（結束、跳過或閒置歸零），摘要與成果卡入口一併結束。
    private func loadCurrentPhase() {
        engine = TimerEngine(phase: cycle.phase, duration: configuration.duration(for: cycle.phase))
        reachedZero = false
        isPausedWhileAway = false
        if cycle.phase == .focus {
            completionSummary = nil
            recapShortcut = nil
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
