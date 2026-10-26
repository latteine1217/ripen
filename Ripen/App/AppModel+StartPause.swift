extension AppModel {
    /// 單一按鍵的開始／暫停：依目前狀態開始、暫停或繼續。全域熱鍵（與之後的選單）共用。
    ///
    /// 超時中同樣是暫停／繼續；結束這一段要按「完成」（ADR-0006）。
    func toggleStartPause() {
        refresh()
        switch status {
        case .idle: start()
        case .running: pause()
        case .paused: resume()
        }
    }
}
