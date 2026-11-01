import Foundation

/// 可跨啟動還原的暫停階段；剩餘時間可為負，代表超時，不保存可繼續累加的結束時刻。
struct TimerRecovery: Codable, Equatable, Sendable {
    let phase: Phase
    let duration: TimeInterval
    let remaining: TimeInterval
    let startedAt: Date
    let projectID: UUID?
    let completedFocuses: Int

    var isValid: Bool {
        duration.isFinite && duration > 0 && duration < Double(Int.max)
            && remaining.isFinite && remaining > -Double(Int.max) && remaining <= duration
            && (duration - remaining).isFinite && startedAt.timeIntervalSinceReferenceDate.isFinite
            && completedFocuses >= 0 && completedFocuses < Int.max
    }
}

protocol TimerRecoveryStorage {
    func loadRecovery() throws -> TimerRecovery?
    func saveRecovery(_ recovery: TimerRecovery?) throws
}
