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
    @ObservationIgnored private let configuration: CycleConfiguration
    private var cycle = PhaseCycle()
    private var engine: TimerEngine
    /// 這段閒置（沒有任何階段在跑，暫停也算）開始的時刻；有階段在跑時為 nil。
    @ObservationIgnored private var idleSince: Date?

    init(clock: any TimeSource = SystemTimeSource(), configuration: CycleConfiguration = .standard) {
        self.clock = clock
        self.configuration = configuration
        engine = TimerEngine(phase: .focus, duration: configuration.duration(for: .focus))
        idleSince = clock.now()
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

    // MARK: - 完成的確立

    /// 確立已倒數到 0 的完成，並套用閒置歸零。
    ///
    /// 若目前階段已倒數到 0，回傳它的完成並停在下一段的起點；同一段只會確立一次。
    /// intent、UI 刷新與系統喚醒時都應呼叫。
    @discardableResult
    func refresh() -> PhaseCompletion? {
        let now = clock.now()
        let completion = establishCompletion(at: now)
        resetCountIfIdle(at: now)
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
        cycle.advance(completed: true, longBreakInterval: configuration.longBreakInterval)
        loadCurrentPhase()
        // 閒置從倒數到 0 的那一刻算起，而不是確立的時刻（可能在睡眠很久之後）
        idleSince = endedAt
        return completion
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
