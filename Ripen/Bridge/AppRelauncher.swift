import AppKit
import Observation

/// 結束 App 後重新開啟（換介面語言用，#74）。
///
/// 經一般的結束流程：計時中會保存恢復點、未儲存的資料照常詢問（ADR-0014）。使用者在詢問中選擇
/// 保持開啟時 `terminate` 會返回，這時不再重開；確定結束才在 `applicationWillTerminate` 排定重開，
/// 避免之後一般的結束被當成重開。
@MainActor
@Observable
final class AppRelauncher {
    @ObservationIgnored private var isRelaunching = false

    func relaunch() {
        isRelaunching = true
        NSApp.terminate(nil)
        // 只有結束被取消時才會執行到這裡
        isRelaunching = false
    }

    /// 由 `AppLifecycleDelegate.applicationWillTerminate` 呼叫。
    func appWillTerminate() {
        guard isRelaunching else { return }
        // 交給背景的 shell：等本程序結束再開，否則 open 只會把還沒結束的這個程序帶到前面
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", #"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; /usr/bin/open "$2""#, "relaunch",
            String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path,
        ]
        try? process.run()
    }
}
