import CryptoKit
import Foundation

/// App 內更新信任的發行公鑰（Ed25519，ADR-0017）。私鑰只在作者的鑰匙圈，見 `scripts/update-signing.swift`。
enum UpdateSigningKey {
    /// 更換金鑰會讓已安裝的版本無法驗證之後的更新，見 ADR-0017。
    static let publicKeyBase64 = "nBGKevGGJ/sgQbM8T1pULFH6Ai/pNLRDH0nUI3miwys="

    static var trusted: Curve25519.Signing.PublicKey? {
        Data(base64Encoded: publicKeyBase64).flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
    }
}
