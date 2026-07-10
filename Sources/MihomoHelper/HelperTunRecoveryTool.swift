import Foundation

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
