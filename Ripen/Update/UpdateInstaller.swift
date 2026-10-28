import AppKit
import CryptoKit
import Foundation
import os

/// 下載、驗證並安裝新版的 dmg。
///
/// Ripen 只有 ad-hoc 簽章，無法以開發者身分驗證新版；改以 GitHub 為檔案算出的 SHA-256 核對下載內容，
/// 再確認 dmg 裡的 App 是同一個 bundle id、版本與 Release 相符、簽章完整。任何一項不符就停止，不安裝。
enum UpdateInstaller {
    private static let logger = Logger(subsystem: "com.latteine.ripen", category: "update")

    enum Failure: Error, Equatable {
        case missingDigest
        case digestMismatch
        case mountFailed
        case unexpectedApp
        case cannotReplace
        case commandFailed(String)
    }

    /// 核對下載的檔案；`expected` 為小寫十六進位。
    static func verify(_ file: URL, sha256 expected: String) throws {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw Failure.digestMismatch }
    }

    /// 掛載 dmg、取出並檢查其中的 Ripen.app，複製到 `workDirectory` 後卸載；回傳複製出的 App。
    static func extractApp(from diskImage: URL, expecting version: AppVersion, in workDirectory: URL) throws -> URL {
        let mountPoint = workDirectory.appending(path: "mount")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        do {
            try run("/usr/bin/hdiutil", ["attach", diskImage.path, "-nobrowse", "-readonly", "-mountpoint", mountPoint.path])
        } catch {
            throw Failure.mountFailed
        }
        defer { try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }

        let mounted = mountPoint.appending(path: "Ripen.app")
        guard let bundle = Bundle(url: mounted),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              AppVersion(shortVersion) == version
        else { throw Failure.unexpectedApp }

        let staged = workDirectory.appending(path: "Ripen.app")
        try run("/usr/bin/ditto", [mounted.path, staged.path])
        // ad-hoc 簽章無法證明來源，但能確認複製出的內容在簽章後沒有被改動
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
        return staged
    }

    /// 目前執行中的 App 能否被原地取代：從 dmg 或被系統搬移（App Translocation）的位置執行時不行。
    static var installedAppURL: URL? {
        let url = Bundle.main.bundleURL
        let path = url.path
        guard !path.hasPrefix("/Volumes/"), !path.contains("/AppTranslocation/"),
              FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path),
              FileManager.default.isWritableFile(atPath: path)
        else { return nil }
        return url
    }

    /// 交給背景的 shell：等本 App 結束後換上新版並重新開啟。換新失敗時放回舊版。
    ///
    /// 路徑以參數傳入，不內插進指令稿。下載內容已核對雜湊，才移除可能存在的隔離屬性，
    /// 否則 ad-hoc 簽章的新版會被 Gatekeeper 擋下、使用者卡在無法開啟的 App。
    static func scheduleReplacement(of target: URL, with staged: URL, in workDirectory: URL) throws {
        let script = workDirectory.appending(path: "install.sh")
        try """
        #!/bin/sh
        pid="$1"; target="$2"; staged="$3"; backup="$4"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        /usr/bin/xattr -dr com.apple.quarantine "$staged" 2>/dev/null
        if /bin/mv "$target" "$backup"; then
          if /usr/bin/ditto "$staged" "$target"; then
            /bin/rm -rf "$backup"
          else
            /bin/rm -rf "$target"
            /bin/mv "$backup" "$target"
          fi
        fi
        /usr/bin/open "$target"
        """.write(to: script, atomically: true, encoding: .utf8)

        let backup = target.deletingLastPathComponent().appending(path: ".Ripen-previous.app")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier),
                             target.path, staged.path, backup.path]
        try process.run()
        logger.info("已排定更新：\(target.path, privacy: .public)")
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            logger.error("\(executable, privacy: .public) 失敗：\(message, privacy: .public)")
            throw Failure.commandFailed(executable)
        }
    }
}
