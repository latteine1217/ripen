extension AppModel {
    /// 單一按鍵的開始／暫停：依目前狀態開始、暫停或繼續。全域熱鍵（與之後的選單）共用。
    ///
    /// 先確立已倒數到 0 的完成，按下時才會從下一段的起點開始，與計時頁的主按鈕一致。
    func toggleStartPause() {
        refresh()
        switch status {
        case .idle: start()
        case .running: pause()
        case .paused: resume()
        // refresh() 之後不會停在已倒數到 0 的階段
        case .finished: assertionFailure("refresh() 後不應仍是 finished")
        }
    }
}
