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

struct HelperRouteEntry: Codable, Hashable {
    var destination: String
    var gateway: String
    var flags: String
    var interface: String
}

struct HelperDefaultRouteState: Codable, Hashable {
    var gateway: String
    var interface: String
    var raw: String
}

struct HelperTunRecoverySnapshot: Codable, Hashable {
    var createdAt: Date
    var proxySnapshot: HelperSystemProxySnapshot
    var ipv4Routes: [HelperRouteEntry]
    var ipv6Routes: [HelperRouteEntry]
    var defaultIPv4Route: HelperDefaultRouteState?
}

final class HelperTunRecoveryTool {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let networkTool: HelperSystemNetworkTool

    init(networkTool: HelperSystemNetworkTool) {
        self.networkTool = networkTool
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func capture(tunSnapshotPath: String) throws -> HelperTunRecoverySnapshot {
        let proxySnapshot = try networkTool.captureSnapshot()
        let snapshot = HelperTunRecoverySnapshot(
            createdAt: Date(),
            proxySnapshot: proxySnapshot,
            ipv4Routes: routes(family: "inet"),
            ipv6Routes: routes(family: "inet6"),
            defaultIPv4Route: defaultRoute()
        )
        try save(snapshot, tunSnapshotPath: tunSnapshotPath)
        return snapshot
    }

    func restore(tunSnapshotPath: String) throws -> String {
        guard let snapshot = load(tunSnapshotPath: tunSnapshotPath) else {
            throw NSError(domain: "MihomoHelper.TUN", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "没有可用的 TUN 回滚快照"
            ])
        }

        let restoredServices = try networkTool.restoreDNS(from: snapshot.proxySnapshot)
        let addedRoutes = rollbackCandidates(
            current: routes(family: "inet") + routes(family: "inet6"),
            baseline: snapshot.ipv4Routes + snapshot.ipv6Routes
        )
        for route in addedRoutes {
            _ = try? HelperShell.run("/sbin/route", ["-n", "delete", route.destination])
        }

        let shouldRestoreDefault = shouldRestoreDefaultRoute(current: defaultRoute(), snapshot: snapshot.defaultIPv4Route)
        if shouldRestoreDefault, let gateway = snapshot.defaultIPv4Route?.gateway, gateway.isEmpty == false {
            _ = try? HelperShell.run("/sbin/route", ["-n", "delete", "default"])
            _ = try HelperShell.run("/sbin/route", ["-n", "add", "default", gateway])
        }

        _ = try? HelperShell.run("/usr/bin/dscacheutil", ["-flushcache"])
        try remove(tunSnapshotPath: tunSnapshotPath)
        return "已恢复 \(restoredServices) 个网络服务的 DNS，删除 \(addedRoutes.count) 条 TUN 新增路由\(shouldRestoreDefault ? "，并恢复默认路由" : "")。"
    }

    private func save(_ snapshot: HelperTunRecoverySnapshot, tunSnapshotPath: String) throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: tunSnapshotPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(snapshot).write(to: URL(fileURLWithPath: tunSnapshotPath), options: .atomic)
    }

    private func load(tunSnapshotPath: String) -> HelperTunRecoverySnapshot? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: tunSnapshotPath)) else { return nil }
        return try? decoder.decode(HelperTunRecoverySnapshot.self, from: data)
    }

    private func remove(tunSnapshotPath: String) throws {
        let url = URL(fileURLWithPath: tunSnapshotPath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func routes(family: String) -> [HelperRouteEntry] {
        guard let result = try? HelperShell.run("/usr/sbin/netstat", ["-rn", "-f", family]),
              result.status == 0
        else { return [] }
        return result.stdout
            .split(separator: "\n")
            .compactMap { parseRouteLine(String($0)) }
    }

    private func parseRouteLine(_ line: String) -> HelperRouteEntry? {
        let columns = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard columns.count >= 4 else { return nil }
        let destination = columns[0]
        guard destination != "Destination",
              destination != "Internet:",
              destination != "Internet6:",
              destination != "Routing"
        else { return nil }
        return HelperRouteEntry(destination: destination, gateway: columns[1], flags: columns[2], interface: columns[3])
    }

    private func defaultRoute() -> HelperDefaultRouteState? {
        guard let result = try? HelperShell.run("/sbin/route", ["-n", "get", "default"]),
              result.status == 0
        else { return nil }
        let lines = result.stdout.split(separator: "\n").map(String.init)
        return HelperDefaultRouteState(
            gateway: value(after: "gateway:", in: lines),
            interface: value(after: "interface:", in: lines),
            raw: result.stdout
        )
    }

    private func rollbackCandidates(current: [HelperRouteEntry], baseline: [HelperRouteEntry]) -> [HelperRouteEntry] {
        let baselineKeys = Set(baseline.map(routeKey))
        return current.filter { baselineKeys.contains(routeKey($0)) == false && isTunRoute($0) }
    }

    private func routeKey(_ route: HelperRouteEntry) -> String {
        "\(route.destination)|\(route.gateway)|\(route.interface)"
    }

    private func isTunRoute(_ route: HelperRouteEntry) -> Bool {
        let text = "\(route.destination) \(route.gateway) \(route.interface)".lowercased()
        guard text.contains("utun") else { return false }
        guard route.destination != "default" else { return true }
        guard route.destination.hasPrefix("127.") == false,
              route.destination.hasPrefix("224.") == false,
              route.destination.hasPrefix("255.") == false,
              route.destination.hasPrefix("fe80") == false
        else { return false }
        return route.destination.range(of: #"^[A-Za-z0-9:._/%+-]+$"#, options: .regularExpression) != nil
    }

    private func shouldRestoreDefaultRoute(current: HelperDefaultRouteState?, snapshot: HelperDefaultRouteState?) -> Bool {
        guard let snapshot else { return false }
        guard let current else { return true }
        return current.gateway != snapshot.gateway || current.interface != snapshot.interface
    }

    private func value(after prefix: String, in lines: [String]) -> String {
        guard let line = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }) else { return "" }
        return line
            .trimmingCharacters(in: .whitespaces)
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
