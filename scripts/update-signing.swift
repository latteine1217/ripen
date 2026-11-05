#!/usr/bin/env swift
// 發行簽章工具（ADR-0017）：私鑰存在登入鑰匙圈，不進 repo 與 CI。
//
//   swift scripts/update-signing.swift generate        產生金鑰，印出要填進 UpdateSigningKey.swift 的公鑰
//   swift scripts/update-signing.swift export          印出私鑰，只用來備份到密碼管理器
//   swift scripts/update-signing.swift import          從備份放回私鑰：輸入不顯示，須符合 App 內建的公鑰
//   swift scripts/update-signing.swift sign <dmg>      簽章並寫出 <dmg>.sig，上傳前執行
//
// RIPEN_SIGNING_SERVICE 可改用另一個鑰匙圈項目，只用於測試這個工具本身。
import CryptoKit
import Foundation
import Security

let service = ProcessInfo.processInfo.environment["RIPEN_SIGNING_SERVICE"] ?? "com.latteine.ripen.update-signing"
let account = "ed25519-private-key"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func baseQuery() -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: account]
}

func loadKey() -> Curve25519.Signing.PrivateKey? {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let encoded = item as? Data, let raw = Data(base64Encoded: encoded),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else { fail("cannot read the signing key from the keychain (status \(status))") }
    return key
}

/// App 實際內建的公鑰；簽章前核對，避免發行無法驗證自己下一版的 App。
func embeddedPublicKey() -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let source = root.appending(path: "Ripen/Update/UpdateSigningKey.swift")
    guard let text = try? String(contentsOf: source, encoding: .utf8),
          let range = text.range(of: #"publicKeyBase64 = "[^"]*""#, options: .regularExpression)
    else { fail("cannot read \(source.path)") }
    return text[range].split(separator: "\"", omittingEmptySubsequences: false)[1].description
}

func store(_ key: Curve25519.Signing.PrivateKey) {
    var attributes = baseQuery()
    attributes[kSecValueData as String] = Data(key.rawRepresentation.base64EncodedString().utf8)
    attributes[kSecAttrLabel as String] = "Ripen update signing key"
    let status = SecItemAdd(attributes as CFDictionary, nil)
    guard status == errSecSuccess else { fail("cannot store the key in the keychain (status \(status))") }
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "generate":
    guard loadKey() == nil else { fail("a signing key already exists; replacing it would strand installed versions") }
    let key = Curve25519.Signing.PrivateKey()
    store(key)
    print("Public key (safe to share):")
    print(key.publicKey.rawRepresentation.base64EncodedString())
    print("Next: back up the private key with `export`.")

case "export":
    guard let key = loadKey() else { fail("no signing key; run generate first") }
    print(key.rawRepresentation.base64EncodedString())

case "import":
    guard loadKey() == nil else { fail("a signing key already exists; replacing it would strand installed versions") }
    // 不接受命令列參數：私鑰不能留在 shell 歷史或行程列表
    var buffer = [CChar](repeating: 0, count: 256)
    defer { memset_s(&buffer, buffer.count, 0, buffer.count) }
    guard let entered = readpassphrase("Private key (input hidden): ", &buffer, buffer.count, 0) else {
        fail("cannot read the private key")
    }
    let text = String(cString: entered).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let raw = Data(base64Encoded: text), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("this is not a private key from `export`")
    }
    guard embeddedPublicKey() == key.publicKey.rawRepresentation.base64EncodedString() else {
        fail("this key does not match the public key in UpdateSigningKey.swift; nothing was stored")
    }
    store(key)
    print("Imported the signing key. It matches the public key built into the app.")

case "sign":
    guard arguments.count == 2 else { fail("usage: sign <dmg>") }
    guard let key = loadKey() else { fail("no signing key; run generate first") }
    let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
    guard embeddedPublicKey() == publicKey else {
        fail("UpdateSigningKey.swift does not contain this key's public key; rebuild the app with it before signing")
    }
    let file = URL(fileURLWithPath: arguments[1])
    guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { fail("cannot read \(file.path)") }
    guard let signature = try? key.signature(for: data), key.publicKey.isValidSignature(signature, for: data) else {
        fail("signing failed")
    }
    let output = file.appendingPathExtension("sig")
    do {
        try Data((signature.base64EncodedString() + "\n").utf8).write(to: output, options: .atomic)
    } catch {
        fail("cannot write \(output.path): \(error)")
    }
    print("Signed \(file.lastPathComponent) -> \(output.lastPathComponent)")

default:
    fail("usage: update-signing.swift generate | export | import | sign <dmg>")
}
