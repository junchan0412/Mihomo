import Foundation
import MihomoShared

final class HelperService: NSObject, MihomoHelperXPCProtocol {
    private let networkTool = HelperSystemNetworkTool()
    private lazy var tunTool = HelperTunRecoveryTool(networkTool: networkTool)
    private let coreRuntime = HelperCoreRuntime()
    private let coreLaunchDaemonTool = HelperCoreLaunchDaemonTool()

    func helperVersion(withReply reply: @escaping (NSDictionary) -> Void) {
        reply(HelperReply.ok("MihomoHelper 0.6.0", payload: [
            "machService": MihomoHelperConstants.machServiceName,
            "effectiveUID": Int(geteuid())
        ]))
    }

    func validateConfig(
        mihomoPath: NSString,
        configPath: NSString,
        workDirectory: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        do {
            let output = try coreRuntime.validate(
                mihomoPath: mihomoPath as String,
                configPath: configPath as String,
                workDirectory: workDirectory as String
            )
            reply(HelperReply.ok(output.isEmpty ? "mihomo 配置校验通过" : output, payload: ["validation": output]))
        } catch {
            reply(HelperReply.error(error))
        }
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
        do {
            if autoSetDNS {
                try networkTool.setDNS(
                    dnsServers.compactMap { $0 as? String },
                    snapshotPath: dnsSnapshotPath as String
                )
            }

            var tunDetail = ""
            if captureTun {
                let snapshot = try tunTool.capture(
                    tunSnapshotPath: tunSnapshotPath as String
                )
                tunDetail = "已捕获 TUN 回滚快照：\(snapshot.createdAt)"
            }

            let validation = try coreRuntime.start(
                mihomoPath: mihomoPath as String,
                configPath: configPath as String,
                workDirectory: workDirectory as String,
                logPath: logPath as String
            )
            reply(HelperReply.ok("核心已由 Helper 启动", payload: [
                "validation": validation,
                "tunDetail": tunDetail
            ]))
        } catch {
            reply(HelperReply.error(error))
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
        do {
            coreRuntime.stop()
            var details: [String] = []
            if restoreTun {
                details.append(try tunTool.restore(
                    tunSnapshotPath: tunSnapshotPath as String
                ))
            } else if restoreDNS {
                let restored = try networkTool.restoreDNS(snapshotPath: dnsSnapshotPath as String)
                details.append("已恢复 \(restored) 个网络服务的系统 DNS 快照")
            }
            reply(HelperReply.ok(details.isEmpty ? "核心已由 Helper 停止" : details.joined(separator: "\n")))
        } catch {
            reply(HelperReply.error(error))
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
            _ = try coreRuntime.validate(
                mihomoPath: corePath as String,
                configPath: configPath as String,
                workDirectory: workDirectory as String
            )
            let path = try coreLaunchDaemonTool.install(
                corePath: corePath as String,
                configPath: configPath as String,
                workDirectory: workDirectory as String,
                logPath: logPath as String
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
        do {
            try networkTool.enableProxy(
                host: host as String,
                mixedPort: Int(mixedPort),
                socksPort: Int(socksPort),
                snapshotPath: proxySnapshotPath as String
            )
            reply(HelperReply.ok("系统代理已由 Helper 设置"))
        } catch {
            reply(HelperReply.error(error))
        }
    }

    func restoreSystemProxy(
        proxySnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        do {
            let count = try networkTool.restore(snapshotPath: proxySnapshotPath as String)
            reply(HelperReply.ok("已恢复 \(count) 个网络服务的系统代理/DNS"))
        } catch {
            reply(HelperReply.error(error))
        }
    }

    func setSystemDNS(
        servers: NSArray,
        dnsSnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        do {
            try networkTool.setDNS(
                servers.compactMap { $0 as? String },
                snapshotPath: dnsSnapshotPath as String
            )
            reply(HelperReply.ok("系统 DNS 已由 Helper 设置"))
        } catch {
            reply(HelperReply.error(error))
        }
    }

    func captureTunSnapshot(
        proxySnapshotPath: NSString,
        tunSnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        do {
            let snapshot = try tunTool.capture(
                tunSnapshotPath: tunSnapshotPath as String
            )
            reply(HelperReply.ok("已捕获 TUN 回滚快照", payload: [
                "createdAt": snapshot.createdAt.description,
                "ipv4Routes": snapshot.ipv4Routes.count,
                "ipv6Routes": snapshot.ipv6Routes.count
            ]))
        } catch {
            reply(HelperReply.error(error))
        }
    }

    func restoreTunSnapshot(
        proxySnapshotPath: NSString,
        tunSnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        do {
            let detail = try tunTool.restore(
                tunSnapshotPath: tunSnapshotPath as String
            )
            reply(HelperReply.ok(detail))
        } catch {
            reply(HelperReply.error(error))
        }
    }

    func verifyPrivileges(withReply reply: @escaping (NSDictionary) -> Void) {
        if geteuid() == 0 {
            reply(HelperReply.ok("Helper 正以 root 权限运行", payload: ["effectiveUID": 0]))
        } else {
            reply(HelperReply.error("Helper 未以 root 权限运行，当前 euid=\(geteuid())"))
        }
    }
}
