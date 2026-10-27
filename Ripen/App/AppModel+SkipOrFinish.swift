extension AppModel {
    /// 「跳過」按鈕的動作：已在超時中就改為「完成」（ADR-0006）。
    ///
    /// 按鈕畫面可能落後於時間（選單開著時跨過 0、或剛好在 0 附近點下），
    /// 點下的那一刻已超時的話，使用者要的是結束這一段，不該什麼都不做。
    func skipOrFinish() {
        refresh()
        if isOvertime { finish() } else { skip() }
    }
}
