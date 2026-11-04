import Foundation

/// 目前階段的執行狀態與它的轉移：純值型別，所有查詢與操作都傳入「現在」。
///
/// 復原是把操作前的值整份換回（引擎記的是結束時刻，換回後時間照牆上時鐘接著走，ADR-0002）；
/// 分類歸屬與使用者是否在場不在這裡，復原不還原它們。存檔、提醒與到點計時器由 `AppModel` 協調。
struct PhaseRun: Equatable, Sendable {
    /// 閒置滿這麼久，長休息間隔就重新計數（GLOSSARY）。
    static let idleResetInterval: TimeInterval = 2 * 60 * 60
    /// 完成摘要停留的時間；比復原期限短，收起後仍可復原。
    static let completionSummaryDuration: TimeInterval = 3

    private(set) var cycle = PhaseCycle()
    var engine: TimerEngine
    /// 目前階段倒數到 0 的提醒是否已送出（含待播）；換階段時歸零。
    private(set) var reachedZero = false
    /// 目前的暫停是離開時自動暫停的超時；使用者按繼續或換階段時清掉。
    private(set) var isPausedWhileAway = false
    /// 這段閒置開始的時刻；不在閒置時為 nil。沒有階段在跑就是閒置（暫停也算），
    /// 超時中則只有離開時被自動暫停才算，從自動暫停的那一刻起算。
    var idleSince: Date?
    /// 完成摘要；完成專注後 3 秒內存在。
    var completionSummary: CompletedFocus?
    /// 休息期間的成果卡入口；保留到緊接的休息結束或被跳過。
    var recapShortcut: CompletedFocus?

    /// 第一次專注的起點。
    init(configuration: CycleConfiguration, idleSince: Date?) {
        engine = TimerEngine(phase: .focus, duration: configuration.duration(for: .focus))
        self.idleSince = idleSince
    }

    init(recovery: TimerRecovery) {
        engine = TimerEngine(recovery: recovery)
        cycle = PhaseCycle(phase: recovery.phase, completedFocuses: recovery.completedFocuses)
        reachedZero = recovery.remaining <= 0
    }

    /// 換上循環目前所在的階段，處於起點、尚未開始。
    /// 回到專注就離開了緊接完成的那段休息（結束、跳過或閒置歸零），摘要與成果卡入口一併結束。
    mutating func loadCurrentPhase(_ configuration: CycleConfiguration) {
        engine = TimerEngine(phase: cycle.phase, duration: configuration.duration(for: cycle.phase))
        reachedZero = false
        isPausedWhileAway = false
        if cycle.phase == .focus {
            completionSummary = nil
            recapShortcut = nil
        }
    }

    /// 離開目前階段、到下一段的起點。`completed` 為假代表跳過，不計數。
    mutating func advance(completed: Bool, configuration: CycleConfiguration) {
        cycle.advance(completed: completed, longBreakInterval: configuration.longBreakInterval)
        loadCurrentPhase(configuration)
    }

    mutating func resume(at now: Date) {
        engine.resume(at: now)
        isPausedWhileAway = false
    }

    /// 離開期間的超時不算：在離開的那一刻暫停；離開時還在倒數則停在 0（ADR-0006）。
    ///
    /// 睡眠時 App 不執行，可能要到回來才走到這裡；暫停時刻取自記下的離開時刻與結束時刻，不受刷新時機影響。
    /// 自動暫停的超時算閒置，從暫停的那一刻起算：整晚睡著時倒數跨過 0，隔天回來計數也會歸零。
    mutating func pauseOvertimeIfAway(since awaySince: Date?, at now: Date) {
        guard let awaySince, let endDate = engine.endDate, endDate <= now else { return }
        let pausedAt = max(awaySince, endDate)
        engine.pause(at: pausedAt)
        isPausedWhileAway = true
        idleSince = pausedAt
    }

    /// 每段只在第一次跨過 0 時回傳真：繼續、重複刷新、到點計時器再觸發都不重播提醒。
    mutating func markReachedZero(at now: Date) -> Bool {
        guard !reachedZero, engine.isOvertime(at: now) else { return false }
        reachedZero = true
        return true
    }

    /// 停在休息起點等待的話，改從第 1 次專注開始；暫停中的階段（含自動暫停的超時）保留，由使用者決定。
    mutating func resetCountIfIdle(at now: Date, configuration: CycleConfiguration) {
        guard let idleSince, now.timeIntervalSince(idleSince) >= Self.idleResetInterval else { return }
        if engine.status(at: now) == .idle, cycle.phase != .focus {
            cycle = PhaseCycle()
            loadCurrentPhase(configuration)
        } else if cycle.completedFocuses != 0 {
            cycle.resetCount()
        }
    }

    /// 改階段長度從下一段生效；停在起點、還沒開始的階段不算在跑，直接換成新長度。
    mutating func applyChangedLength(at now: Date, configuration: CycleConfiguration) {
        guard engine.status(at: now) == .idle,
              engine.duration != configuration.duration(for: engine.phase)
        else { return }
        loadCurrentPhase(configuration)
    }

    mutating func expireCompletionSummary(at now: Date) {
        guard let completionSummary, now >= completionSummary.completedAt + Self.completionSummaryDuration else { return }
        self.completionSummary = nil
    }

    /// 開始跑或在超時中就不是閒置，離開時自動暫停的超時除外；停下來的那一刻開始閒置。已在閒置中的操作不重新計時。
    mutating func updateIdle(at now: Date) {
        if engine.status(at: now) == .running || (engine.isOvertime(at: now) && !isPausedWhileAway) {
            idleSince = nil
        } else if idleSince == nil {
            idleSince = now
        }
    }
}
