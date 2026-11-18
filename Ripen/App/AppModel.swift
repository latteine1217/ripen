import Foundation
import Observation

/// 計時的可觀察狀態根：對外只暴露操作意圖與可觀察狀態。形態（畫面上有哪些介面）另由 `PresentationModel` 持有。
///
/// 時間相關的值（`status`、`remaining`、`isOvertime`、`overtime`）每次讀取都向注入的時鐘取「現在」，
/// 本身不會因時間流逝而發出變更通知；UI 需以 `TimelineView` 定期取用 `display`。
///
/// 倒數到 0 只是由時間推導出的超時（ADR-0006）：`refresh()` 發現時送出提醒，階段不前進；
/// 使用者按「完成」（`finish()`）才確立完成、記錄並前進到下一段。
///
/// 階段執行狀態的變更、恢復閘門與檢查點都在 `PhaseRunner`（ADR-0014）；這裡組裝它與提醒、在場與到點計時器。
/// 內部時刻都在 `clock.now()` 那一套不受系統時間調動的時間裡；交給畫面與提醒的時刻換算成目前的系統時間（ADR-0020）。
@MainActor
@Observable
final class AppModel {
    static let idleResetInterval = PhaseRun.idleResetInterval
    /// 跳過、重設、完成之後可以復原的時間。
    nonisolated static let undoWindow = PhaseRunner.undoWindow
    nonisolated static let completionSummaryDuration = PhaseRun.completionSummaryDuration

    @ObservationIgnored private let clock: any TimeSource
    /// 使用者設定；階段長度與長休息間隔每次需要時才讀，改動從下一段生效。
    @ObservationIgnored let settings: AppSettings
    /// 完成的專注紀錄，統計頁由此彙總；本身可觀察。
    @ObservationIgnored let focusLog: FocusLog
    /// 本身可觀察；下列讀取它的屬性因此也可觀察。
    @ObservationIgnored private let runner: PhaseRunner
    @ObservationIgnored private let presence: any UserPresence
    @ObservationIgnored private let reminderSound: any ReminderSound
    @ObservationIgnored private let alarm: any PhaseEndAlarm
    @ObservationIgnored private let notifier: any PhaseNotifier

    var recovery: TimerRecovery? { runner.recovery }
    var recoveryIssue: FocusLogIssue? { runner.recoveryIssue }
    var onRecoveryIssue: (() -> Void)? {
        get { runner.onRecoveryIssue }
        set { runner.onRecoveryIssue = newValue }
    }
    /// 等待恢復決定時按了全域熱鍵；App 叫出主視窗的恢復畫面並發出提示音（#79）。
    @ObservationIgnored var onHotkeyBlockedByRecovery: (() -> Void)?
    /// 尚未決定或載入失敗時，所有入口維持同一份恢復資料，不允許另開計時。
    var requiresRecoveryDecision: Bool { runner.requiresRecoveryDecision }
    /// 恢復進度的提示還在時不另外顯示紀錄的提示：它的重試也會重試紀錄，同一次失敗只有一則提示與一個重試。
    /// 恢復點之後保存成功、紀錄仍未寫入時，這則提示才接手，未保存的紀錄不會沒有提示。
    var showsFocusStorageNotice: Bool { recoveryIssue == nil && focusLog.issue != nil }

    private var run: PhaseRun { runner.run }
    /// 可觀察：每段只在跨過 0 時變一次，選單列選單靠它在那一刻換成「完成」，不必隨時間文字重建。
    var reachedZero: Bool { run.reachedZero }
    /// 離開期間倒數到 0、還沒播的提醒；回來時播。
    @ObservationIgnored private var pendingReminder: Phase?
    /// 最後一次播出的提醒；各介面觀察它的 `id` 播提醒動畫。
    private(set) var lastReminder: PhaseReminder?
    /// 目前可以復原的操作；各介面依它顯示復原膠囊，期限以系統時間表示。
    var undoOffer: UndoOffer? {
        runner.pendingUndo.map { UndoOffer(action: $0.offer.action, expiresAt: clock.systemDate(for: $0.offer.expiresAt)) }
    }
    /// 完成摘要；由 `refresh()` 收起。
    var completionSummary: CompletedFocus? { run.completionSummary }
    var recapShortcut: CompletedFocus? { run.recapShortcut }
    /// 緊接專注的休息期間、完成摘要已收起；拖出圓環的一次性提示在這時出現，不擋住摘要（#40）。
    var isRestingAfterFocus: Bool { recapShortcut != nil && completionSummary == nil }

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
        let focusLog = FocusLog(storage: storage)
        self.focusLog = focusLog
        self.presence = presence
        self.reminderSound = reminderSound
        self.alarm = alarm
        self.notifier = notifier
        runner = PhaseRunner(clock: clock, settings: settings, focusLog: focusLog, storage: storage)
        // 結束時刻一變就重排到點計時器；所有變更都經過 runner，不必逐一記得重排。
        runner.onRunChange = { [weak self] oldValue in self?.runDidChange(from: oldValue) }
        runner.onReachedZero = { [weak self] phase in
            self?.pendingReminder = phase
            self?.deliverPendingReminder()
        }
        presence.onLeave = { [weak self] leftAgo in self?.userDidLeave(leftAgo: leftAgo) }
        presence.onReturn = { [weak self] in self?.userDidReturn() }
        alarm.onFire = { [weak self] in self?.alarmDidFire() }
    }

    /// 只讀取一次注入時鐘；不呼叫 refresh，不發出提醒或確立完成。
    var display: PhaseDisplay {
        let now = clock.now()
        return PhaseDisplay(
            phase: run.engine.phase, status: run.engine.status(at: now), remaining: run.engine.remaining(at: now),
            isOvertime: run.engine.isOvertime(at: now), overtime: run.engine.overtime(at: now),
            phaseDuration: run.engine.duration, endDate: run.engine.endDate.map(clock.systemDate(for:)),
            completedFocusesInCycle: run.cycle.completedFocuses, longBreakInterval: longBreakInterval
        )
    }

    var phase: Phase { run.engine.phase }

    var status: TimerStatus { run.engine.status(at: clock.now()) }
    /// 倒數到 0 之後（含暫停中）；此時「跳過」「重設」由「完成」取代。
    var isOvertime: Bool { run.engine.isOvertime(at: clock.now()) }
    /// 目前階段的總長度，供進度計算。
    var phaseDuration: TimeInterval { run.engine.duration }
    var longBreakInterval: Int { runner.configuration.longBreakInterval }

    // MARK: - 分類

    /// 已開始（含暫停與超時）的專注；此時選分類是更正當次歸屬，其餘時候只影響下一次。
    var isFocusInProgress: Bool { runner.isFocusInProgress }

    /// 分類選單目前呈現的歸屬：進行中的專注顯示當次分類，否則是下一次的選擇。nil 是未分類。
    var currentProject: FocusProject? {
        focusLog.project(withID: isFocusInProgress ? runner.focusProjectID : settings.lastProjectID)
    }

    /// 選擇分類（nil 為未分類）。專注進行中時整次專注改歸這個分類，不拆分時間；
    /// 休息或尚未開始時只改下一次。不是計時操作，不結束復原機會，也不改動暫存的完成紀錄。
    func selectProject(_ id: UUID?) {
        runner.apply(.selectProject(id))
    }

    /// 新增並直接選取分類；空白名稱、同名或等待恢復決定時不建立，回傳 nil。
    @discardableResult
    func createProject(named name: String, color: ProjectColor? = nil) -> FocusProject? {
        guard let project = try? focusLog.apply(.addProject(name: name, color: color)).get() else { return nil }
        selectProject(project.id)
        return project
    }

    // MARK: - 刷新

    /// 套用由時間推導出的變化：離開時暫停超時、倒數到 0 的提醒、閒置歸零、改過的階段長度。
    ///
    /// 只送提醒，不會結束階段。intent、UI 刷新與系統喚醒時都應呼叫；重複呼叫無妨。
    func refresh() {
        runner.refresh()
    }

    // MARK: - 提醒與離開

    /// 離開超時就是這一段結束了，通知中心不留下過期的提醒。
    /// 超時中繼續時結束時刻在過去，不再排：提醒每段只送一次。
    private func runDidChange(from oldValue: PhaseRun) {
        if oldValue.reachedZero && !run.reachedZero { notifier.clearPhaseEndNotification() }
        guard run.engine.endDate != oldValue.engine.endDate else { return }
        scheduleAlarm()
    }

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
        runner.awaySince = clock.now() - leftAgo
        refresh()
    }

    /// 解鎖或喚醒：先依離開時刻暫停睡眠中跨過 0 的倒數並送出提醒（睡眠時 App 不執行），回來後停在暫停。
    private func userDidReturn() {
        refresh()
        runner.awaySince = nil
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

    // MARK: - 操作意圖

    // 意圖都經 `PhaseRunner.apply(_:)`：先刷新，再過恢復閘門、套用並保存檢查點。
    // 除了 undo() 之外的意圖都會結束上一個操作的復原機會。

    func start() { runner.apply(.start) }

    func pause() { runner.apply(.pause) }

    func resume() { runner.apply(.resume) }

    /// 單一按鍵的開始／暫停：依目前狀態開始、暫停或繼續。全域熱鍵與選單共用。
    ///
    /// 超時中同樣是暫停／繼續；結束這一段要按「完成」（ADR-0006）。
    /// 先刷新再看狀態：離開時自動暫停的超時要先套用，才會選到「繼續」。
    func toggleStartPause() { runner.apply(.toggleStartPause) }

    /// 全域熱鍵的開始／暫停。其他入口在畫面上顯示停用原因，熱鍵按下時畫面可能不在，
    /// 等待恢復決定時改請 App 叫出恢復畫面，不默默失效（#79）；其餘狀態與 `toggleStartPause()` 相同。
    func toggleStartPauseFromHotkey() {
        if runner.apply(.toggleStartPause) == .awaitingRecoveryDecision { onHotkeyBlockedByRecovery?() }
    }

    /// 「完成」：結束超時中的這一段、確立完成並進到下一段（ADR-0006）。倒數到 0 前不做任何事。
    func finish() { runner.apply(.finish) }

    /// 直接進到下一段的起點；跳過的階段不算完成。超時中由「完成」取代，不做任何事。
    func skip() { runner.apply(.skip) }

    /// 目前階段回到完整長度並停止；重設的階段不算完成。超時中由「完成」取代，不做任何事。
    func reset() { runner.apply(.reset) }

    /// 復原上一個跳過、重設或完成：換回操作前的狀態，暫存的完成紀錄一併捨棄。期限已過則不做任何事。
    ///
    /// 日誌先更新成功才生效（ADR-0014）。保存失敗時狀態與復原機會都不變，可以再按一次；期限到了照一般流程確立。
    func undo() { runner.apply(.undo) }

    /// 退出先暫停目前階段，先前已按完成的紀錄才確立；取消退出也不自動完成或前進。
    @discardableResult
    func prepareToQuit() -> Bool {
        focusLog.retryIfNeeded()
        let saved =
            switch runner.apply(.pauseForQuit) {
            case .awaitingRecoveryDecision: recoveryIssue == nil
            case .applied(let checkpointSaved): checkpointSaved
            case .unchanged, .rolledBack: false
            }
        return saved && !focusLog.hasUnsavedChanges
    }

    // MARK: - 跨啟動恢復

    func continueRecovery() { runner.continueRecovery() }

    func discardRecovery() { runner.discardRecovery() }

    func retryRecovery() { runner.retryRecovery() }
}
