import Foundation

/// 計時引擎：純值型別，不依賴 UI 與時鐘實作；所有查詢與操作都傳入「現在」。
///
/// 執行中只記住結束時刻，剩餘時間永遠是「結束時刻 − 現在」（ADR-0002）。
/// 倒數到 0 後不會自己結束：剩餘時間變成負值，就是超時（ADR-0006）；何時結束由 `AppModel` 決定。
struct TimerEngine: Equatable, Sendable {
    private enum Run: Equatable, Sendable {
        case idle
        case running(endDate: Date)
        /// 超時中暫停時 `remaining` ≤ 0。
        case paused(remaining: TimeInterval)
    }

    let phase: Phase
    let duration: TimeInterval
    private var run: Run = .idle
    /// 這一段第一次開始的時刻（不因暫停改變）；統計依它歸屬日期。
    private(set) var startedAt: Date?

    init(phase: Phase, duration: TimeInterval) {
        // 長度為 0 會讓進度計算除以 0，屬於設定錯誤，直接中止
        precondition(duration > 0, "階段長度必須大於 0")
        self.phase = phase
        self.duration = duration
    }

    func status(at now: Date) -> TimerStatus {
        switch run {
        case .idle: .idle
        case .running: .running
        case .paused: .paused
        }
    }

    /// 倒數的剩餘時間，超時中為 0。
    func remaining(at now: Date) -> TimeInterval {
        max(0, signedRemaining(at: now))
    }

    /// 倒數到 0 之後（含暫停中）。
    func isOvertime(at now: Date) -> Bool {
        run != .idle && signedRemaining(at: now) <= 0
    }

    /// 倒數到 0 之後經過的時間，不含暫停；未超時為 0。
    func overtime(at now: Date) -> TimeInterval {
        max(0, -signedRemaining(at: now))
    }

    /// 實際跑了多久：設定長度加超時，扣掉暫停（GLOSSARY：完成的專注）。
    func elapsed(at now: Date) -> TimeInterval {
        duration - signedRemaining(at: now)
    }

    /// 執行中（含超時）的結束時刻；閒置或暫停時沒有結束時刻。
    var endDate: Date? {
        guard case .running(let endDate) = run else { return nil }
        return endDate
    }

    private func signedRemaining(at now: Date) -> TimeInterval {
        switch run {
        case .idle: duration
        case .running(let endDate): endDate.timeIntervalSince(now)
        case .paused(let remaining): remaining
        }
    }

    // 不符合目前狀態的操作一律忽略：意圖可能同時來自按鈕、熱鍵與選單。

    /// 閒置時開始一段完整的階段。
    mutating func start(at now: Date) {
        guard status(at: now) == .idle else { return }
        run = .running(endDate: now + duration)
        startedAt = now
    }

    /// 暫停時改存剩餘時間（超時中為負值），暫停期間不再與時鐘相關。
    ///
    /// `now` 可以是過去的時刻：離開電腦時以離開的那一刻暫停。
    mutating func pause(at now: Date) {
        guard status(at: now) == .running else { return }
        run = .paused(remaining: signedRemaining(at: now))
    }

    /// 繼續時以剩餘時間重算新的結束時刻；超時中繼續時結束時刻在過去。
    mutating func resume(at now: Date) {
        guard case .paused(let remaining) = run else { return }
        run = .running(endDate: now + remaining)
    }
}

/// 目前階段的執行狀態；是否超時另由 `isOvertime(at:)` 推導。
enum TimerStatus: Equatable, Sendable {
    case idle
    case running
    case paused
}
