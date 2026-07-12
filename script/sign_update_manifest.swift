#!/usr/bin/env swift
import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("usage: sign_update_manifest.swift <manifest-path>\n       sign_update_manifest.swift --verify <manifest-path> [expected-public-key]\n", stderr)
    exit(2)
}

if arguments[1] == "--verify" {
    guard arguments.count >= 3 else {
        fputs("usage: sign_update_manifest.swift --verify <manifest-path> [expected-public-key]\n", stderr)
        exit(2)
    }
    let manifestURL = URL(fileURLWithPath: arguments[2])
    let expectedPublicKey = arguments.count >= 4 ? arguments[3] : nil
    do {
        let publicKey = try verifyManifest(at: manifestURL, expectedPublicKey: expectedPublicKey)
        print(publicKey)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
    exit(0)
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

private func verifyManifest(at manifestURL: URL, expectedPublicKey: String?) throws -> String {
    let data = try Data(contentsOf: manifestURL)
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SignError.message("manifest must be a JSON object")
    }
    guard let signatureObject = object["signature"] as? [String: Any],
          let algorithm = signatureObject["algorithm"] as? String,
          let publicKeyBase64 = signatureObject["publicKey"] as? String,
          let signatureBase64 = signatureObject["value"] as? String
    else {
        throw SignError.message("manifest missing Ed25519 signature")
    }
    guard algorithm == "Ed25519" else {
        throw SignError.message("unsupported signature algorithm: \(algorithm)")
    }
    if let expectedPublicKey,
       expectedPublicKey.trimmingCharacters(in: .whitespacesAndNewlines) != publicKeyBase64 {
        throw SignError.message("update signing key mismatch: expected \(expectedPublicKey), got \(publicKeyBase64)")
    }
    guard let publicKeyData = Data(base64Encoded: publicKeyBase64),
          let signatureData = Data(base64Encoded: signatureBase64)
    else {
        throw SignError.message("manifest signature is not valid Base64")
    }

    object.removeValue(forKey: "signature")
    let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    guard publicKey.isValidSignature(signatureData, for: canonical) else {
        throw SignError.message("manifest Ed25519 signature verification failed")
    }
    return publicKeyBase64
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
