import Foundation

/// GitHub「最新版本」API 的回應中更新需要的部分。
struct GitHubRelease: Decodable, Equatable, Sendable {
    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let browserDownloadURL: URL
        let size: Int
        /// GitHub 為上傳的檔案算出的雜湊，形如 `sha256:<hex>`；較舊的檔案沒有。
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case draft, prerelease, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    static let latestURL = URL(string: "https://api.github.com/repos/latteine1217/ripen/releases/latest")!
    /// 無法自動安裝時讓使用者自己下載的頁面。
    static let releasesPage = URL(string: "https://github.com/latteine1217/ripen/releases")!

    var version: AppVersion? { AppVersion(tagName) }

    /// `scripts/make-dmg.sh` 產生的 `Ripen-<version>.dmg`。
    var diskImage: Asset? {
        guard let version else { return nil }
        return assets.first { $0.name == "Ripen-\(version).dmg" }
    }
}

extension GitHubRelease.Asset {
    /// `digest` 中的 SHA-256（小寫十六進位）；不是 SHA-256 或格式不對時為 nil。
    var sha256: String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let hex = digest.dropFirst("sha256:".count).lowercased()
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        return hex
    }
}
