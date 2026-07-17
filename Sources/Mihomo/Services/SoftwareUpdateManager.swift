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
    var helperSigningIdentifier: String?
    var teamIdentifier: String?
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
    var manifestURL: URL
    var isNewer: Bool
    var currentVersion: String
    var currentBuild: String
}

struct PreparedUpdatePackage {
    var candidate: URL
    var installScript: URL
    var tempRoot: URL
}

final class SoftwareUpdateManager {
    static let githubLatestManifestURL = URL(string: "https://github.com/junchan0412/Mihomo/releases/latest/download/mihomo-update.json")!
    static let githubReleasesPage = URL(string: "https://github.com/junchan0412/Mihomo/releases/latest")!

    private let expectedBundleIdentifier: String

    init(expectedBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "dev.codex.Mihomo") {
        self.expectedBundleIdentifier = expectedBundleIdentifier
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    func checkForUpdate() async throws -> AppUpdateCheckResult {
        try await checkForUpdate(manifestURL: Self.githubLatestManifestURL)
    }

    func checkForUpdate(manifestURL: URL) async throws -> AppUpdateCheckResult {
        var request = URLRequest(url: manifestURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mihomo", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await NetworkClient.data(for: request)
        try validateHTTP(response: response, data: data)
        try validateManifestSignature(data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(AppUpdateManifest.self, from: data)
        try validateManifest(manifest)
        return AppUpdateCheckResult(
            manifest: manifest,
            manifestURL: manifestURL,
            isNewer: isManifestNewer(manifest),
            currentVersion: currentVersion,
            currentBuild: currentBuild
        )
    }

    func prepareUpdate(_ manifest: AppUpdateManifest, manifestURL: URL) async throws -> PreparedUpdatePackage {
        let packageURL = try resolvedPackageURL(manifest.url, manifestURL: manifestURL)
        let tempRoot = AppPaths.runtimeDirectory.appendingPathComponent("app-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

            let (downloaded, response) = try await NetworkClient.download(from: packageURL)
            try validateHTTP(response: response, data: Data())
            let zipURL = tempRoot.appendingPathComponent(packageURL.lastPathComponent.isEmpty ? "update.zip" : packageURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: zipURL.path) {
                try FileManager.default.removeItem(at: zipURL)
            }
            try FileManager.default.copyItem(at: downloaded, to: zipURL)

            return try prepareDownloadedUpdatePackage(zipURL: zipURL, manifest: manifest, tempRoot: tempRoot)
        } catch {
            try? FileManager.default.removeItem(at: tempRoot)
            throw error
        }
    }

    func launchPreparedUpdate(_ prepared: PreparedUpdatePackage, version: String) throws -> String {
        try launchInstallScript(
            script: prepared.installScript,
            candidate: prepared.candidate,
            tempRoot: prepared.tempRoot
        )
        return "更新 \(version) 已验证，Mihomo 将退出并由安装器替换应用。"
    }

    func discardPreparedUpdate(_ prepared: PreparedUpdatePackage) {
        try? FileManager.default.removeItem(at: prepared.tempRoot)
    }

    func prepareDownloadedUpdatePackage(zipURL: URL, manifest: AppUpdateManifest, tempRoot: URL) throws -> PreparedUpdatePackage {
        let unpackRoot = tempRoot.appendingPathComponent("unpack", isDirectory: true)
        try FileManager.default.createDirectory(at: unpackRoot, withIntermediateDirectories: true)

        try validateSHA256(fileURL: zipURL, expected: manifest.sha256)

        let unzip = try Shell.run("/usr/bin/unzip", ["-q", zipURL.path, "-d", unpackRoot.path])
        guard unzip.status == 0 else {
            throw updateError(unzip.stderr.isEmpty ? unzip.stdout : unzip.stderr)
        }

        let candidate = try locateAppBundle(in: unpackRoot)
        try validateCandidateBundle(candidate, manifest: manifest)
        let script = try writeInstallScript(tempRoot: tempRoot)
        return PreparedUpdatePackage(candidate: candidate, installScript: script, tempRoot: tempRoot)
    }

    private func resolvedPackageURL(_ value: String, manifestURL: URL) throws -> URL {
        guard let url = URL(string: value, relativeTo: manifestURL)?.absoluteURL,
              url.scheme != nil else {
            throw updateError("更新包 URL 无效。")
        }
        return url
    }

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
           compareVersions(systemVersionString(), minimum) == .orderedAscending {
            throw updateError("当前 macOS 版本低于 \(minimum)。")
        }
        guard manifest.signature != nil else {
            throw updateError("manifest 缺少 Ed25519 签名。")
        }
        guard let teamIdentifier = manifest.teamIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              teamIdentifier.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil else {
            throw updateError("manifest 缺少 Developer ID TeamIdentifier。")
        }
        guard let helperIdentifier = manifest.helperSigningIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              helperIdentifier == "dev.codex.Mihomo.Helper" else {
            throw updateError("manifest 的 Helper 签名 identifier 无效。")
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
        let expectedID = manifest.bundleIdentifier ?? expectedBundleIdentifier
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
        guard let teamIdentifier = manifest.teamIdentifier,
              signatureOutput.contains("TeamIdentifier=\(teamIdentifier)"),
              signatureOutput.contains("Authority=Developer ID Application:") else {
            throw updateError("更新包必须由 Team \(manifest.teamIdentifier ?? "-") 的 Developer ID Application 签名。")
        }

        let helperURL = appURL
            .appendingPathComponent("Contents/Library/LaunchServices", isDirectory: true)
            .appendingPathComponent("MihomoHelper")
        let helperVerify = try Shell.run("/usr/bin/codesign", ["--verify", "--strict", helperURL.path])
        guard helperVerify.status == 0 else {
            throw updateError("更新包 Helper 签名验证失败：\(helperVerify.stderr.isEmpty ? helperVerify.stdout : helperVerify.stderr)")
        }
        let helperDetails = try Shell.run("/usr/bin/codesign", ["-dv", "--verbose=4", helperURL.path])
        let helperSignatureOutput = helperDetails.stdout + helperDetails.stderr
        guard helperSignatureOutput.contains("Identifier=\(manifest.helperSigningIdentifier ?? "dev.codex.Mihomo.Helper")"),
              helperSignatureOutput.contains("TeamIdentifier=\(teamIdentifier)"),
              helperSignatureOutput.contains("Authority=Developer ID Application:") else {
            throw updateError("更新包 Helper 与主 App 的 Developer ID 身份不一致。")
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

    func writeInstallScript(tempRoot: URL) throws -> URL {
        let script = tempRoot.appendingPathComponent("install-update.sh")
        let body = """
        #!/bin/sh
        set -eu
        current="$1"
        candidate="$2"
        temp="$3"
        backup="${current}.previous-update"

        restore_backup() {
          /bin/rm -rf "$current"
          if [ -e "$backup" ]; then
            /bin/mv "$backup" "$current"
          fi
        }

        is_current_app_running() {
          executable="$current/Contents/MacOS/Mihomo"
          for pid in $(/usr/bin/pgrep -x "Mihomo" 2>/dev/null || true); do
            command=$(/bin/ps -p "$pid" -o command= 2>/dev/null || true)
            case "$command" in
              "$executable"|"$executable "*) return 0 ;;
            esac
          done
          return 1
        }

        while is_current_app_running; do
          /bin/sleep 0.2
        done

        /bin/rm -rf "$backup"
        if [ -e "$current" ]; then
          /bin/mv "$current" "$backup"
        fi

        if ! /usr/bin/ditto "$candidate" "$current"; then
          restore_backup
          exit 1
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$current" >/dev/null 2>&1 || true

        if ! /usr/bin/codesign --verify --deep --strict "$current" >/dev/null 2>&1; then
          restore_backup
          exit 1
        fi

        /usr/bin/open -n "$current"
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

    func isManifestNewer(
        _ manifest: AppUpdateManifest,
        currentVersion: String? = nil,
        currentBuild: String? = nil
    ) -> Bool {
        let versionComparison = compareVersions(manifest.version, currentVersion ?? self.currentVersion)
        if versionComparison == .orderedDescending {
            return true
        }
        guard versionComparison == .orderedSame,
              let manifestBuild = manifest.build?.trimmingCharacters(in: .whitespacesAndNewlines),
              manifestBuild.isEmpty == false
        else {
            return false
        }
        let current = (currentBuild ?? self.currentBuild).trimmingCharacters(in: .whitespacesAndNewlines)
        return current.isEmpty || current != manifestBuild
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
