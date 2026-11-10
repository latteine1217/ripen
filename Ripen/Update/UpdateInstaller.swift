import AppKit
import CryptoKit
import Foundation
import os

/// 下載、驗證並安裝新版的 dmg。
///
/// Ripen 只有 ad-hoc 簽章，無法靠系統驗證開發者身分；改以 App 內建的公鑰驗證作者對 dmg 的簽章（ADR-0017），
/// 再確認 dmg 裡的 App 是同一個 bundle id、版本與 Release 相符、程式碼簽章完整。任何一項不符就停止，不安裝。
enum UpdateInstaller {
    private static let logger = Logger(subsystem: "com.latteine.ripen", category: "update")

    enum Failure: Error, Equatable {
        case signatureMismatch
        case mountFailed
        case unexpectedApp
        case cannotReplace
        case commandFailed(String)
    }

    /// 確認 `file` 正是持有私鑰的作者簽過的內容。
    static func verify(_ file: URL, signature: Data, publicKey: Curve25519.Signing.PublicKey) throws {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        guard publicKey.isValidSignature(signature, for: data) else { throw Failure.signatureMismatch }
    }

    /// 簽章檔的內容是 base64 文字（`scripts/update-signing.swift` 產生）；不是 64 位元組的 Ed25519 簽章時為 nil。
    static func signature(fromFile contents: Data) -> Data? {
        let text = String(decoding: contents, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let signature = Data(base64Encoded: text), signature.count == 64 else { return nil }
        return signature
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
    /// 路徑以參數傳入，不內插進指令稿。下載內容已通過作者簽章驗證，才移除可能存在的隔離屬性，
    /// 否則 ad-hoc 簽章的新版會被 Gatekeeper 擋下、使用者卡在無法開啟的 App。
    static func scheduleReplacement(of target: URL, with staged: URL, in workDirectory: URL) throws {
        let script = workDirectory.appending(path: "install.sh")
        try """
        #!/bin/sh
        pid="$1"; target="$2"; staged="$3"; workDirectory="$4"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        /usr/bin/xattr -dr com.apple.quarantine "$staged" 2>/dev/null
        \(replacementCommands)
        /usr/bin/open "$target"
        """.write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier),
                             target.path, staged.path, workDirectory.path]
        try process.run()
        logger.info("已排定更新：\(target.path, privacy: .public)")
    }

    /// 在 App 同目錄預留獨立備份資料夾，避免 mv 將 App 放進殘留備份，也避免跨檔案系統更名。
    /// 舊版仍完好時（無法預留備份或無法移開舊版）照常往下重新開啟；只有還原失敗才以非 0 結束、不開啟。
    /// 有指定 `workDirectory`（下載的 dmg、取出的新版與本指令稿）時，換新結束後一併清除；還原失敗時保留。
    /// 正式更新與隔離檔案測試共用此指令，測試不會結束或重新開啟 App。
    static let replacementCommands = """
    if backupDirectory=$(/usr/bin/mktemp -d "${target%/*}/.Ripen-update.XXXXXX"); then
      backup="$backupDirectory/Ripen.app"
      if /bin/mv "$target" "$backup"; then
        if /usr/bin/ditto "$staged" "$target"; then
          /bin/rm -rf "$backupDirectory"
        else
          /bin/rm -rf "$target" || exit 1
          /bin/mv "$backup" "$target" || exit 1
          /bin/rmdir "$backupDirectory"
        fi
      else
        /bin/rmdir "$backupDirectory"
      fi
    fi
    if [ -n "$workDirectory" ]; then /bin/rm -rf "$workDirectory"; fi
    """

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
