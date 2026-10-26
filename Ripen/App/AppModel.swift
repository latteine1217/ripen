import Foundation
import Observation

/// 唯一的可觀察狀態根：對外只暴露操作意圖與可觀察狀態。
///
/// 時間相關的值（`status`、`remaining`）每次讀取都向注入的時鐘取「現在」，
/// 本身不會因時間流逝而發出變更通知；UI 需以 `TimelineView` 定期重讀。
///
/// 倒數到 0 只是由時間推導出的狀態（`status == .finished`）；
/// 「完成」要等 `refresh()` 才確立，確立時才前進到下一段。
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
        // 結束時刻一變就重排到點計時器；所有操作都經過 engine，不必逐一記得重排
        didSet { if engine.endDate != oldValue.endDate { alarm.schedule(at: engine.endDate) } }
    }
    /// 這段閒置（沒有任何階段在跑，暫停也算）開始的時刻；有階段在跑時為 nil。
    @ObservationIgnored private var idleSince: Date?
    /// 離開期間倒數到 0、還沒播的提醒。多段完成只保留最後一段：回來時只響一次。
    @ObservationIgnored private var pendingReminder: PhaseCompletion?
    /// 最後一次播出的提醒；各介面觀察它的 `id` 播換階段動畫。
    private(set) var lastReminder: PhaseReminder?

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
        presence.onReturn = { [weak self] in self?.userDidReturn() }
        alarm.onFire = { [weak self] in self?.alarmDidFire() }
    }

    var phase: Phase { engine.phase }
    var status: TimerStatus { engine.status(at: clock.now()) }
    var remaining: TimeInterval { engine.remaining(at: clock.now()) }
    /// 目前階段的總長度，供進度計算。
    var phaseDuration: TimeInterval { engine.duration }
    var endDate: Date? { engine.endDate }
    /// 距離上次長休息已完成的專注次數。
    var completedFocusesInCycle: Int { cycle.completedFocuses }
    var longBreakInterval: Int { configuration.longBreakInterval }
    private var configuration: CycleConfiguration { settings.cycleConfiguration }

    // MARK: - 完成的確立

    /// 確立已倒數到 0 的完成，並套用閒置歸零。
    ///
    /// 若目前階段已倒數到 0，回傳它的完成並停在下一段的起點；同一段只會確立一次。
    /// intent、UI 刷新與系統喚醒時都應呼叫。
    @discardableResult
    func refresh() -> PhaseCompletion? {
        let now = clock.now()
        let completion = establishCompletion(at: now)
        if let completion { startBreakAutomatically(after: completion, now: now) }
        resetCountIfIdle(at: now)
        applyChangedLength(at: now)
        return completion
    }

    private func establishCompletion(at now: Date) -> PhaseCompletion? {
        guard engine.status(at: now) == .finished,
              let endedAt = engine.endDate, let startedAt = engine.startedAt
        else { return nil }

        let completion = PhaseCompletion(
            phase: engine.phase, startedAt: startedAt, endedAt: endedAt, duration: engine.duration
        )
        // 完成的副作用（統計、提醒）接在這裡：intent 會丟棄 refresh() 的回傳值，只有這裡保證每段恰好一次
        if completion.phase == .focus {
            focusLog.append(FocusRecord(startedAt: startedAt, duration: completion.duration))
        }
        cycle.advance(completed: true, longBreakInterval: configuration.longBreakInterval)
        loadCurrentPhase()
        // 閒置從倒數到 0 的那一刻算起，而不是確立的時刻（可能在睡眠很久之後）
        idleSince = endedAt
        pendingReminder = completion
        deliverPendingReminder()
        return completion
    }

    // MARK: - 提醒

    /// 使用者在場才播；離開時留在待播，回來再播（ADR-0002）。
    private func deliverPendingReminder() {
        guard let completion = pendingReminder, !presence.isAway else { return }
        pendingReminder = nil
        if settings.completionSoundEnabled { reminderSound.play() }
        lastReminder = PhaseReminder(id: (lastReminder?.id ?? 0) + 1, completion: completion)
    }

    /// 解鎖或喚醒：先確立睡眠中倒數到 0 的完成（睡眠時 App 不執行），再播待播的提醒。
    private func userDidReturn() {
        refresh()
        deliverPendingReminder()
    }

    private func alarmDidFire() {
        refresh()
        // 計時器可能比結束時刻早一點觸發；還沒到 0 就重排，否則視窗關閉時這段永遠不會確立
        if engine.status(at: clock.now()) == .running { alarm.schedule(at: engine.endDate) }
    }

    private func resetCountIfIdle(at now: Date) {
        guard let idleSince, now.timeIntervalSince(idleSince) >= Self.idleResetInterval else { return }
        // 只在真的有變化時寫入：閒置期間每次刷新都會走到這裡，避免無謂的觀察通知
        // 停在休息起點等待的話，改從第 1 次專注開始；暫停中的階段保留，由使用者決定
        if engine.status(at: now) == .idle, cycle.phase != .focus {
            cycle = PhaseCycle()
            loadCurrentPhase()
        } else if cycle.completedFocuses != 0 {
            cycle.resetCount()
        }
    }

    // MARK: - 設定的套用

    /// 「自動開始休息」開啟時，休息從專注倒數到 0 的那一刻開始，而不是確立的時刻（ADR-0002）。
    ///
    /// 若照這樣算休息到現在也已結束（睡眠或鎖定很久），代表使用者不在，休息改停在起點等他。
    private func startBreakAutomatically(after completion: PhaseCompletion, now: Date) {
        guard completion.phase == .focus, settings.autoStartBreaks,
              now < completion.endedAt + engine.duration
        else { return }
        engine.start(at: completion.endedAt)
        idleSince = nil
    }

    /// 改階段長度從下一段生效；停在起點、還沒開始的階段不算在跑，直接換成新長度。
    private func applyChangedLength(at now: Date) {
        guard engine.status(at: now) == .idle,
              engine.duration != configuration.duration(for: engine.phase)
        else { return }
        loadCurrentPhase()
    }

    // MARK: - 操作意圖

    // 每個意圖先 refresh()：已倒數到 0 卻還沒確立的階段，要先前進到下一段再處理意圖。

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
        updateIdleSince()
    }

    /// 直接進到下一段的起點；跳過的階段不算完成。
    func skip() {
        // 剛確立完成就已停在下一段起點；再前進會把使用者沒看到的下一段也跳過
        guard refresh() == nil else { return }
        cycle.advance(completed: false, longBreakInterval: configuration.longBreakInterval)
        loadCurrentPhase()
        updateIdleSince()
    }

    /// 目前階段回到完整長度並停止；重設的階段不算完成。
    func reset() {
        refresh()
        loadCurrentPhase()
        updateIdleSince()
    }

    /// 開始跑就結束閒置；停下來的那一刻開始閒置。已在閒置中的操作不重新計時。
    private func updateIdleSince() {
        if engine.status(at: clock.now()) == .running {
            idleSince = nil
        } else if idleSince == nil {
            idleSince = clock.now()
        }
    }

    /// 換上循環目前所在的階段，處於起點、尚未開始。
    private func loadCurrentPhase() {
        engine = TimerEngine(phase: cycle.phase, duration: configuration.duration(for: cycle.phase))
    }
}

/// 一段倒數到 0 而確立完成的階段。
struct PhaseCompletion: Equatable, Sendable {
    let phase: Phase
    /// 第一次開始的時刻；完成的專注歸屬於它所在的日期（ADR-0002）。
    let startedAt: Date
    /// 倒數到 0 的時刻；在睡眠中結束時早於確立的時刻。
    let endedAt: Date
    let duration: TimeInterval
}
