#!/usr/bin/env swift
import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("usage: sign_update_manifest.swift <manifest-path>\n", stderr)
    exit(2)
}

let manifestURL = URL(fileURLWithPath: arguments[1])
let privateKeyBase64 = ProcessInfo.processInfo.environment["MIHOMO_UPDATE_PRIVATE_KEY"]
    ?? readText(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".mihomo-update-signing/ed25519.private"))

guard let privateKeyData = Data(base64Encoded: privateKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)) else {
    fputs("invalid Ed25519 private key Base64\n", stderr)
    exit(2)
}

do {
    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
    let publicKey = privateKey.publicKey.rawRepresentation.base64EncodedString()
    let data = try Data(contentsOf: manifestURL)
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SignError.message("manifest must be a JSON object")
    }

    object.removeValue(forKey: "signature")
    let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    let signature = try privateKey.signature(for: canonical).base64EncodedString()
    object["signature"] = [
        "algorithm": "Ed25519",
        "publicKey": publicKey,
        "value": signature
    ]

    let signed = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try signed.write(to: manifestURL, options: .atomic)
    print(publicKey)
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}

private func readText(_ url: URL) -> String {
    (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

private enum SignError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message): return message
        }
    }
}
