import Foundation

/// 計時引擎：純值型別，不依賴 UI 與時鐘實作；所有查詢與操作都傳入「現在」。
///
/// 執行中只記住結束時刻，剩餘時間永遠是「結束時刻 − 現在」（ADR-0002）。
struct TimerEngine: Equatable, Sendable {
    static let defaultFocusDuration: TimeInterval = 25 * 60

    private enum Run: Equatable, Sendable {
        case idle
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
    }

    let phase: Phase
    let duration: TimeInterval
    private var run: Run = .idle

    init(phase: Phase = .focus, duration: TimeInterval = TimerEngine.defaultFocusDuration) {
        // 長度為 0 會讓進度計算除以 0，屬於設定錯誤，直接中止
        precondition(duration > 0, "階段長度必須大於 0")
        self.phase = phase
        self.duration = duration
    }

    func status(at now: Date) -> TimerStatus {
        switch run {
        case .idle: .idle
        case .running(let endDate): now < endDate ? .running : .finished
        case .paused: .paused
        }
    }

    func remaining(at now: Date) -> TimeInterval {
        switch run {
        case .idle: duration
        case .running(let endDate): max(0, endDate.timeIntervalSince(now))
        case .paused(let remaining): remaining
        }
    }

    /// 執行中（含已倒數到 0）的結束時刻；閒置或暫停時沒有結束時刻。
    var endDate: Date? {
        guard case .running(let endDate) = run else { return nil }
        return endDate
    }

    // 不符合目前狀態的操作一律忽略：意圖可能同時來自按鈕、熱鍵與選單。

    /// 閒置或已倒數到 0 時，開始一段完整的階段。
    mutating func start(at now: Date) {
        let current = status(at: now)
        guard current == .idle || current == .finished else { return }
        run = .running(endDate: now + duration)
    }

    /// 暫停時改存剩餘時間，暫停期間不再與時鐘相關。
    mutating func pause(at now: Date) {
        guard status(at: now) == .running else { return }
        run = .paused(remaining: remaining(at: now))
    }

    /// 繼續時以剩餘時間重算新的結束時刻。
    mutating func resume(at now: Date) {
        guard case .paused(let remaining) = run else { return }
        run = .running(endDate: now + remaining)
    }
}

/// 目前階段的執行狀態。
enum TimerStatus: Equatable, Sendable {
    case idle
    case running
    case paused
    /// 倒數到 0。由時間推導而來，不需要任何計時器觸發。
    case finished
}
