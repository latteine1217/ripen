import Foundation
import Observation

/// 唯一的可觀察狀態根：對外只暴露操作意圖與可觀察狀態。
///
/// 時間相關的值（`status`、`remaining`、`isOvertime`、`overtime`）每次讀取都向注入的時鐘取「現在」，
/// 本身不會因時間流逝而發出變更通知；UI 需以 `TimelineView` 定期重讀。
///
/// 倒數到 0 只是由時間推導出的超時（ADR-0006）：`refresh()` 發現時送出提醒，階段不前進；
/// 使用者按「完成」（`finish()`）才確立完成、記錄並前進到下一段。
@MainActor
@Observable
final class AppModel {
    /// 閒置滿這麼久，長休息間隔就重新計數（GLOSSARY）。
    static let idleResetInterval: TimeInterval = 2 * 60 * 60

    @ObservationIgnored private let clock: any TimeSource
    /// 使用者設定；階段長度與長休息間隔每次需要時才讀，改動從下一段生效。
    @ObservationIgnored let settings: AppSettings
    /// 完成的專注紀錄，統計頁由此彙總；本身可觀察。
    @ObservationIgnored let focusLog: FocusLog
    @ObservationIgnored private let presence: any UserPresence
    @ObservationIgnored private let reminderSound: any ReminderSound
    @ObservationIgnored private let alarm: any PhaseEndAlarm
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
    @ObservationIgnored private var reachedZero = false
    /// 離開期間倒數到 0、還沒播的提醒；回來時播。
    @ObservationIgnored private var pendingReminder: Phase?
    /// 使用者離開電腦的時刻；在場時為 nil。超時只算到這一刻（ADR-0006）。
    @ObservationIgnored private var awaySince: Date?
    /// 最後一次播出的提醒；各介面觀察它的 `id` 播提醒動畫。
    private(set) var lastReminder: PhaseReminder?
    /// 畫面上有哪些介面；主視窗與各 panel 只依它顯示或隱藏（ADR-0003）。
    private(set) var presentation = Presentation.mainWindowOnly
    /// 造成目前形態的操作。同一對形態可能來自不同操作（例如並存時的紅色與黃色按鈕），
    /// 過場依它選擇；在 `presentation` 之前寫入，觀察到形態改變時已是新值。
    @ObservationIgnored private(set) var lastPresentationAction: PresentationAction?
    /// 每套用一個改變畫面的操作加一。再拖出一次時形態不變，畫面要靠它得知換成新的懸浮窗（#16）。
    private(set) var presentationRevision = 0

    /// 未指定的依賴一律用不碰系統的版本：測試與預覽不讀寫真正的設定、不出聲。
    init(
        clock: any TimeSource = SystemTimeSource(),
        settings: AppSettings = AppSettings(storage: InMemorySettingsStorage()),
        focusLog: FocusLog = FocusLog(),
        presence: any UserPresence = AlwaysPresent(),
        reminderSound: any ReminderSound = SilentReminderSound(),
        alarm: any PhaseEndAlarm = NoPhaseEndAlarm()
    ) {
        self.clock = clock
        self.settings = settings
        self.focusLog = focusLog
        self.presence = presence
        self.reminderSound = reminderSound
        self.alarm = alarm
        engine = TimerEngine(phase: .focus, duration: settings.cycleConfiguration.duration(for: .focus))
        idleSince = clock.now()
        presence.onLeave = { [weak self] in self?.userDidLeave() }
        presence.onReturn = { [weak self] in self?.userDidReturn() }
        alarm.onFire = { [weak self] in self?.alarmDidFire() }
    }

    var phase: Phase { engine.phase }
    var status: TimerStatus { engine.status(at: clock.now()) }
    var remaining: TimeInterval { engine.remaining(at: clock.now()) }
    /// 倒數到 0 之後（含暫停中）；此時「跳過」「重設」由「完成」取代。
    var isOvertime: Bool { engine.isOvertime(at: clock.now()) }
    /// 倒數到 0 之後經過的時間，不含暫停；未超時為 0。
    var overtime: TimeInterval { engine.overtime(at: clock.now()) }
    /// 目前階段的總長度，供進度計算。
    var phaseDuration: TimeInterval { engine.duration }
    var endDate: Date? { engine.endDate }
    /// 距離上次長休息已完成的專注次數。
    var completedFocusesInCycle: Int { cycle.completedFocuses }
    var longBreakInterval: Int { configuration.longBreakInterval }
    private var configuration: CycleConfiguration { settings.cycleConfiguration }

    // MARK: - 刷新

    /// 套用由時間推導出的變化：離開時暫停超時、倒數到 0 的提醒、閒置歸零、改過的階段長度。
    ///
    /// 只送提醒，不會結束階段。intent、UI 刷新與系統喚醒時都應呼叫；重複呼叫無妨。
    func refresh() {
        let now = clock.now()
        pauseOvertimeWhileAway(at: now)
        remindIfReachedZero(at: now)
        resetCountIfIdle(at: now)
        applyChangedLength(at: now)
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

    /// 這一段若在 `now` 完成會是怎樣的完成；倒數到 0 前為 nil。「完成」與 ⌘Q 共用這個長度定義。
    private func completion(at now: Date) -> PhaseCompletion? {
        guard engine.isOvertime(at: now), let startedAt = engine.startedAt else { return nil }
        return PhaseCompletion(phase: engine.phase, startedAt: startedAt, duration: engine.elapsed(at: now))
    }

    /// 完成的專注記錄實際長度，依開始時刻歸日（GLOSSARY）；FocusLog 同步寫檔。
    private func recordIfFocus(_ completion: PhaseCompletion) {
        guard completion.phase == .focus else { return }
        focusLog.append(FocusRecord(startedAt: completion.startedAt, duration: completion.duration))
    }

    // MARK: - 提醒與離開

    /// 使用者在場才播；離開時留在待播，回來再播（ADR-0002）。
    private func deliverPendingReminder() {
        guard let phase = pendingReminder, !presence.isAway else { return }
        pendingReminder = nil
        if settings.completionSoundEnabled { reminderSound.play() }
        lastReminder = PhaseReminder(id: (lastReminder?.id ?? 0) + 1, phase: phase)
    }

    /// 鎖定、睡眠或螢幕關閉：記下離開的時刻；已在超時中就立即暫停。
    private func userDidLeave() {
        awaySince = clock.now()
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
        engine.start(at: now)
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

    func start() {
        refresh()
        engine.start(at: clock.now())
        updateIdleSince()
    }

    func pause() {
        refresh()
        engine.pause(at: clock.now())
        updateIdleSince()
    }

    func resume() {
        refresh()
        engine.resume(at: clock.now())
        isPausedWhileAway = false
        updateIdleSince()
    }

    /// 「完成」：結束超時中的這一段、確立完成並進到下一段（ADR-0006）。倒數到 0 前不做任何事。
    func finish() {
        refresh()
        let now = clock.now()
        guard let completion = completion(at: now) else { return }
        // 前進後已是下一段的起點，再按一次完成不會重複記錄
        recordIfFocus(completion)
        cycle.advance(completed: true, longBreakInterval: configuration.longBreakInterval)
        loadCurrentPhase()
        startNextPhaseAutomatically(now: now)
        updateIdleSince()
    }

    /// 直接進到下一段的起點；跳過的階段不算完成。超時中由「完成」取代，不做任何事。
    func skip() {
        refresh()
        guard !isOvertime else { return }
        cycle.advance(completed: false, longBreakInterval: configuration.longBreakInterval)
        loadCurrentPhase()
        updateIdleSince()
    }

    /// 目前階段回到完整長度並停止；重設的階段不算完成。超時中由「完成」取代，不做任何事。
    func reset() {
        refresh()
        guard !isOvertime else { return }
        loadCurrentPhase()
        updateIdleSince()
    }

    /// App 結束（⌘Q）前呼叫：超時中的專注已是完成的專注，以此刻的實際長度記錄（ADR-0006）。
    ///
    /// 階段狀態不保存（ADR-0002），所以只記錄、不前進；寫檔是同步的，回傳時已存好。
    func prepareToQuit() {
        refresh()
        if let completion = completion(at: clock.now()) { recordIfFocus(completion) }
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

    // MARK: - 形態

    // 形態與計時無關：不刷新計時、不影響閒置。

    /// 主視窗的紅色按鈕（ADR-0001）。
    func closeMainWindow() { apply(.closeMainWindow) }

    /// 主視窗的黃色按鈕或 ⌘M：主視窗變形成懸浮窗。
    func minimizeMainWindow() { apply(.minimizeMainWindow) }

    /// 懸浮窗的「展開」：懸浮窗變形成主視窗。
    func expandFloatingWindow() { apply(.expandFloatingWindow) }

    /// 懸浮窗的 ✕：主視窗在畫面上時只關懸浮窗，否則收進瀏海。
    func closeFloatingWindow() { apply(.closeFloatingWindow) }

    /// 把主視窗拖到瀏海附近放開。
    func collapseIntoNotch() { apply(.collapseIntoNotch) }

    /// 拉出瀏海島或按島上的「展開」。
    func expandNotchIsland() { apply(.expandNotchIsland) }

    /// 點 Dock 圖示或選單列的「顯示主視窗」。
    func showMainWindow() { apply(.showMainWindow) }

    /// 把計時圓環拖到主視窗外放開：在放開處產生懸浮窗，主視窗保留（#16）。
    func tearOffTimerRing() { apply(.tearOffTimerRing) }

    /// 轉換表中沒有這一格時忽略：操作可能來自已在過場中消失的介面。
    private func apply(_ action: PresentationAction) {
        guard let next = presentation.applying(action),
              next != presentation || action.replacesFloatingWindow else { return }
        lastPresentationAction = action
        presentationRevision += 1
        presentation = next
    }

    /// 換上循環目前所在的階段，處於起點、尚未開始。
    private func loadCurrentPhase() {
        engine = TimerEngine(phase: cycle.phase, duration: configuration.duration(for: cycle.phase))
        reachedZero = false
        isPausedWhileAway = false
    }
}

/// 一段倒數到過 0、由「完成」或 ⌘Q 確立完成的階段。
struct PhaseCompletion: Equatable, Sendable {
    let phase: Phase
    /// 第一次開始的時刻；完成的專注歸屬於它所在的日期（ADR-0002）。
    let startedAt: Date
    /// 實際長度：設定長度加超時，扣掉暫停。
    let duration: TimeInterval
}
