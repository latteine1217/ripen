import Foundation

/// 「現在」的來源。計時只透過它讀取時間，測試可注入假時鐘（ADR-0002、ADR-0020）。
///
/// `now()` 不受系統時間調動影響；面向使用者與資料的時刻要加上 `systemClockOffset` 換算成目前的系統時間。
protocol TimeSource {
    func now() -> Date
    /// 目前的系統時間減 `now()`；系統時間被調動後不為 0。
    var systemClockOffset: TimeInterval { get }
}

extension TimeSource {
    var systemClockOffset: TimeInterval { 0 }

    /// 把 `now()` 同一套時間裡的時刻換算成目前的系統時間。
    func systemDate(for date: Date) -> Date { date + systemClockOffset }
    /// 把系統時間的時刻（例如存下的開始時刻）換算回 `now()` 同一套時間。
    func steadyDate(for systemDate: Date) -> Date { systemDate - systemClockOffset }
}

/// 正式環境用的時鐘：建立時的系統時間加上之後經過的單調時間。
///
/// 單調時間取自 `ContinuousClock`：不受手動改時間影響、睡眠期間照常前進（ADR-0020 的實測）。
struct SystemTimeSource: TimeSource {
    private let origin: Date
    private let systemClock: @Sendable () -> Date
    private let elapsed: @Sendable () -> TimeInterval

    init() {
        let start = ContinuousClock.now
        self.init(systemClock: { Date() }, elapsed: {
            let duration = ContinuousClock.now - start
            return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        })
    }

    /// 測試用：注入系統時間與經過的時間。
    init(systemClock: @escaping @Sendable () -> Date, elapsed: @escaping @Sendable () -> TimeInterval) {
        self.systemClock = systemClock
        self.elapsed = elapsed
        origin = systemClock() - elapsed()
    }

    func now() -> Date { origin + elapsed() }

    var systemClockOffset: TimeInterval { systemClock().timeIntervalSince(now()) }
}
