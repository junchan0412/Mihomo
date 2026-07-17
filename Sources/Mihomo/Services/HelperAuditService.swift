import Foundation
import MihomoShared

struct HelperAuditService {
    private let appBundleURL: URL
    private let appVersion: String
    private let appBuild: String

    init(
        appBundleURL: URL = Bundle.main.bundleURL,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        appBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    ) {
        self.appBundleURL = appBundleURL
        self.appVersion = appVersion
        self.appBuild = appBuild
    }

    func localAuditResults(helperStatus: String) -> [DiagnosticResult] {
        [
            bundleLayoutResult(),
            daemonPlistResult(),
            appSignatureResult(),
            helperSignatureResult(),
            legacyHelperResult(),
            serviceStatusResult(helperStatus: helperStatus),
            notarizationResult()
        ]
    }

    func runtimeBindingResult(helperVersion: HelperOperationResult) -> DiagnosticResult {
        HelperRuntimeBindingAudit.evaluate(
            currentAppURL: appBundleURL,
            currentVersion: appVersion,
            currentBuild: appBuild,
            payload: helperVersion.payload
        )
    }

    private func bundleLayoutResult() -> DiagnosticResult {
        let helperURL = helperExecutableURL
        let plistURL = daemonPlistURL
        let helperOK = FileManager.default.isExecutableFile(atPath: helperURL.path)
        let plistOK = FileManager.default.fileExists(atPath: plistURL.path)
        return DiagnosticResult(
            title: "Helper Bundle 布局",
            detail: "Helper：\(helperURL.path)\nPlist：\(plistURL.path)",
            state: helperOK && plistOK ? .ok : .failed
        )
    }

    private func daemonPlistResult() -> DiagnosticResult {
        let plistURL = daemonPlistURL
        guard let plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
            return DiagnosticResult(title: "Helper Plist", detail: "无法读取 \(plistURL.path)", state: .failed)
        }

        let label = plist["Label"] as? String
        let bundleProgram = plist["BundleProgram"] as? String
        let machServices = plist["MachServices"] as? [String: Bool]
        let ok = label == MihomoHelperConstants.machServiceName
            && bundleProgram == "Contents/Library/LaunchServices/\(MihomoHelperConstants.helperExecutableName)"
            && machServices?[MihomoHelperConstants.machServiceName] == true
        return DiagnosticResult(
            title: "Helper Plist",
            detail: "Label：\(label ?? "-")\nBundleProgram：\(bundleProgram ?? "-")\nMachService：\(machServices?[MihomoHelperConstants.machServiceName] == true ? "已声明" : "缺失")",
            state: ok ? .ok : .failed
        )
    }

    private func appSignatureResult() -> DiagnosticResult {
        signatureResult(
            title: "App 签名",
            url: appBundleURL,
            expectedIdentifier: MihomoHelperConstants.appBundleIdentifier,
            deep: true
        )
    }

    private func helperSignatureResult() -> DiagnosticResult {
        signatureResult(
            title: "Helper 签名",
            url: helperExecutableURL,
            expectedIdentifier: MihomoHelperConstants.machServiceName,
            deep: false
        )
    }

    private func serviceStatusResult(helperStatus: String) -> DiagnosticResult {
        let state: DiagnosticState
        if helperStatus.contains("已注册") {
            state = .ok
        } else if helperStatus.contains("传统 Helper") || helperStatus.contains("批准") || helperStatus.contains("未注册") {
            state = .warning
        } else {
            state = .failed
        }
        return DiagnosticResult(title: "SMAppService 状态", detail: helperStatus, state: state)
    }

    private func legacyHelperResult() -> DiagnosticResult {
        let helper = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/dev.codex.Mihomo.Helper")
        let authorization = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/dev.codex.Mihomo.Helper.authorization.plist")
        let plist = URL(fileURLWithPath: "/Library/LaunchDaemons/dev.codex.Mihomo.Helper.plist")
        let exists = FileManager.default.isExecutableFile(atPath: helper.path)
            && FileManager.default.fileExists(atPath: authorization.path)
            && FileManager.default.fileExists(atPath: plist.path)
        return DiagnosticResult(
            title: "传统 Helper 兼容路径",
            detail: exists
                ? "已安装。Helper 使用 root 所有的授权文件绑定当前 App 路径与签名 CDHash；App 更新后必须重新授权安装。"
                : "未安装。Developer ID + notarization 可直接使用 SMAppService；无开发者账户时可通过“修复 Helper”安装兼容路径。",
            state: exists ? .warning : .ok
        )
    }

    private func notarizationResult() -> DiagnosticResult {
        let details = try? Shell.run("/usr/bin/codesign", ["-dv", "--verbose=4", appBundleURL.path])
        let signatureOutput = [details?.stdout, details?.stderr].compactMap { $0 }.joined(separator: "\n")
        let hasDeveloperID = signatureOutput.contains("Authority=Developer ID Application:")
        let gatekeeper = try? Shell.run("/usr/sbin/spctl", ["-a", "-vv", "--type", "execute", appBundleURL.path])
        if hasDeveloperID && gatekeeper?.status == 0 {
            return DiagnosticResult(
                title: "公证 / Gatekeeper",
                detail: "Developer ID 签名与 Gatekeeper 评估通过，可使用 SMAppService LaunchDaemon。",
                state: .ok
            )
        }
        return DiagnosticResult(
            title: "公证 / Gatekeeper",
            detail: "SMAppService LaunchDaemon 的正式发行需要 Developer ID 与 Apple notarization。无开发者账户的构建只能使用需管理员确认的传统 Helper 兼容路径；应用内正式更新还会校验 manifest、TeamIdentifier、主 App 与 Helper 的 Developer ID 身份。",
            state: .warning
        )
    }

    private func signatureResult(title: String, url: URL, expectedIdentifier: String, deep: Bool) -> DiagnosticResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return DiagnosticResult(title: title, detail: "文件不存在：\(url.path)", state: .failed)
        }

        let verifyArgs = deep ? ["--verify", "--deep", "--strict", url.path] : ["--verify", "--strict", url.path]
        let verify = try? Shell.run("/usr/bin/codesign", verifyArgs)
        let details = try? Shell.run("/usr/bin/codesign", ["-dv", "--verbose=4", url.path])
        let output = [details?.stdout, details?.stderr]
            .compactMap { $0 }
            .joined(separator: "\n")
        let identifier = signatureValue(named: "Identifier", in: output)
        let signature = signatureValue(named: "Signature", in: output)
        let team = signatureValue(named: "TeamIdentifier", in: output)
        let ok = verify?.status == 0 && identifier == expectedIdentifier
        let verifyText = verify?.status == 0 ? "通过" : ((verify?.stderr.isEmpty == false ? verify?.stderr : verify?.stdout) ?? "未执行")
        return DiagnosticResult(
            title: title,
            detail: "路径：\(url.path)\nIdentifier：\(identifier ?? "-")\nSignature：\(signature ?? "-")\nTeam：\(team ?? "not set")\nVerify：\(verifyText)",
            state: ok ? .ok : .failed
        )
    }

    private func signatureValue(named name: String, in output: String) -> String? {
        let prefix = "\(name)="
        for line in output.components(separatedBy: .newlines) where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private var helperExecutableURL: URL {
        appBundleURL
            .appendingPathComponent("Contents/Library/LaunchServices", isDirectory: true)
            .appendingPathComponent(MihomoHelperConstants.helperExecutableName)
    }

    private var daemonPlistURL: URL {
        appBundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons", isDirectory: true)
            .appendingPathComponent(MihomoHelperConstants.daemonPlistName)
    }
}

enum HelperRuntimeBindingAudit {
    static func evaluate(
        currentAppURL: URL,
        currentVersion: String,
        currentBuild: String,
        payload: [String: String]
    ) -> DiagnosticResult {
        let expectedPath = currentAppURL.standardizedFileURL.resolvingSymlinksInPath().path
        let rawActualPath = payload["authorizedAppBundle"] ?? ""
        let actualPath = rawActualPath.isEmpty ? "" : URL(fileURLWithPath: rawActualPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        let actualVersion = payload["authorizedAppVersion"] ?? ""
        let actualBuild = payload["authorizedAppBuild"] ?? ""
        let pathMatches = actualPath == expectedPath
        let versionMatches = currentVersion.isEmpty || actualVersion.isEmpty || actualVersion == currentVersion
        let buildMatches = currentBuild.isEmpty || actualBuild.isEmpty || actualBuild == currentBuild

        let state: DiagnosticState = pathMatches && versionMatches && buildMatches ? .ok : .warning
        return DiagnosticResult(
            title: "Helper 运行绑定",
            detail: "当前 App：\(expectedPath)\nHelper 授权 App：\(actualPath.isEmpty ? "-" : actualPath)\n当前版本：\(currentVersion.isEmpty ? "-" : currentVersion) (\(currentBuild.isEmpty ? "-" : currentBuild))\nHelper 版本：\(actualVersion.isEmpty ? "-" : actualVersion) (\(actualBuild.isEmpty ? "-" : actualBuild))",
            state: state
        )
    }
}
