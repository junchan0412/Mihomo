import Foundation
import MihomoShared

final class HelperService: NSObject, MihomoHelperXPCProtocol {
    private let networkTool = HelperSystemNetworkTool()
    private lazy var tunTool = HelperTunRecoveryTool(networkTool: networkTool)
    private let coreRuntime = HelperCoreRuntime()
    private let coreLaunchDaemonTool = HelperCoreLaunchDaemonTool()
    private let appBundleURL: URL?
    private let userHomeDirectory: URL

    init(
        appBundleURL: URL? = nil,
        userHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.appBundleURL = appBundleURL
        self.userHomeDirectory = userHomeDirectory
    }

    func helperVersion(withReply reply: @escaping (NSDictionary) -> Void) {
        let appInfo = appBundleInfo()
        reply(HelperReply.ok("MihomoHelper 0.6.0", payload: [
            "machService": MihomoHelperConstants.machServiceName,
            "effectiveUID": Int(geteuid()),
            "authorizedUserHome": userHomeDirectory.path,
            "authorizedAppBundle": appBundleURL?.path ?? "",
            "authorizedAppVersion": appInfo.version,
            "authorizedAppBuild": appInfo.build
        ]))
    }

    func validateConfig(
        mihomoPath: NSString,
        configPath: NSString,
        workDirectory: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        do {
            let paths = try validatedCorePaths(
                mihomoPath: mihomoPath as String,
                configPath: configPath as String,
                workDirectory: workDirectory as String,
                logPath: nil
            )
            let output = try coreRuntime.validate(
                mihomoPath: paths.mihomoPath,
                configPath: paths.configPath,
                workDirectory: paths.workDirectory
            )
            reply(HelperReply.ok(output.isEmpty ? "mihomo 配置校验通过" : output, payload: ["validation": output]))
        } catch {
            reply(HelperReply.error(error))
        }
    }

    private func appBundleInfo() -> (version: String, build: String) {
        guard let appBundleURL else { return ("", "") }
        let infoURL = appBundleURL.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: infoURL) as? [String: Any]
        return (
            info?["CFBundleShortVersionString"] as? String ?? "",
            info?["CFBundleVersion"] as? String ?? ""
        )
    }

    func prepareAndStartCore(
        mihomoPath: NSString,
        configPath: NSString,
        workDirectory: NSString,
        logPath: NSString,
        proxySnapshotPath: NSString,
        dnsSnapshotPath: NSString,
        tunSnapshotPath: NSString,
        autoSetDNS: Bool,
        dnsServers: NSArray,
        captureTun: Bool,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        var steps: [String] = []
        do {
            let paths = try validatedCorePaths(
                mihomoPath: mihomoPath as String,
                configPath: configPath as String,
                workDirectory: workDirectory as String,
                logPath: logPath as String
            )
            _ = try validatedProxySnapshotPath(proxySnapshotPath as String)
            let dnsSnapshot = try validatedDNSSnapshotPath(dnsSnapshotPath as String)
            let tunSnapshot = try validatedTunSnapshotPath(tunSnapshotPath as String)

            if autoSetDNS {
                steps.append("捕获系统 DNS 快照并写入临时 DNS")
                try networkTool.setDNS(
                    dnsServers.compactMap { $0 as? String },
                    snapshotPath: dnsSnapshot
                )
            }

            var tunDetail = ""
            if captureTun {
                steps.append("捕获 TUN DNS/路由回滚快照")
                let snapshot = try tunTool.capture(
                    tunSnapshotPath: tunSnapshot
                )
                tunDetail = "已捕获 TUN 回滚快照：\(snapshot.createdAt)"
            }

            steps.append("校验并启动 mihomo core")
            let validation = try coreRuntime.start(
                mihomoPath: paths.mihomoPath,
                configPath: paths.configPath,
                workDirectory: paths.workDirectory,
                logPath: try requiredLogPath(paths)
            )
            reply(HelperReply.transactionOK("核心已由 Helper 启动", steps: steps, rollbackSuggestion: "若启动后网络异常，请在诊断页依次执行恢复 DNS、恢复 TUN 路由或停止核心。", payload: [
                "validation": validation,
                "tunDetail": tunDetail
            ]))
        } catch {
            reply(HelperReply.error(error, steps: steps, rollbackSuggestion: "启动事务部分失败。可在诊断页恢复 DNS、恢复 TUN 路由，并检查运行配置 dry-run 结果。"))
        }
    }

    func stopCore(
        restoreDNS: Bool,
        restoreTun: Bool,
        proxySnapshotPath: NSString,
        dnsSnapshotPath: NSString,
        tunSnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        var steps: [String] = []
        do {
            _ = try validatedProxySnapshotPath(proxySnapshotPath as String)
            let dnsSnapshot = try validatedDNSSnapshotPath(dnsSnapshotPath as String)
            let tunSnapshot = try validatedTunSnapshotPath(tunSnapshotPath as String)

            steps.append("停止 mihomo core 进程")
            coreRuntime.stop()
            var details: [String] = []
            if restoreTun {
                steps.append("恢复 TUN DNS/路由快照")
                details.append(try tunTool.restore(
                    tunSnapshotPath: tunSnapshot
                ))
            } else if restoreDNS {
                steps.append("恢复系统 DNS 快照")
                let restored = try networkTool.restoreDNS(snapshotPath: dnsSnapshot)
                details.append("已恢复 \(restored) 个网络服务的系统 DNS 快照")
            }
            reply(HelperReply.transactionOK(details.isEmpty ? "核心已由 Helper 停止" : details.joined(separator: "\n"), steps: steps, rollbackSuggestion: "若停止后仍无法联网，请在诊断页执行恢复代理、恢复 DNS、恢复 TUN 路由。"))
        } catch {
            reply(HelperReply.error(error, steps: steps, rollbackSuggestion: "停止事务部分失败。请在诊断页按需执行恢复代理、恢复 DNS、恢复 TUN 路由。"))
        }
    }

    func installCoreLaunchDaemon(
        corePath: NSString,
        configPath: NSString,
        workDirectory: NSString,
        logPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        do {
            let paths = try validatedCorePaths(
                mihomoPath: corePath as String,
                configPath: configPath as String,
                workDirectory: workDirectory as String,
                logPath: logPath as String
            )
            _ = try coreRuntime.validate(
                mihomoPath: paths.mihomoPath,
                configPath: paths.configPath,
                workDirectory: paths.workDirectory
            )
            let path = try coreLaunchDaemonTool.install(
                corePath: paths.mihomoPath,
                configPath: paths.configPath,
                workDirectory: paths.workDirectory,
                logPath: try requiredLogPath(paths)
            )
            reply(HelperReply.ok("Core LaunchDaemon 已安装并加载", payload: ["path": path]))
        } catch {
            reply(HelperReply.error(error))
        }
    }

    func uninstallCoreLaunchDaemon(withReply reply: @escaping (NSDictionary) -> Void) {
        do {
            try coreLaunchDaemonTool.uninstall()
            reply(HelperReply.ok("Core LaunchDaemon 已卸载"))
        } catch {
            reply(HelperReply.error(error))
        }
    }

    func startCoreLaunchDaemon(withReply reply: @escaping (NSDictionary) -> Void) {
        do {
            try coreLaunchDaemonTool.start()
            reply(HelperReply.ok("Core LaunchDaemon 已启动"))
        } catch {
            reply(HelperReply.error(error))
        }
    }

    func stopCoreLaunchDaemon(withReply reply: @escaping (NSDictionary) -> Void) {
        do {
            try coreLaunchDaemonTool.stop()
            reply(HelperReply.ok("Core LaunchDaemon 已停止"))
        } catch {
            reply(HelperReply.error(error))
        }
    }

    func setSystemProxy(
        host: NSString,
        mixedPort: Int32,
        socksPort: Int32,
        proxySnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        var steps: [String] = []
        do {
            let proxySnapshot = try validatedProxySnapshotPath(proxySnapshotPath as String)
            steps.append("捕获系统代理/DNS 快照")
            steps.append("为所有网络服务写入 HTTP/HTTPS/SOCKS 代理")
            try networkTool.enableProxy(
                host: host as String,
                mixedPort: Int(mixedPort),
                socksPort: Int(socksPort),
                snapshotPath: proxySnapshot
            )
            reply(HelperReply.transactionOK("系统代理已由 Helper 设置", steps: steps, rollbackSuggestion: "如代理端口残留，请在诊断页执行恢复代理或清理快照。"))
        } catch {
            reply(HelperReply.error(error, steps: steps, rollbackSuggestion: "系统代理写入部分失败。建议执行恢复代理，必要时清理快照后重试。"))
        }
    }

    func restoreSystemProxy(
        proxySnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        var steps: [String] = []
        do {
            let proxySnapshot = try validatedProxySnapshotPath(proxySnapshotPath as String)
            steps.append("读取系统代理快照")
            steps.append("恢复 HTTP/HTTPS/SOCKS 代理、绕过域名和 DNS")
            let count = try networkTool.restore(snapshotPath: proxySnapshot)
            reply(HelperReply.transactionOK("已恢复 \(count) 个网络服务的系统代理/DNS", steps: steps, rollbackSuggestion: "如快照不存在，Helper 已尝试关闭代理开关；仍异常时可在系统设置中手动检查网络服务。"))
        } catch {
            reply(HelperReply.error(error, steps: steps, rollbackSuggestion: "代理恢复失败。请检查网络服务名称是否变化，或在系统设置中手动关闭代理。"))
        }
    }

    func setSystemDNS(
        servers: NSArray,
        dnsSnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        var steps: [String] = []
        do {
            let dnsSnapshot = try validatedDNSSnapshotPath(dnsSnapshotPath as String)
            steps.append("捕获系统 DNS 快照")
            steps.append("写入临时 DNS 服务器")
            try networkTool.setDNS(
                servers.compactMap { $0 as? String },
                snapshotPath: dnsSnapshot
            )
            reply(HelperReply.transactionOK("系统 DNS 已由 Helper 设置", steps: steps, rollbackSuggestion: "如 DNS 异常，请在诊断页执行恢复 DNS。"))
        } catch {
            reply(HelperReply.error(error, steps: steps, rollbackSuggestion: "DNS 写入失败。请检查 DNS 服务器设置，或执行恢复 DNS。"))
        }
    }

    func restoreSystemDNS(
        dnsSnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        let steps = ["读取系统 DNS 快照", "恢复各网络服务 DNS 并移除快照"]
        do {
            let dnsSnapshot = try validatedDNSSnapshotPath(dnsSnapshotPath as String)
            let count = try networkTool.restoreDNS(snapshotPath: dnsSnapshot)
            reply(HelperReply.transactionOK("已恢复 \(count) 个网络服务的系统 DNS", steps: steps, rollbackSuggestion: "如无快照可恢复，返回 0 属于正常结果。"))
        } catch {
            reply(HelperReply.error(error, steps: steps, rollbackSuggestion: "DNS 恢复失败。请检查网络服务是否被删除或重命名。"))
        }
    }

    func captureTunSnapshot(
        proxySnapshotPath: NSString,
        tunSnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        var steps: [String] = []
        do {
            _ = try validatedProxySnapshotPath(proxySnapshotPath as String)
            let tunSnapshot = try validatedTunSnapshotPath(tunSnapshotPath as String)
            steps.append("捕获当前 DNS、IPv4/IPv6 路由和默认路由")
            let snapshot = try tunTool.capture(
                tunSnapshotPath: tunSnapshot
            )
            reply(HelperReply.transactionOK("已捕获 TUN 回滚快照", steps: steps, rollbackSuggestion: "如 TUN 启动失败，可在诊断页执行恢复 TUN 路由。", payload: [
                "createdAt": snapshot.createdAt.description,
                "ipv4Routes": snapshot.ipv4Routes.count,
                "ipv6Routes": snapshot.ipv6Routes.count
            ]))
        } catch {
            reply(HelperReply.error(error, steps: steps, rollbackSuggestion: "TUN 快照捕获失败。建议先验证 Helper 权限后重试。"))
        }
    }

    func restoreTunSnapshot(
        proxySnapshotPath: NSString,
        tunSnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        var steps: [String] = []
        do {
            _ = try validatedProxySnapshotPath(proxySnapshotPath as String)
            let tunSnapshot = try validatedTunSnapshotPath(tunSnapshotPath as String)
            steps.append("读取 TUN 回滚快照")
            steps.append("恢复 DNS，删除新增 utun 路由，必要时恢复默认路由")
            let detail = try tunTool.restore(
                tunSnapshotPath: tunSnapshot
            )
            reply(HelperReply.transactionOK(detail, steps: steps, rollbackSuggestion: "如果路由仍异常，请关闭核心并重新运行诊断。"))
        } catch {
            reply(HelperReply.error(error, steps: steps, rollbackSuggestion: "TUN 回滚失败。请检查 Helper 权限，必要时重启网络服务。"))
        }
    }

    func verifyPrivileges(withReply reply: @escaping (NSDictionary) -> Void) {
        if geteuid() == 0 {
            reply(HelperReply.ok("Helper 正以 root 权限运行", payload: ["effectiveUID": 0]))
        } else {
            reply(HelperReply.error("Helper 未以 root 权限运行，当前 euid=\(geteuid())"))
        }
    }

    private func validatedCorePaths(
        mihomoPath: String,
        configPath: String,
        workDirectory: String,
        logPath: String?
    ) throws -> HelperCorePathSet {
        try HelperPathPolicy.validateCorePaths(
            mihomoPath: mihomoPath,
            configPath: configPath,
            workDirectory: workDirectory,
            logPath: logPath,
            appBundleURL: appBundleURL,
            userHomeDirectory: userHomeDirectory
        )
    }

    private func validatedProxySnapshotPath(_ path: String) throws -> String {
        try HelperPathPolicy.validateProxySnapshotPath(path, userHomeDirectory: userHomeDirectory)
    }

    private func validatedDNSSnapshotPath(_ path: String) throws -> String {
        try HelperPathPolicy.validateDNSSnapshotPath(path, userHomeDirectory: userHomeDirectory)
    }

    private func validatedTunSnapshotPath(_ path: String) throws -> String {
        try HelperPathPolicy.validateTunSnapshotPath(path, userHomeDirectory: userHomeDirectory)
    }

    private func requiredLogPath(_ paths: HelperCorePathSet) throws -> String {
        guard let logPath = paths.logPath else {
            throw HelperPathPolicyError("logPath 不能为空")
        }
        return logPath
    }
}
