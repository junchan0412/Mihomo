import Foundation
import MihomoShared

/// 本机没有 Developer ID / notarization 时，SMAppService 的 LaunchDaemon 无法启动。
/// 该兼容路径沿用 macOS 传统的 /Library/PrivilegedHelperTools 安装方式，
/// 只在用户明确执行“修复 Helper”或核心启动自愈时触发管理员授权。
final class LegacyHelperInstaller {
    static let helperFileName = "dev.codex.Mihomo.Helper"
    static let plistFileName = "dev.codex.Mihomo.Helper.plist"
    static let authorizationFileName = "dev.codex.Mihomo.Helper.authorization.plist"
    static let label = "dev.codex.Mihomo.Helper"

    private let fileManager = FileManager.default

    var helperURL: URL {
        URL(fileURLWithPath: "/Library/PrivilegedHelperTools")
            .appendingPathComponent(Self.helperFileName)
    }

    var plistURL: URL {
        URL(fileURLWithPath: "/Library/LaunchDaemons")
            .appendingPathComponent(Self.plistFileName)
    }

    var authorizationURL: URL {
        URL(fileURLWithPath: "/Library/PrivilegedHelperTools")
            .appendingPathComponent(Self.authorizationFileName)
    }

    var isInstalled: Bool {
        fileManager.isExecutableFile(atPath: helperURL.path)
            && fileManager.fileExists(atPath: plistURL.path)
            && fileManager.fileExists(atPath: authorizationURL.path)
    }

    func bundledSMAppServiceIsSupported(appBundleURL: URL = Bundle.main.bundleURL) -> Bool {
        let helper = appBundleURL
            .appendingPathComponent("Contents/Library/LaunchServices", isDirectory: true)
            .appendingPathComponent("MihomoHelper")
        guard let appDetails = try? Shell.run("/usr/bin/codesign", ["-dv", "--verbose=4", appBundleURL.path]),
              let helperDetails = try? Shell.run("/usr/bin/codesign", ["-dv", "--verbose=4", helper.path])
        else { return false }
        return Self.signaturesSupportBundledSMAppService(
            appOutput: appDetails.stdout + appDetails.stderr,
            helperOutput: helperDetails.stdout + helperDetails.stderr
        )
    }

    static func signaturesSupportBundledSMAppService(appOutput: String, helperOutput: String) -> Bool {
        guard signatureValue("Identifier", in: appOutput) == MihomoHelperConstants.appBundleIdentifier,
              signatureValue("Identifier", in: helperOutput) == label,
              let appTeam = signatureValue("TeamIdentifier", in: appOutput),
              let helperTeam = signatureValue("TeamIdentifier", in: helperOutput),
              appTeam.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil,
              appTeam == helperTeam
        else { return false }

        let acceptedAuthorities = ["Authority=Developer ID Application:", "Authority=Apple Development:"]
        return acceptedAuthorities.contains { authority in
            appOutput.contains(authority) && helperOutput.contains(authority)
        }
    }

    func install(appBundleURL: URL = Bundle.main.bundleURL) async throws {
        let source = appBundleURL
            .appendingPathComponent("Contents/Library/LaunchServices", isDirectory: true)
            .appendingPathComponent("MihomoHelper")
        guard fileManager.isExecutableFile(atPath: source.path) else {
            throw installerError("App Bundle 中没有可执行 MihomoHelper。")
        }

        let appVerify = try Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appBundleURL.path])
        guard appVerify.status == 0 else {
            throw installerError("当前 App 签名无效，拒绝安装传统 Helper。")
        }
        let helperVerify = try Shell.run("/usr/bin/codesign", ["--verify", "--strict", source.path])
        guard helperVerify.status == 0 else {
            throw installerError("App Bundle 内 Helper 签名无效。")
        }
        let helperSignature = try Shell.run("/usr/bin/codesign", ["-dv", "--verbose=4", source.path])
        guard Self.signatureValue("Identifier", in: helperSignature.stdout + helperSignature.stderr) == Self.label else {
            throw installerError("App Bundle 内 Helper identifier 不匹配。")
        }

        let signature = try Shell.run("/usr/bin/codesign", ["-dv", "--verbose=4", appBundleURL.path])
        let signatureOutput = signature.stdout + signature.stderr
        guard let cdHash = Self.signatureValue("CDHash", in: signatureOutput), cdHash.isEmpty == false else {
            throw installerError("无法读取当前 App 的签名 CDHash。")
        }

        let staging = AppPaths.runtimeDirectory
            .appendingPathComponent("legacy-helper-\(UUID().uuidString).plist")
        let authorizationStaging = AppPaths.runtimeDirectory
            .appendingPathComponent("legacy-helper-authorization-\(UUID().uuidString).plist")
        try fileManager.createDirectory(at: AppPaths.runtimeDirectory, withIntermediateDirectories: true)
        try Self.legacyPlist(helperPath: helperURL.path).write(to: staging, atomically: true, encoding: .utf8)
        try Self.authorizationPlist(appPath: appBundleURL.path, cdHash: cdHash)
            .write(to: authorizationStaging, atomically: true, encoding: .utf8)
        defer {
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: authorizationStaging)
        }

        let command = Self.installationCommand(
            sourcePath: source.path,
            sourceSHA256: try ArtifactChecksum.sha256(fileURL: source),
            helperPath: helperURL.path,
            stagingPlistPath: staging.path,
            stagingPlistSHA256: try ArtifactChecksum.sha256(fileURL: staging),
            plistPath: plistURL.path,
            stagingAuthorizationPath: authorizationStaging.path,
            stagingAuthorizationSHA256: try ArtifactChecksum.sha256(fileURL: authorizationStaging),
            authorizationPath: authorizationURL.path
        )
        try await runAsAdministrator(command)
    }

    static func installationCommand(
        sourcePath: String,
        sourceSHA256: String,
        helperPath: String,
        stagingPlistPath: String,
        stagingPlistSHA256: String,
        plistPath: String,
        stagingAuthorizationPath: String,
        stagingAuthorizationSHA256: String,
        authorizationPath: String
    ) -> String {
        """
        set -eu
        /bin/mkdir -p /Library/PrivilegedHelperTools
        helper_tmp=\(shellQuote(helperPath + ".installing"))".$$"
        authorization_tmp=\(shellQuote(authorizationPath + ".installing"))".$$"
        plist_tmp=\(shellQuote(plistPath + ".installing"))".$$"
        cleanup() { /bin/rm -f "$helper_tmp" "$authorization_tmp" "$plist_tmp"; }
        trap cleanup EXIT HUP INT TERM
        /bin/cp \(shellQuote(sourcePath)) "$helper_tmp"
        /bin/cp \(shellQuote(stagingAuthorizationPath)) "$authorization_tmp"
        /bin/cp \(shellQuote(stagingPlistPath)) "$plist_tmp"
        test "$(/usr/bin/shasum -a 256 "$helper_tmp" | /usr/bin/awk '{print $1}')" = \(shellQuote(sourceSHA256))
        test "$(/usr/bin/shasum -a 256 "$authorization_tmp" | /usr/bin/awk '{print $1}')" = \(shellQuote(stagingAuthorizationSHA256))
        test "$(/usr/bin/shasum -a 256 "$plist_tmp" | /usr/bin/awk '{print $1}')" = \(shellQuote(stagingPlistSHA256))
        /usr/sbin/chown root:wheel "$helper_tmp" "$authorization_tmp" "$plist_tmp"
        /bin/chmod 755 "$helper_tmp"
        /bin/chmod 600 "$authorization_tmp"
        /bin/chmod 644 "$plist_tmp"
        /bin/launchctl bootout system/\(Self.label) >/dev/null 2>&1 || true
        /bin/mv -f "$helper_tmp" \(shellQuote(helperPath))
        /bin/mv -f "$authorization_tmp" \(shellQuote(authorizationPath))
        /bin/mv -f "$plist_tmp" \(shellQuote(plistPath))
        /bin/launchctl bootstrap system \(shellQuote(plistPath))
        /bin/launchctl enable system/\(Self.label)
        /bin/launchctl kickstart -k system/\(Self.label)
        """
    }

    func uninstall() async throws {
        let command = """
        /bin/launchctl bootout system/\(Self.label) >/dev/null 2>&1 || true
        /bin/rm -f \(Self.shellQuote(plistURL.path)) \(Self.shellQuote(helperURL.path)) \(Self.shellQuote(authorizationURL.path))
        """
        try await runAsAdministrator(command)
    }

    static func legacyPlist(helperPath: String) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(Self.label)</string>
          <key>AssociatedBundleIdentifiers</key>
          <string>dev.codex.Mihomo</string>
          <key>Program</key>
          <string>\(xmlEscape(helperPath))</string>
          <key>ProgramArguments</key>
          <array><string>\(xmlEscape(helperPath))</string></array>
          <key>MachServices</key>
          <dict><key>\(Self.label)</key><true/></dict>
          <key>RunAtLoad</key>
          <true/>
        </dict>
        </plist>
        """
    }

    static func authorizationPlist(appPath: String, cdHash: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>AuthorizedAppPath</key>
          <string>\(xmlEscape(appPath))</string>
          <key>AuthorizedAppBundleIdentifier</key>
          <string>dev.codex.Mihomo</string>
          <key>AuthorizedAppCDHash</key>
          <string>\(xmlEscape(cdHash.lowercased()))</string>
        </dict>
        </plist>
        """
    }

    static func signatureValue(_ name: String, in output: String) -> String? {
        let prefix = "\(name)="
        return output.components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix(prefix) })
            .map { String($0.dropFirst(prefix.count)) }
    }

    private func runAsAdministrator(_ command: String) async throws {
        let shellCommand = Self.flattenedShellCommand(command)
        let script = "with timeout of 3600 seconds\nreturn do shell script \(appleScriptQuote(shellCommand)) with administrator privileges\nend timeout"
        let result = try await Task.detached(priority: .userInitiated) {
            try Shell.run("/usr/bin/osascript", ["-e", script])
        }.value
        guard result.status == 0 else {
            throw installerError(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    static func flattenedShellCommand(_ command: String) -> String {
        command
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: "; ")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptQuote(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func installerError(_ message: String) -> NSError {
        NSError(domain: "Mihomo.LegacyHelperInstaller", code: 1, userInfo: [
            NSLocalizedDescriptionKey: message.isEmpty ? "传统 Helper 安装失败" : message
        ])
    }
}
