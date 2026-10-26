import Foundation

/// 「現在」的來源。計時只透過它讀取時間，測試可注入假時鐘（ADR-0002）。
protocol TimeSource {
    func now() -> Date
}

/// 正式環境用的系統時鐘。
struct SystemTimeSource: TimeSource {
    func now() -> Date { Date() }
}
