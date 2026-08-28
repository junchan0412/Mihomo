import Foundation

struct ProxyEndpointState: Codable, Hashable {
    var enabled: Bool
    var server: String
    var port: Int
}

struct NetworkServiceProxyState: Codable, Hashable {
    var service: String
    var web: ProxyEndpointState
    var secureWeb: ProxyEndpointState
    var socks: ProxyEndpointState
    var bypassDomains: [String]
    var dnsServers: [String]
}

struct SystemProxySnapshot: Codable, Hashable {
    var createdAt: Date
    var services: [NetworkServiceProxyState]
}

struct SystemProxyMatchReport: Equatable {
    var totalServices: Int
    var matchedServices: Int

    var isFullyMatched: Bool { totalServices > 0 && totalServices == matchedServices }
}

extension SystemProxyManager {
    static func matchReport(snapshot: SystemProxySnapshot, mixedPort: Int, socksPort: Int) -> SystemProxyMatchReport {
        let matched = snapshot.services.filter { service in
            let webMatches = service.web.enabled && service.web.server == "127.0.0.1" && service.web.port == mixedPort
            let secureMatches = service.secureWeb.enabled && service.secureWeb.server == "127.0.0.1" && service.secureWeb.port == mixedPort
            let socksMatches = socksPort > 0 && service.socks.enabled && service.socks.server == "127.0.0.1" && service.socks.port == socksPort
            return webMatches && secureMatches && (socksPort <= 0 || socksMatches)
        }.count
        return SystemProxyMatchReport(totalServices: snapshot.services.count, matchedServices: matched)
    }
}

final class SystemProxyManager {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func networkServices() -> [String] {
        guard let result = try? Shell.run(
            "/usr/sbin/networksetup",
            ["-listallnetworkservices"],
            forcesPOSIXLocale: true
        ), result.status == 0
        else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map(String.init)
            .dropFirst()
            .filter { !$0.hasPrefix("*") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func enable(host: String, port: Int, socksPort: Int) throws {
        throw helperOnlyError()
    }

    func setDNSServers(_ servers: [String]) throws {
        throw helperOnlyError()
    }

    func disable() throws {
        throw helperOnlyError()
    }

    func repairFromSnapshot() throws {
        throw helperOnlyError()
    }

    func loadSnapshot() -> SystemProxySnapshot? {
        loadSnapshot(at: AppPaths.systemProxySnapshotFile)
    }

    func loadDNSSnapshot() -> SystemProxySnapshot? {
        loadSnapshot(at: AppPaths.systemDNSSnapshotFile)
    }

    func loadSnapshot(at url: URL) -> SystemProxySnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(SystemProxySnapshot.self, from: data)
    }

    func removeSnapshot(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func captureSnapshot() throws -> SystemProxySnapshot {
        let names = networkServices()
        guard names.isEmpty == false else {
            return SystemProxySnapshot(createdAt: Date(), services: [])
        }

        // Each service needs five independent `networksetup` probes. Run services in parallel:
        // serially this is 5x(service count) process spawns — 40+ and one to two seconds on a
        // typical Mac — and it runs on every takeover refresh and proxy-guard reconciliation.
        let lock = NSLock()
        var captured: [Int: NetworkServiceProxyState] = [:]
        DispatchQueue.concurrentPerform(iterations: names.count) { index in
            let service = names[index]
            let state = NetworkServiceProxyState(
                service: service,
                web: endpointState(command: "-getwebproxy", service: service),
                secureWeb: endpointState(command: "-getsecurewebproxy", service: service),
                socks: endpointState(command: "-getsocksfirewallproxy", service: service),
                bypassDomains: bypassDomains(service: service),
                dnsServers: dnsServers(service: service)
            )
            lock.lock()
            captured[index] = state
            lock.unlock()
        }

        return SystemProxySnapshot(
            createdAt: Date(),
            services: names.indices.compactMap { captured[$0] }
        )
    }

    func restore(_ snapshot: SystemProxySnapshot) throws {
        throw helperOnlyError()
    }

    // `networksetup` localises its output, so every parser below pins LC_ALL=C. Without it the
    // "Enabled:"/"Server:"/"There aren't any" labels never match on a non-English system and the
    // app silently reports "no proxy configured".
    private func endpointState(command: String, service: String) -> ProxyEndpointState {
        guard let result = try? Shell.run(
            "/usr/sbin/networksetup",
            [command, service],
            forcesPOSIXLocale: true
        ), result.status == 0 else {
            return ProxyEndpointState(enabled: false, server: "", port: 0)
        }
        let lines = result.stdout.split(separator: "\n").map(String.init)
        let enabled = value(after: "Enabled:", in: lines).lowercased().hasPrefix("yes")
        let server = value(after: "Server:", in: lines)
        let port = Int(value(after: "Port:", in: lines)) ?? 0
        return ProxyEndpointState(enabled: enabled, server: server, port: port)
    }

    private func bypassDomains(service: String) -> [String] {
        guard let result = try? Shell.run(
            "/usr/sbin/networksetup",
            ["-getproxybypassdomains", service],
            forcesPOSIXLocale: true
        ), result.status == 0
        else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("There aren't any") }
    }

    private func dnsServers(service: String) -> [String] {
        guard let result = try? Shell.run(
            "/usr/sbin/networksetup",
            ["-getdnsservers", service],
            forcesPOSIXLocale: true
        ), result.status == 0
        else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("There aren't any") }
    }

    private func value(after prefix: String, in lines: [String]) -> String {
        guard let line = lines.first(where: { $0.hasPrefix(prefix) }) else { return "" }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func helperOnlyError() -> NSError {
        NSError(domain: "SystemProxy", code: 9, userInfo: [
            NSLocalizedDescriptionKey: "系统代理/DNS 写入操作已迁移到 XPC Helper"
        ])
    }
}
