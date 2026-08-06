import CryptoKit
import Foundation

extension SoftwareUpdateManager {
    func validateManifest(_ manifest: AppUpdateManifest) throws {
        guard manifest.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw updateError("manifest 缺少 version。")
        }
        guard manifest.sha256.range(of: #"^[A-Fa-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw updateError("manifest 的 sha256 必须是 64 位十六进制。")
        }
        let expectedID = expectedBundleIdentifier
        guard manifest.bundleIdentifier == expectedID else {
            throw updateError("manifest bundle id 不匹配：\(manifest.bundleIdentifier ?? "缺失")。")
        }
        guard manifest.signingIdentifier == expectedID else {
            throw updateError("manifest signing identifier 不匹配：\(manifest.signingIdentifier ?? "缺失")。")
        }
        if let build = manifest.build,
           build.range(of: #"^[0-9]+(?:\.[0-9]+){0,2}$"#, options: .regularExpression) == nil {
            throw updateError("manifest build 必须是一至三段数字。")
        }
        if let minimum = manifest.minimumSystemVersion,
           SoftwareVersionComparator.compare(systemVersionString(), minimum) == .orderedAscending {
            throw updateError("当前 macOS 版本低于 \(minimum)。")
        }
        guard manifest.signature != nil else {
            throw updateError("manifest 缺少 Ed25519 签名。")
        }
        guard let helperIdentifier = manifest.helperSigningIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              helperIdentifier == "dev.codex.Mihomo.Helper" else {
            throw updateError("manifest 的 Helper 签名 identifier 无效。")
        }
        switch effectiveSigningMode(manifest) {
        case "developer-id":
            guard let teamIdentifier = manifest.teamIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                  teamIdentifier.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil else {
                throw updateError("Developer ID manifest 缺少有效 TeamIdentifier。")
            }
        case "adhoc":
            guard isValidCDHash(manifest.appCDHash), isValidCDHash(manifest.helperCDHash) else {
                throw updateError("ad-hoc manifest 必须固定主 App 与 Helper 的 CDHash。")
            }
        default:
            throw updateError("manifest 缺少受支持的 signingMode。")
        }
    }

    func validateManifestSignature(_ data: Data) throws {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw updateError("manifest 不是 JSON 对象。")
        }
        guard let signatureObject = object["signature"] as? [String: Any],
              let algorithm = signatureObject["algorithm"] as? String,
              let publicKeyBase64 = signatureObject["publicKey"] as? String,
              let signatureBase64 = signatureObject["value"] as? String
        else {
            throw updateError("manifest 缺少 Ed25519 签名。")
        }
        guard algorithm == "Ed25519" else {
            throw updateError("manifest 签名算法不受支持：\(algorithm)。")
        }
        guard publicKeyBase64 == UpdateSigningKey.publicKeyBase64 else {
            throw updateError("manifest 签名公钥不匹配。")
        }
        guard let publicKeyData = Data(base64Encoded: publicKeyBase64),
              let signatureData = Data(base64Encoded: signatureBase64)
        else {
            throw updateError("manifest 签名不是有效 Base64。")
        }

        object.removeValue(forKey: "signature")
        let canonicalData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        guard publicKey.isValidSignature(signatureData, for: canonicalData) else {
            throw updateError("manifest Ed25519 签名验证失败。")
        }
    }

    func effectiveSigningMode(_ manifest: AppUpdateManifest) -> String {
        if let mode = manifest.signingMode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           mode.isEmpty == false {
            return mode
        }
        return manifest.teamIdentifier == nil ? "" : "developer-id"
    }

    func isValidCDHash(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return value.range(of: #"^(?:[A-Fa-f0-9]{40}|[A-Fa-f0-9]{64})$"#, options: .regularExpression) != nil
    }
}
