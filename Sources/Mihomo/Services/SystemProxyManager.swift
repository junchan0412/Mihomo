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

final class SystemProxyManager {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func networkServices() -> [String] {
        guard let result = try? Shell.run("/usr/sbin/networksetup", ["-listallnetworkservices"]),
              result.status == 0
        else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map(String.init)
            .dropFirst()
            .filter { !$0.hasPrefix("*") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func enable(host: String, port: Int, socksPort: Int) throws {
        if loadSnapshot() == nil {
            try saveSnapshot(captureSnapshot())
        }

        for service in networkServices() {
            try run(["-setwebproxy", service, host, "\(port)"])
            try run(["-setsecurewebproxy", service, host, "\(port)"])
            if socksPort > 0 {
                try run(["-setsocksfirewallproxy", service, host, "\(socksPort)"])
            }
            try run(["-setproxybypassdomains", service, "localhost", "127.0.0.1", "*.local"])
        }
    }

    func disable() throws {
        if let snapshot = loadSnapshot() {
            try restore(snapshot)
            try removeSnapshot()
            return
        }

        for service in networkServices() {
            try run(["-setwebproxystate", service, "off"])
            try run(["-setsecurewebproxystate", service, "off"])
            try run(["-setsocksfirewallproxystate", service, "off"])
        }
    }

    func repairFromSnapshot() throws {
        guard let snapshot = loadSnapshot() else {
            try disable()
            return
        }
        try restore(snapshot)
        try removeSnapshot()
    }

    func loadSnapshot() -> SystemProxySnapshot? {
        guard let data = try? Data(contentsOf: AppPaths.systemProxySnapshotFile) else { return nil }
        return try? decoder.decode(SystemProxySnapshot.self, from: data)
    }

    func captureSnapshot() throws -> SystemProxySnapshot {
        let services = networkServices().map { service in
            NetworkServiceProxyState(
                service: service,
                web: endpointState(command: "-getwebproxy", service: service),
                secureWeb: endpointState(command: "-getsecurewebproxy", service: service),
                socks: endpointState(command: "-getsocksfirewallproxy", service: service),
                bypassDomains: bypassDomains(service: service),
                dnsServers: dnsServers(service: service)
            )
        }
        return SystemProxySnapshot(createdAt: Date(), services: services)
    }

    private func restore(_ snapshot: SystemProxySnapshot) throws {
        for serviceState in snapshot.services {
            try restoreEndpoint(service: serviceState.service, kind: "web", state: serviceState.web)
            try restoreEndpoint(service: serviceState.service, kind: "secureWeb", state: serviceState.secureWeb)
            try restoreEndpoint(service: serviceState.service, kind: "socks", state: serviceState.socks)

            if serviceState.bypassDomains.isEmpty {
                try run(["-setproxybypassdomains", serviceState.service, "Empty"])
            } else {
                try run(["-setproxybypassdomains", serviceState.service] + serviceState.bypassDomains)
            }

            if serviceState.dnsServers.isEmpty {
                try run(["-setdnsservers", serviceState.service, "Empty"])
            } else {
                try run(["-setdnsservers", serviceState.service] + serviceState.dnsServers)
            }
        }
    }

    private func restoreEndpoint(service: String, kind: String, state: ProxyEndpointState) throws {
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
            try run([proxyCommand, service, state.server, "\(state.port)"])
        }
        try run([stateCommand, service, state.enabled ? "on" : "off"])
    }

    private func saveSnapshot(_ snapshot: SystemProxySnapshot) throws {
        try AppPaths.ensureBaseDirectories()
        let data = try encoder.encode(snapshot)
        try data.write(to: AppPaths.systemProxySnapshotFile, options: .atomic)
    }

    private func removeSnapshot() throws {
        if FileManager.default.fileExists(atPath: AppPaths.systemProxySnapshotFile.path) {
            try FileManager.default.removeItem(at: AppPaths.systemProxySnapshotFile)
        }
    }

    private func endpointState(command: String, service: String) -> ProxyEndpointState {
        guard let result = try? Shell.run("/usr/sbin/networksetup", [command, service]), result.status == 0 else {
            return ProxyEndpointState(enabled: false, server: "", port: 0)
        }
        let lines = result.stdout.split(separator: "\n").map(String.init)
        let enabled = value(after: "Enabled:", in: lines).lowercased().hasPrefix("yes")
        let server = value(after: "Server:", in: lines)
        let port = Int(value(after: "Port:", in: lines)) ?? 0
        return ProxyEndpointState(enabled: enabled, server: server, port: port)
    }

    private func bypassDomains(service: String) -> [String] {
        guard let result = try? Shell.run("/usr/sbin/networksetup", ["-getproxybypassdomains", service]),
              result.status == 0
        else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("There aren't any") }
    }

    private func dnsServers(service: String) -> [String] {
        guard let result = try? Shell.run("/usr/sbin/networksetup", ["-getdnsservers", service]),
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

    private func run(_ arguments: [String]) throws {
        let result = try Shell.run("/usr/sbin/networksetup", arguments)
        guard result.status == 0 else {
            throw NSError(domain: "SystemProxy", code: Int(result.status), userInfo: [
                NSLocalizedDescriptionKey: result.stderr.isEmpty ? result.stdout : result.stderr
            ])
        }
    }
}
