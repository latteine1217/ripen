import Foundation

/// 剛按「完成」確立的專注，供完成摘要與休息期間的成果卡入口使用（#24）。
///
/// 數字在完成的那一刻取定：摘要只是回饋，不隨之後的紀錄變動；復原時整份撤回。
struct CompletedFocus: Equatable, Sendable {
    /// nil 是未分類。
    let projectID: UUID?
    /// 這一次的實際長度。
    let focus: FocusTotal
    /// 含這一次在內的分類累積。
    let projectTotal: FocusTotal
    let completedAt: Date
}
