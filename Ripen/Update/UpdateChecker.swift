import AppKit
import Foundation
import Observation
import os

/// 取得最新版本與下載檔案；測試以假的來源取代網路。
protocol ReleaseSource: Sendable {
    /// 最新的正式版；還沒有發佈任何版本時為 nil。
    func latest() async throws -> GitHubRelease?
    /// 下載到暫存位置，回傳檔案。
    func download(_ asset: GitHubRelease.Asset) async throws -> URL
}

/// 手動檢查更新：只在使用者按下「檢查更新」時連網，從不自動檢查（README「本機與隱私」）。
///
/// 有新版時由使用者決定是否下載安裝；下載後核對雜湊、換上新版並重新開啟（`UpdateInstaller`）。
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
        /// Release 裡沒有預期的 dmg 或沒有雜湊，無法安全地自動安裝。
        case cannotVerify
        /// 下載內容與雜湊或 App 資訊不符，已停止安裝。
        case verificationFailed
        case installFailed
    }

    private static let logger = Logger(subsystem: "com.latteine.ripen", category: "update")

    private(set) var state = State.idle
    let currentVersion: AppVersion?
    @ObservationIgnored private let source: any ReleaseSource
    /// 換上新版的實際動作；測試以假的取代，不碰檔案系統與 App 生命週期。
    @ObservationIgnored private let install: @MainActor (GitHubRelease, URL) async throws -> State

    init(
        source: any ReleaseSource = GitHubReleaseSource(),
        currentVersion: AppVersion? = .current,
        install: @escaping @MainActor (GitHubRelease, URL) async throws -> State = UpdateChecker.installDownloadedImage
    ) {
        self.source = source
        self.currentVersion = currentVersion
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
        guard let asset = release.diskImage, let digest = asset.sha256 else {
            state = .failed(.cannotVerify)
            return
        }
        state = .downloading
        let file: URL
        do {
            file = try await source.download(asset)
        } catch {
            Self.logger.error("下載更新失敗：\(error)")
            state = .failed(.network)
            return
        }
        do {
            try await Task.detached { try UpdateInstaller.verify(file, sha256: digest) }.value
            state = try await install(release, file)
        } catch UpdateInstaller.Failure.digestMismatch, UpdateInstaller.Failure.unexpectedApp {
            state = .failed(.verificationFailed)
        } catch {
            Self.logger.error("安裝更新失敗：\(error)")
            state = .failed(.installFailed)
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
        // 經過一般的結束流程：超時中的專注照常記錄，未保存紀錄照常詢問（ADR-0006、ADR-0007）
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

    func download(_ asset: GitHubRelease.Asset) async throws -> URL {
        let (temporary, response) = try await URLSession.shared.download(from: asset.browserDownloadURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        // 系統會清掉回傳的暫存檔，先搬到自己的工作資料夾
        let directory = FileManager.default.temporaryDirectory.appending(path: "RipenUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: asset.name)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}
