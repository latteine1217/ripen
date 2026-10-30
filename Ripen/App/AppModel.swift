import Foundation
import Observation

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
    /// 可觀察：每段只在跨過 0 時變一次，選單列選單靠它在那一刻換成「完成」，不必隨時間文字重建。
    private(set) var reachedZero = false
    /// 離開期間倒數到 0、還沒播的提醒；回來時播。
    @ObservationIgnored private var pendingReminder: Phase?
    /// 使用者離開電腦的時刻；在場時為 nil。超時只算到這一刻（ADR-0006）。
    @ObservationIgnored private var awaySince: Date?
    /// 最後一次播出的提醒；各介面觀察它的 `id` 播提醒動畫。
    private(set) var lastReminder: PhaseReminder?
    /// 目前可以復原的操作；各介面依它顯示復原膠囊。
    private(set) var undoOffer: UndoOffer?
    /// 復原時要換回的狀態，與 `undoOffer` 同生同滅。
    @ObservationIgnored private var undoSnapshot: Snapshot?
    /// 進行中專注的歸屬；開始專注時取自下次選擇，途中更正時一併改寫（ADR-0010）。
    private var focusProjectID: UUID?

    /// 操作前的計時狀態。引擎記的是結束時刻，換回後時間照牆上時鐘接著走（ADR-0002）。
    private struct Snapshot {
        let cycle: PhaseCycle
        let engine: TimerEngine
        let reachedZero: Bool
        let isPausedWhileAway: Bool
        let idleSince: Date?
    }

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
        let configuration = settings.cycleConfiguration
        cachedConfiguration = (settings.revision, configuration)
        engine = TimerEngine(phase: .focus, duration: configuration.duration(for: .focus))
        idleSince = clock.now()
        presence.onLeave = { [weak self] leftAgo in self?.userDidLeave(leftAgo: leftAgo) }
        presence.onReturn = { [weak self] in self?.userDidReturn() }
        alarm.onFire = { [weak self] in self?.alarmDidFire() }
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
        settings.lastProjectID = id
        if isFocusInProgress { focusProjectID = id }
    }

    /// 新增並直接選取分類；空白名稱不建立，回傳 nil。
    @discardableResult
    func createProject(named name: String, color: ProjectColor? = nil) -> FocusProject? {
        guard let project = focusLog.addProject(named: name, color: color) else { return nil }
        selectProject(project.id)
        return project
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
        let now = clock.now()
        pauseOvertimeWhileAway(at: now)
        remindIfReachedZero(at: now)
        resetCountIfIdle(at: now)
        applyChangedLength(at: now)
        expireUndoOffer(at: now)
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

    /// 完成的專注記錄實際長度，依開始時刻歸日（GLOSSARY）。
    /// 按「完成」時先暫存（還能復原），⌘Q 時直接寫檔。
    private func recordIfFocus(_ completion: PhaseCompletion, undoable: Bool) {
        guard completion.phase == .focus else { return }
        let record = FocusRecord(startedAt: completion.startedAt, duration: completion.duration, projectID: focusProjectID)
        if undoable { focusLog.stage(record) } else { focusLog.append(record) }
    }

    // MARK: - 復原

    /// 復原上一個跳過、重設或完成：換回操作前的狀態，暫存的完成紀錄一併捨棄。期限已過則不做任何事。
    func undo() {
        refresh()
        guard undoOffer != nil, let snapshot = undoSnapshot else { return }
        focusLog.discardStaged()
        cycle = snapshot.cycle
        engine = snapshot.engine
        reachedZero = snapshot.reachedZero
        isPausedWhileAway = snapshot.isPausedWhileAway
        idleSince = snapshot.idleSince
        undoOffer = nil
        undoSnapshot = nil
    }

    private func snapshot() -> Snapshot {
        Snapshot(cycle: cycle, engine: engine, reachedZero: reachedZero,
                 isPausedWhileAway: isPausedWhileAway, idleSince: idleSince)
    }

    private func offerUndo(_ action: UndoableAction, restoring snapshot: Snapshot) {
        undoSnapshot = snapshot
        undoOffer = UndoOffer(action: action, expiresAt: clock.now() + Self.undoWindow)
    }

    /// 其他操作出現或期限已過，復原機會結束；暫存的完成紀錄在此寫入。
    private func closeUndoOffer() {
        undoOffer = nil
        undoSnapshot = nil
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
        refresh()
        closeUndoOffer()
        startRefreshed()
    }

    func pause() {
        refresh()
        closeUndoOffer()
        pauseRefreshed()
    }

    func resume() {
        refresh()
        closeUndoOffer()
        resumeRefreshed()
    }

    /// 單一按鍵的開始／暫停：依目前狀態開始、暫停或繼續。全域熱鍵與選單共用。
    ///
    /// 超時中同樣是暫停／繼續；結束這一段要按「完成」（ADR-0006）。
    /// 先刷新再看狀態：離開時自動暫停的超時要先套用，才會選到「繼續」。
    func toggleStartPause() {
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
    }

    private func resumeRefreshed() {
        engine.resume(at: clock.now())
        isPausedWhileAway = false
        updateIdleSince()
    }

    /// 「完成」：結束超時中的這一段、確立完成並進到下一段（ADR-0006）。倒數到 0 前不做任何事。
    func finish() {
        refresh()
        let now = clock.now()
        guard let completion = completion(at: now) else { return }
        closeUndoOffer()
        let before = snapshot()
        // 前進後已是下一段的起點，再按一次完成不會重複記錄
        recordIfFocus(completion, undoable: true)
        cycle.advance(completed: true, longBreakInterval: configuration.longBreakInterval)
        loadCurrentPhase()
        startNextPhaseAutomatically(now: now)
        updateIdleSince()
        offerUndo(.finish, restoring: before)
    }

    /// 直接進到下一段的起點；跳過的階段不算完成。超時中由「完成」取代，不做任何事。
    func skip() {
        refresh()
        guard !isOvertime else { return }
        closeUndoOffer()
        let before = snapshot()
        cycle.advance(completed: false, longBreakInterval: configuration.longBreakInterval)
        loadCurrentPhase()
        updateIdleSince()
        offerUndo(.skip, restoring: before)
    }

    /// 目前階段回到完整長度並停止；重設的階段不算完成。超時中由「完成」取代，不做任何事。
    func reset() {
        refresh()
        // 停在起點時重設沒有變化，也就沒有可復原的
        guard !isOvertime, status != .idle else { return }
        closeUndoOffer()
        let before = snapshot()
        loadCurrentPhase()
        updateIdleSince()
        offerUndo(.reset, restoring: before)
    }

    /// App 結束（⌘Q）前呼叫：超時中的專注已是完成的專注，以此刻的實際長度記錄（ADR-0006）。
    ///
    /// 取消退出時已完成的專注不重複記錄，停在下一段起點，不自動開始。
    /// 回傳 false 表示仍有未保存紀錄，呼叫端必須先詢問是否放棄。
    @discardableResult
    func prepareToQuit() -> Bool {
        if focusLog.issue != nil { focusLog.retry() }
        refresh()
        // 退出就不能再復原：暫存的完成紀錄先確立
        closeUndoOffer()
        if let completion = completion(at: clock.now()) {
            recordIfFocus(completion, undoable: false)
            cycle.advance(completed: true, longBreakInterval: configuration.longBreakInterval)
            loadCurrentPhase()
            updateIdleSince()
        }
        return !focusLog.hasUnsavedChanges
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
