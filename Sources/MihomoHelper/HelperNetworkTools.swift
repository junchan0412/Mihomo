import Foundation

struct HelperProxyEndpointState: Codable, Hashable {
    var enabled: Bool
    var server: String
    var port: Int
}

struct HelperNetworkServiceProxyState: Codable, Hashable {
    var service: String
    var web: HelperProxyEndpointState
    var secureWeb: HelperProxyEndpointState
    var socks: HelperProxyEndpointState
    var bypassDomains: [String]
    var dnsServers: [String]
}

struct HelperSystemProxySnapshot: Codable, Hashable {
    var createdAt: Date
    var services: [HelperNetworkServiceProxyState]
}

final class HelperSystemNetworkTool {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func networkServices() -> [String] {
        guard let result = try? HelperShell.run("/usr/sbin/networksetup", ["-listallnetworkservices"]),
              result.status == 0
        else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map(String.init)
            .dropFirst()
            .filter { !$0.hasPrefix("*") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func enableProxy(host: String, mixedPort: Int, socksPort: Int, snapshotPath: String) throws {
        if loadSnapshot(snapshotPath: snapshotPath) == nil {
            try saveSnapshot(captureSnapshot(), snapshotPath: snapshotPath)
        }
        for service in networkServices() {
            try runNetworkSetup(["-setwebproxy", service, host, "\(mixedPort)"])
            try runNetworkSetup(["-setsecurewebproxy", service, host, "\(mixedPort)"])
            if socksPort > 0 {
                try runNetworkSetup(["-setsocksfirewallproxy", service, host, "\(socksPort)"])
            }
            try runNetworkSetup(["-setproxybypassdomains", service, "localhost", "127.0.0.1", "*.local"])
        }
    }

    func setDNS(_ servers: [String], snapshotPath: String) throws {
        let cleaned = servers.map(\.nonEmptyTrimmed).filter { !$0.isEmpty }
        guard cleaned.isEmpty == false else { return }
        if loadSnapshot(snapshotPath: snapshotPath) == nil {
            try saveSnapshot(captureSnapshot(), snapshotPath: snapshotPath)
        }
        for service in networkServices() {
            try runNetworkSetup(["-setdnsservers", service] + cleaned)
        }
    }

    func restore(snapshotPath: String) throws -> Int {
        guard let snapshot = loadSnapshot(snapshotPath: snapshotPath) else {
            try disableWithoutSnapshot()
            return 0
        }
        for serviceState in snapshot.services {
            try restoreEndpoint(service: serviceState.service, kind: "web", state: serviceState.web)
            try restoreEndpoint(service: serviceState.service, kind: "secureWeb", state: serviceState.secureWeb)
            try restoreEndpoint(service: serviceState.service, kind: "socks", state: serviceState.socks)

            if serviceState.bypassDomains.isEmpty {
                try runNetworkSetup(["-setproxybypassdomains", serviceState.service, "Empty"])
            } else {
                try runNetworkSetup(["-setproxybypassdomains", serviceState.service] + serviceState.bypassDomains)
            }

            if serviceState.dnsServers.isEmpty {
                try runNetworkSetup(["-setdnsservers", serviceState.service, "Empty"])
            } else {
                try runNetworkSetup(["-setdnsservers", serviceState.service] + serviceState.dnsServers)
            }
        }
        try removeSnapshot(snapshotPath: snapshotPath)
        return snapshot.services.count
    }

    func restoreDNS(snapshotPath: String) throws -> Int {
        guard let snapshot = loadSnapshot(snapshotPath: snapshotPath) else { return 0 }
        let count = try restoreDNS(from: snapshot)
        try removeSnapshot(snapshotPath: snapshotPath)
        return count
    }

    func restoreDNS(from snapshot: HelperSystemProxySnapshot) throws -> Int {
        for serviceState in snapshot.services {
            if serviceState.dnsServers.isEmpty {
                try runNetworkSetup(["-setdnsservers", serviceState.service, "Empty"])
            } else {
                try runNetworkSetup(["-setdnsservers", serviceState.service] + serviceState.dnsServers)
            }
        }
        return snapshot.services.count
    }

    func captureSnapshot() throws -> HelperSystemProxySnapshot {
        let services = networkServices().map { service in
            HelperNetworkServiceProxyState(
                service: service,
                web: endpointState(command: "-getwebproxy", service: service),
                secureWeb: endpointState(command: "-getsecurewebproxy", service: service),
                socks: endpointState(command: "-getsocksfirewallproxy", service: service),
                bypassDomains: bypassDomains(service: service),
                dnsServers: dnsServers(service: service)
            )
        }
        return HelperSystemProxySnapshot(createdAt: Date(), services: services)
    }

    func saveSnapshot(_ snapshot: HelperSystemProxySnapshot, snapshotPath: String) throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: snapshotPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: URL(fileURLWithPath: snapshotPath), options: .atomic)
    }

    func loadSnapshot(snapshotPath: String) -> HelperSystemProxySnapshot? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: snapshotPath)) else { return nil }
        return try? decoder.decode(HelperSystemProxySnapshot.self, from: data)
    }

    private func disableWithoutSnapshot() throws {
        for service in networkServices() {
            try runNetworkSetup(["-setwebproxystate", service, "off"])
            try runNetworkSetup(["-setsecurewebproxystate", service, "off"])
            try runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
        }
    }

    private func restoreEndpoint(service: String, kind: String, state: HelperProxyEndpointState) throws {
        let proxyCommand: String
        let stateCommand: String
        switch kind {
        case "web":
            proxyCommand = "-setwebproxy"
            stateCommand = "-setwebproxystate"
        case "secureWeb":
            proxyCommand = "-setsecurewebproxy"
            stateCommand = "-setsecurewebproxystate"
        default:
            proxyCommand = "-setsocksfirewallproxy"
            stateCommand = "-setsocksfirewallproxystate"
        }

        if state.server.isEmpty == false, state.port > 0 {
            try runNetworkSetup([proxyCommand, service, state.server, "\(state.port)"])
        }
        try runNetworkSetup([stateCommand, service, state.enabled ? "on" : "off"])
    }

    private func removeSnapshot(snapshotPath: String) throws {
        let url = URL(fileURLWithPath: snapshotPath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func endpointState(command: String, service: String) -> HelperProxyEndpointState {
        guard let result = try? HelperShell.run("/usr/sbin/networksetup", [command, service]), result.status == 0 else {
            return HelperProxyEndpointState(enabled: false, server: "", port: 0)
        }
        let lines = result.stdout.split(separator: "\n").map(String.init)
        return HelperProxyEndpointState(
            enabled: value(after: "Enabled:", in: lines).lowercased().hasPrefix("yes"),
            server: value(after: "Server:", in: lines),
            port: Int(value(after: "Port:", in: lines)) ?? 0
        )
    }

    private func bypassDomains(service: String) -> [String] {
        guard let result = try? HelperShell.run("/usr/sbin/networksetup", ["-getproxybypassdomains", service]),
              result.status == 0
        else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("There aren't any") }
    }

    private func dnsServers(service: String) -> [String] {
        guard let result = try? HelperShell.run("/usr/sbin/networksetup", ["-getdnsservers", service]),
              result.status == 0
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

    private func runNetworkSetup(_ arguments: [String]) throws {
        let result = try HelperShell.run("/usr/sbin/networksetup", arguments)
        guard result.status == 0 else {
            throw NSError(domain: "MihomoHelper.Network", code: Int(result.status), userInfo: [
                NSLocalizedDescriptionKey: HelperShell.output(result)
            ])
        }
    }
}
