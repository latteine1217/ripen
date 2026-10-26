/// 階段循環：目前是哪一種階段，以及距離上次長休息已完成幾次專注。純值型別，不涉及時間。
struct PhaseCycle: Equatable, Sendable {
    private(set) var phase: Phase = .focus
    /// 長休息間隔的計數。
    private(set) var completedFocuses = 0

    /// 離開目前階段、進到下一段。`completed` 為假代表跳過：跳過的專注不計數。
    mutating func advance(completed: Bool, longBreakInterval: Int) {
        switch phase {
        case .focus:
            if completed { completedFocuses += 1 }
            phase = completedFocuses >= longBreakInterval ? .longBreak : .shortBreak
        case .shortBreak:
            phase = .focus
        case .longBreak:
            completedFocuses = 0
            phase = .focus
        }
    }

    /// 長休息間隔重新計數，目前階段不變。
    mutating func resetCount() {
        completedFocuses = 0
    }
}
