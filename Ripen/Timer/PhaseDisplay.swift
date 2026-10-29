import Foundation

/// 一次時鐘取樣得到的階段顯示值；子畫面直接使用它，不再各自讀時鐘。
/// 不保存取樣日期，也不驅動刷新；暫停時資料不變，畫面就不必因節拍而失效。
struct PhaseDisplay: Equatable, Sendable {
    let phase: Phase
    let status: TimerStatus
    let remaining: TimeInterval
    let isOvertime: Bool
    let overtime: TimeInterval
    let phaseDuration: TimeInterval
    let endDate: Date?
    let completedFocusesInCycle: Int
    let longBreakInterval: Int

    /// 超時中剩餘時間為零，進度維持滿圈。
    var phaseProgress: Double { 1 - remaining / phaseDuration }
}
