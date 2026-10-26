/// 計時的最小單位（見 GLOSSARY）。短休息、長休息由後續 ticket 加入。
enum Phase: Equatable, Sendable {
    case focus
}
