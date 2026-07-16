import Foundation
import MihomoShared
import ServiceManagement

struct HelperOperationResult: Hashable {
    var message: String
    var payload: [String: String]

    init(dictionary: NSDictionary) throws {
        let ok = dictionary["ok"] as? Bool ?? false
        message = dictionary["message"] as? String ?? ""
        var values: [String: String] = [:]
        for (key, value) in dictionary {
            guard let key = key as? String, key != "ok", key != "message" else { continue }
            values[key] = "\(value)"
        }
        payload = values
        if ok == false {
            throw NSError(domain: "MihomoHelperClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: message.isEmpty ? "Helper 操作失败" : message
            ])
        }
    }
}

final class HelperServiceManager {
    private let service = SMAppService.daemon(plistName: MihomoHelperConstants.daemonPlistName)

    var statusDescription: String {
        switch service.status {
        case .enabled:
            return "Helper 已注册"
        case .notRegistered:
            return "Helper 未注册"
        case .notFound:
            return "Helper plist 未打入 App Bundle"
        case .requiresApproval:
            return "Helper 等待系统设置中批准"
        @unknown default:
            return "Helper 状态未知"
        }
    }

    var requiresApproval: Bool {
        service.status == .requiresApproval
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

final class MihomoHelperClient {
    func version() async throws -> HelperOperationResult {
        try await call(timeoutSeconds: 2) { proxy, reply in
            proxy.helperVersion(withReply: reply)
        }
    }

    func validateConfig(mihomoPath: String, configPath: URL, workDirectory: URL) async throws -> HelperOperationResult {
        try await call(timeoutSeconds: 30) { proxy, reply in
            proxy.validateConfig(
                mihomoPath: mihomoPath as NSString,
                configPath: configPath.path as NSString,
                workDirectory: workDirectory.path as NSString,
                withReply: reply
            )
        }
    }

    func prepareAndStartCore(
        mihomoPath: String,
        configPath: URL,
        workDirectory: URL,
        logPath: URL,
        autoSetDNS: Bool,
        dnsServers: [String],
        captureTun: Bool
    ) async throws -> HelperOperationResult {
        try await call(timeoutSeconds: 30) { proxy, reply in
            proxy.prepareAndStartCore(
                mihomoPath: mihomoPath as NSString,
                configPath: configPath.path as NSString,
                workDirectory: workDirectory.path as NSString,
                logPath: logPath.path as NSString,
                proxySnapshotPath: AppPaths.systemProxySnapshotFile.path as NSString,
                dnsSnapshotPath: AppPaths.systemDNSSnapshotFile.path as NSString,
                tunSnapshotPath: AppPaths.tunRecoverySnapshotFile.path as NSString,
                autoSetDNS: autoSetDNS,
                dnsServers: dnsServers as NSArray,
                captureTun: captureTun,
                withReply: reply
            )
        }
    }

    func stopCore(restoreDNS: Bool, restoreTun: Bool) async throws -> HelperOperationResult {
        try await call { proxy, reply in
            proxy.stopCore(
                restoreDNS: restoreDNS,
                restoreTun: restoreTun,
                proxySnapshotPath: AppPaths.systemProxySnapshotFile.path as NSString,
                dnsSnapshotPath: AppPaths.systemDNSSnapshotFile.path as NSString,
                tunSnapshotPath: AppPaths.tunRecoverySnapshotFile.path as NSString,
                withReply: reply
            )
        }
    }

    func installCoreLaunchDaemon(corePath: String, configPath: URL, workDirectory: URL, logPath: URL) async throws -> HelperOperationResult {
        try await call { proxy, reply in
            proxy.installCoreLaunchDaemon(
                corePath: corePath as NSString,
                configPath: configPath.path as NSString,
                workDirectory: workDirectory.path as NSString,
                logPath: logPath.path as NSString,
                withReply: reply
            )
        }
    }

    func uninstallCoreLaunchDaemon() async throws -> HelperOperationResult {
        try await call { proxy, reply in
            proxy.uninstallCoreLaunchDaemon(withReply: reply)
        }
    }

    func startCoreLaunchDaemon() async throws -> HelperOperationResult {
        try await call { proxy, reply in
            proxy.startCoreLaunchDaemon(withReply: reply)
        }
    }

    func stopCoreLaunchDaemon() async throws -> HelperOperationResult {
        try await call { proxy, reply in
            proxy.stopCoreLaunchDaemon(withReply: reply)
        }
    }

    func setSystemProxy(host: String, mixedPort: Int, socksPort: Int) async throws -> HelperOperationResult {
        try await call { proxy, reply in
            proxy.setSystemProxy(
                host: host as NSString,
                mixedPort: Int32(mixedPort),
                socksPort: Int32(socksPort),
                proxySnapshotPath: AppPaths.systemProxySnapshotFile.path as NSString,
                withReply: reply
            )
        }
    }

    func restoreSystemProxy() async throws -> HelperOperationResult {
        try await call { proxy, reply in
            proxy.restoreSystemProxy(
                proxySnapshotPath: AppPaths.systemProxySnapshotFile.path as NSString,
                withReply: reply
            )
        }
    }

    func setSystemDNS(_ servers: [String]) async throws -> HelperOperationResult {
        try await call { proxy, reply in
            proxy.setSystemDNS(
                servers: servers as NSArray,
                dnsSnapshotPath: AppPaths.systemDNSSnapshotFile.path as NSString,
                withReply: reply
            )
        }
    }

    func restoreSystemDNS() async throws -> HelperOperationResult {
        try await call { proxy, reply in
            proxy.restoreSystemDNS(
                dnsSnapshotPath: AppPaths.systemDNSSnapshotFile.path as NSString,
                withReply: reply
            )
        }
    }

    func captureTunSnapshot() async throws -> HelperOperationResult {
        try await call { proxy, reply in
            proxy.captureTunSnapshot(
                proxySnapshotPath: AppPaths.systemProxySnapshotFile.path as NSString,
                tunSnapshotPath: AppPaths.tunRecoverySnapshotFile.path as NSString,
                withReply: reply
            )
        }
    }

    func restoreTunSnapshot() async throws -> HelperOperationResult {
        try await call { proxy, reply in
            proxy.restoreTunSnapshot(
                proxySnapshotPath: AppPaths.systemProxySnapshotFile.path as NSString,
                tunSnapshotPath: AppPaths.tunRecoverySnapshotFile.path as NSString,
                withReply: reply
            )
        }
    }

    func verifyPrivileges() async throws -> HelperOperationResult {
        try await call { proxy, reply in
            proxy.verifyPrivileges(withReply: reply)
        }
    }

    private func call(
        timeoutSeconds: TimeInterval = 10,
        _ invoke: @escaping (MihomoHelperXPCProtocol, @escaping (NSDictionary) -> Void) -> Void
    ) async throws -> HelperOperationResult {
        try await withCheckedThrowingContinuation { continuation in
            let completion = HelperCallCompletion()
            let connection = NSXPCConnection(
                machServiceName: MihomoHelperConstants.machServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(with: MihomoHelperXPCProtocol.self)
            let finish: (Result<HelperOperationResult, Error>) -> Void = { result in
                guard completion.claim() else { return }
                connection.invalidate()
                continuation.resume(with: result)
            }
            connection.invalidationHandler = {
                finish(.failure(HelperCallError.connectionInvalidated))
            }
            connection.interruptionHandler = {
                finish(.failure(HelperCallError.connectionInterrupted))
            }
            connection.resume()

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeoutSeconds) {
                finish(.failure(HelperCallError.timeout(seconds: timeoutSeconds)))
            }

            let remote = connection.remoteObjectProxyWithErrorHandler { error in
                finish(.failure(error))
            } as? MihomoHelperXPCProtocol

            guard let remote else {
                finish(.failure(NSError(domain: "MihomoHelperClient", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "无法连接 XPC Helper，请先在高级页注册 Helper。"
                ])))
                return
            }

            invoke(remote) { dictionary in
                do {
                    finish(.success(try HelperOperationResult(dictionary: dictionary)))
                } catch {
                    finish(.failure(error))
                }
            }
        }
    }
}

final class HelperCallCompletion {
    private let lock = NSLock()
    private var finished = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard finished == false else { return false }
        finished = true
        return true
    }
}

enum HelperCallError: LocalizedError {
    case timeout(seconds: TimeInterval)
    case connectionInvalidated
    case connectionInterrupted

    var errorDescription: String? {
        switch self {
        case .timeout(let seconds):
            return "XPC Helper 在 \(Int(seconds)) 秒内没有响应，请在高级工具中重新注册 Helper。"
        case .connectionInvalidated:
            return "XPC Helper 连接已失效，请重新注册 Helper。"
        case .connectionInterrupted:
            return "XPC Helper 连接被中断，请稍后重试或重新注册 Helper。"
        }
    }
}
