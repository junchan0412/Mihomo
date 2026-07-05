import AppKit
import CryptoKit
import Foundation

struct AppUpdateManifest: Codable, Hashable {
    var version: String
    var build: String?
    var url: String
    var sha256: String
    var notes: String?
    var minimumSystemVersion: String?
    var bundleIdentifier: String?
    var signingIdentifier: String?
    var publishedAt: Date?
    var signature: AppUpdateSignature?
}

struct AppUpdateSignature: Codable, Hashable {
    var algorithm: String
    var publicKey: String
    var value: String
}

struct AppUpdateCheckResult: Hashable {
    var manifest: AppUpdateManifest
    var isNewer: Bool
    var currentVersion: String
}

final class SoftwareUpdateManager {
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    func checkForUpdate(manifestURLString: String) async throws -> AppUpdateCheckResult {
        let manifestURL = try resolvedManifestURL(manifestURLString)
        let (data, response) = try await URLSession.shared.data(from: manifestURL)
        try validateHTTP(response: response, data: data)
        try validateManifestSignature(data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(AppUpdateManifest.self, from: data)
        try validateManifest(manifest)
        return AppUpdateCheckResult(
            manifest: manifest,
            isNewer: compareVersions(manifest.version, currentVersion) == .orderedDescending,
            currentVersion: currentVersion
        )
    }

    func installUpdate(_ manifest: AppUpdateManifest, manifestURLString: String) async throws -> String {
        let manifestURL = try resolvedManifestURL(manifestURLString)
        let packageURL = try resolvedPackageURL(manifest.url, manifestURL: manifestURL)
        let tempRoot = AppPaths.runtimeDirectory.appendingPathComponent("app-update-\(UUID().uuidString)", isDirectory: true)
        let unpackRoot = tempRoot.appendingPathComponent("unpack", isDirectory: true)
        try FileManager.default.createDirectory(at: unpackRoot, withIntermediateDirectories: true)

        let (downloaded, response) = try await URLSession.shared.download(from: packageURL)
        try validateHTTP(response: response, data: Data())
        let zipURL = tempRoot.appendingPathComponent(packageURL.lastPathComponent.isEmpty ? "update.zip" : packageURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }
        try FileManager.default.copyItem(at: downloaded, to: zipURL)
        try validateSHA256(fileURL: zipURL, expected: manifest.sha256)

        let unzip = try Shell.run("/usr/bin/unzip", ["-q", zipURL.path, "-d", unpackRoot.path])
        guard unzip.status == 0 else {
            throw updateError(unzip.stderr.isEmpty ? unzip.stdout : unzip.stderr)
        }

        let candidate = try locateAppBundle(in: unpackRoot)
        try validateCandidateBundle(candidate, manifest: manifest)
        let script = try writeInstallScript(tempRoot: tempRoot)
        try launchInstallScript(script: script, candidate: candidate, tempRoot: tempRoot)
        return "更新 \(manifest.version) 已验证，Mihomo 将退出并由安装器替换应用。"
    }

    private func resolvedManifestURL(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, let url = URL(string: trimmed), url.scheme != nil else {
            throw updateError("请先填写完整的更新 manifest URL。")
        }
        return url
    }

    private func resolvedPackageURL(_ value: String, manifestURL: URL) throws -> URL {
        guard let url = URL(string: value, relativeTo: manifestURL)?.absoluteURL,
              url.scheme != nil else {
            throw updateError("更新包 URL 无效。")
        }
        return url
    }

    private func validateManifest(_ manifest: AppUpdateManifest) throws {
        guard manifest.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw updateError("manifest 缺少 version。")
        }
        guard manifest.sha256.range(of: #"^[A-Fa-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw updateError("manifest 的 sha256 必须是 64 位十六进制。")
        }
        let expectedID = Bundle.main.bundleIdentifier ?? "dev.codex.Mihomo"
        if let bundleIdentifier = manifest.bundleIdentifier, bundleIdentifier != expectedID {
            throw updateError("manifest bundle id 不匹配：\(bundleIdentifier)。")
        }
        if let minimum = manifest.minimumSystemVersion,
           compareVersions(systemVersionString(), minimum) == .orderedAscending {
            throw updateError("当前 macOS 版本低于 \(minimum)。")
        }
        guard manifest.signature != nil else {
            throw updateError("manifest 缺少 Ed25519 签名。")
        }
    }

    private func validateManifestSignature(_ data: Data) throws {
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
        let canonicalData = try canonicalManifestData(object)
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        guard publicKey.isValidSignature(signatureData, for: canonicalData) else {
            throw updateError("manifest Ed25519 签名验证失败。")
        }
    }

    private func canonicalManifestData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func validateCandidateBundle(_ appURL: URL, manifest: AppUpdateManifest) throws {
        let expectedID = manifest.bundleIdentifier ?? Bundle.main.bundleIdentifier ?? "dev.codex.Mihomo"
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
              info["CFBundleIdentifier"] as? String == expectedID else {
            throw updateError("更新包 bundle id 不匹配。")
        }

        let expectedVersion = manifest.version.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bundleVersion = info["CFBundleShortVersionString"] as? String,
           bundleVersion.trimmingCharacters(in: .whitespacesAndNewlines) != expectedVersion {
            throw updateError("更新包版本 \(bundleVersion) 与 manifest \(expectedVersion) 不一致。")
        }

        let verify = try Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
        guard verify.status == 0 else {
            throw updateError("更新包签名验证失败：\(verify.stderr.isEmpty ? verify.stdout : verify.stderr)")
        }

        let details = try Shell.run("/usr/bin/codesign", ["-dv", "--verbose=4", appURL.path])
        let signatureOutput = details.stdout + details.stderr
        let signingIdentifier = manifest.signingIdentifier ?? expectedID
        guard signatureOutput.contains("Identifier=\(signingIdentifier)") else {
            throw updateError("更新包签名 identifier 不匹配，应为 \(signingIdentifier)。")
        }
    }

    private func validateSHA256(fileURL: URL, expected: String) throws {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest.lowercased() == expected.lowercased() else {
            throw updateError("更新包 SHA-256 不匹配。")
        }
    }

    private func locateAppBundle(in directory: URL) throws -> URL {
        let direct = directory.appendingPathComponent("Mihomo.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw updateError("无法读取更新包内容。")
        }
        for case let item as URL in enumerator where item.pathExtension == "app" && item.lastPathComponent == "Mihomo.app" {
            return item
        }
        throw updateError("更新包中没有 Mihomo.app。")
    }

    private func writeInstallScript(tempRoot: URL) throws -> URL {
        let script = tempRoot.appendingPathComponent("install-update.sh")
        let body = """
        #!/bin/sh
        set -eu
        current="$1"
        candidate="$2"
        temp="$3"
        backup="${current}.previous-update"

        while /usr/bin/pgrep -x "Mihomo" >/dev/null 2>&1; do
          /bin/sleep 0.2
        done

        /bin/rm -rf "$backup"
        if [ -e "$current" ]; then
          /bin/mv "$current" "$backup"
        fi

        /usr/bin/ditto "$candidate" "$current"
        /usr/bin/xattr -dr com.apple.quarantine "$current" >/dev/null 2>&1 || true

        if ! /usr/bin/codesign --verify --deep --strict "$current" >/dev/null 2>&1; then
          /bin/rm -rf "$current"
          if [ -e "$backup" ]; then
            /bin/mv "$backup" "$current"
          fi
          exit 1
        fi

        /usr/bin/open "$current"
        /bin/rm -rf "$backup" "$temp"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func launchInstallScript(script: URL, candidate: URL, tempRoot: URL) throws {
        let currentApp = Bundle.main.bundleURL
        guard currentApp.pathExtension == "app" else {
            throw updateError("当前运行目标不是 .app bundle，无法执行应用内更新。")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, currentApp.path, candidate.path, tempRoot.path]
        try process.run()
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw updateError(body)
        }
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionNumbers(lhs)
        let right = versionNumbers(rhs)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l > r { return .orderedDescending }
            if l < r { return .orderedAscending }
        }
        return .orderedSame
    }

    private func versionNumbers(_ value: String) -> [Int] {
        value.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { $0.isEmpty ? nil : Int($0) }
    }

    private func systemVersionString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private func updateError(_ message: String) -> NSError {
        NSError(domain: "SoftwareUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
