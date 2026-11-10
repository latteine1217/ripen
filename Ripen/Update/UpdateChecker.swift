import AppKit
import CryptoKit
import Foundation
import Observation
import os

/// 取得最新版本與下載檔案；測試以假的來源取代網路。
protocol ReleaseSource: Sendable {
    /// 最新的正式版；還沒有發佈任何版本時為 nil。
    func latest() async throws -> GitHubRelease?
    /// 下載到 `directory`（呼叫端建立並負責清除的工作資料夾），回傳檔案。
    func download(_ asset: GitHubRelease.Asset, into directory: URL) async throws -> URL
}

/// 手動檢查更新：只在使用者按下「檢查更新」時連網，從不自動檢查（README「本機與隱私」）。
///
/// 有新版時由使用者決定是否下載安裝；下載後驗證作者簽章、換上新版並重新開啟（`UpdateInstaller`）。
@MainActor
@Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(GitHubRelease)
        case downloading
        /// 已排定安裝，等 App 結束後換上新版；退出被取消時停在這裡，下次結束時才更新。
        case restarting
        /// 無法自動安裝（例如 App 不在可寫入的位置），已在 Finder 打開 dmg 讓使用者自己拖。
        case openedDiskImage
        case failed(Failure)
    }

    enum Failure: Equatable {
        case network
        /// Release 裡沒有預期的 dmg 或簽章檔，或 App 沒有可信任的公鑰，無法安全地自動安裝。
        case cannotVerify
        /// 下載內容與作者簽章或 App 資訊不符，已停止安裝。
        case verificationFailed
        case installFailed
        /// 暫存所在的磁碟放不下這次更新；`required` 是大約需要的可用空間（位元組）。
        case notEnoughSpace(required: Int64)
    }

    /// dmg 之外還要放取出的新版：0.3.1 的 dmg 約 5 MB、App 約 13 MB，取 dmg 的 4 倍留餘裕。
    static let spaceFactor: Int64 = 4

    private static let logger = Logger(subsystem: "com.latteine.ripen", category: "update")

    private(set) var state = State.idle
    let currentVersion: AppVersion?
    @ObservationIgnored private let source: any ReleaseSource
    @ObservationIgnored private let publicKey: Curve25519.Signing.PublicKey?
    /// 某個位置所在磁碟的可用空間；量不到時為 nil，照常下載。
    @ObservationIgnored private let availableSpace: @Sendable (URL) -> Int64?
    /// 換上新版的實際動作；測試以假的取代，不碰檔案系統與 App 生命週期。
    @ObservationIgnored private let install: @MainActor (GitHubRelease, URL) async throws -> State

    init(
        source: any ReleaseSource = GitHubReleaseSource(),
        currentVersion: AppVersion? = .current,
        publicKey: Curve25519.Signing.PublicKey? = UpdateSigningKey.trusted,
        availableSpace: @escaping @Sendable (URL) -> Int64? = { UpdateChecker.availableSpace(at: $0) },
        install: @escaping @MainActor (GitHubRelease, URL) async throws -> State = UpdateChecker.installDownloadedImage
    ) {
        self.source = source
        self.currentVersion = currentVersion
        self.publicKey = publicKey
        self.availableSpace = availableSpace
        self.install = install
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .restarting: true
        default: false
        }
    }

    func check() async {
        guard !isBusy else { return }
        state = .checking
        do {
            guard let release = try await source.latest(), let latest = release.version,
                  let currentVersion, currentVersion < latest
            else {
                state = .upToDate
                return
            }
            state = .available(release)
        } catch {
            Self.logger.error("檢查更新失敗：\(error)")
            state = .failed(.network)
        }
    }

    func downloadAndInstall() async {
        guard case .available(let release) = state else { return }
        // 缺簽章一律不裝，不退回其他檢查：否則刪掉簽章檔就能繞過驗證
        guard let asset = release.diskImage, let signatureAsset = release.diskImageSignature, let publicKey else {
            state = .failed(.cannotVerify)
            return
        }
        // 下載前先檢查：空間不足時下載會被誤報成網路錯誤（#64）。替換時的複製失敗另由安裝指令稿放回舊版。
        let temporary = FileManager.default.temporaryDirectory
        let required = Int64(asset.size) * Self.spaceFactor
        if let available = availableSpace(temporary), available < required {
            state = .failed(.notEnoughSpace(required: required))
            return
        }
        state = .downloading
        // dmg 與簽章放同一個工作資料夾；排定換新後由安裝指令稿在換完後清除，其他結果在這裡清除
        let workDirectory = temporary.appending(path: "RipenUpdate-\(UUID().uuidString)")
        let file: URL
        let signatureFile: URL
        do {
            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            file = try await source.download(asset, into: workDirectory)
            signatureFile = try await source.download(signatureAsset, into: workDirectory)
        } catch {
            Self.logger.error("下載更新失敗：\(error)")
            state = .failed(.network)
            Self.remove(workDirectory)
            return
        }
        do {
            try await Task.detached {
                guard let signature = UpdateInstaller.signature(fromFile: try Data(contentsOf: signatureFile)) else {
                    throw UpdateInstaller.Failure.signatureMismatch
                }
                try UpdateInstaller.verify(file, signature: signature, publicKey: publicKey)
            }.value
            state = try await install(release, file)
        } catch UpdateInstaller.Failure.signatureMismatch, UpdateInstaller.Failure.unexpectedApp {
            state = .failed(.verificationFailed)
        } catch {
            Self.logger.error("安裝更新失敗：\(error)")
            state = .failed(.installFailed)
        }
        switch state {
        // 指令稿等 App 結束才換新，還要用到工作資料夾；結束被取消時要留到下次結束
        case .restarting: break
        // dmg 已在 Finder 打開，使用者還要從裡面拖出 App；交給系統清理暫存
        case .openedDiskImage: Self.remove(signatureFile)
        default: Self.remove(workDirectory)
        }
    }

    /// 以「重要用途」的可用空間計算，包含系統可清出的可清除空間，與 Finder 顯示的一致。
    nonisolated static func availableSpace(at url: URL) -> Int64? {
        try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }

    private static func remove(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error("清除更新暫存失敗：\(error)")
        }
    }

    /// 實際安裝：App 能原地取代就排定換新並結束；不能就打開 dmg 讓使用者自己拖到「應用程式」。
    static func installDownloadedImage(_ release: GitHubRelease, _ diskImage: URL) async throws -> State {
        guard let version = release.version else { throw UpdateInstaller.Failure.unexpectedApp }
        guard let target = UpdateInstaller.installedAppURL else {
            NSWorkspace.shared.open(diskImage)
            return .openedDiskImage
        }
        let workDirectory = diskImage.deletingLastPathComponent()
        let staged = try await Task.detached {
            try UpdateInstaller.extractApp(from: diskImage, expecting: version, in: workDirectory)
        }.value
        try UpdateInstaller.scheduleReplacement(of: target, with: staged, in: workDirectory)
        // 經過一般退出流程：保存目前階段的暫停進度，未保存資料照常詢問（ADR-0014）
        NSApp.terminate(nil)
        return .restarting
    }
}

/// 從 GitHub 取得最新版本；只在使用者手動檢查時呼叫。
struct GitHubReleaseSource: ReleaseSource {
    func latest() async throws -> GitHubRelease? {
        var request = URLRequest(url: GitHubRelease.latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 還沒有任何正式版時 GitHub 回 404
        if status == 404 { return nil }
        guard status == 200 else { throw URLError(.badServerResponse) }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        return release.draft || release.prerelease ? nil : release
    }

    func download(_ asset: GitHubRelease.Asset, into directory: URL) async throws -> URL {
        let (temporary, response) = try await URLSession.shared.download(from: asset.browserDownloadURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        // 系統會清掉回傳的暫存檔，先搬到工作資料夾
        let destination = directory.appending(path: asset.name)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}
