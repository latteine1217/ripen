import Foundation
import Observation

/// 唯一的可觀察狀態根：對外只暴露操作意圖與可觀察狀態。
///
/// 時間相關的值（`status`、`remaining`）每次讀取都向注入的時鐘取「現在」，
/// 本身不會因時間流逝而發出變更通知；UI 需以 `TimelineView` 定期重讀。
@MainActor
@Observable
final class AppModel {
    private var engine = TimerEngine()
    @ObservationIgnored private let clock: any TimeSource

    init(clock: any TimeSource = SystemTimeSource()) {
        self.clock = clock
    }

    var phase: Phase { engine.phase }
    var status: TimerStatus { engine.status(at: clock.now()) }
    var remaining: TimeInterval { engine.remaining(at: clock.now()) }
    /// 目前階段的總長度，供進度計算。
    var phaseDuration: TimeInterval { engine.duration }
    var endDate: Date? { engine.endDate }

    // MARK: - 操作意圖

    func start() { engine.start(at: clock.now()) }
    func pause() { engine.pause(at: clock.now()) }
    func resume() { engine.resume(at: clock.now()) }
}
