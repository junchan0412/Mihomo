import Foundation

struct RouteEntry: Codable, Hashable {
    var destination: String
    var gateway: String
    var flags: String
    var interface: String
}

struct DefaultRouteState: Codable, Hashable {
    var gateway: String
    var interface: String
    var raw: String
}

struct TunRecoverySnapshot: Codable, Hashable {
    var createdAt: Date
    var proxySnapshot: SystemProxySnapshot
    var ipv4Routes: [RouteEntry]
    var ipv6Routes: [RouteEntry]
    var defaultIPv4Route: DefaultRouteState?
}

struct TunRecoveryRestoreResult: Hashable {
    var restoredNetworkServices: Int
    var deletedRoutes: Int
    var restoredDefaultRoute: Bool
    var detail: String
}

final class TunRecoveryManager {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func capture(systemProxy: SystemProxyManager) throws -> TunRecoverySnapshot {
        try AppPaths.ensureBaseDirectories()
        let snapshot = TunRecoverySnapshot(
            createdAt: Date(),
            proxySnapshot: try systemProxy.captureSnapshot(),
            ipv4Routes: routes(family: "inet"),
            ipv6Routes: routes(family: "inet6"),
            defaultIPv4Route: defaultRoute()
        )
        try save(snapshot)
        return snapshot
    }

    func loadSnapshot() -> TunRecoverySnapshot? {
        guard let data = try? Data(contentsOf: AppPaths.tunRecoverySnapshotFile) else { return nil }
        return try? decoder.decode(TunRecoverySnapshot.self, from: data)
    }

    func restore(systemProxy: SystemProxyManager) throws -> TunRecoveryRestoreResult {
        guard let snapshot = loadSnapshot() else {
            throw NSError(domain: "TunRecovery", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "没有可用的 TUN 回滚快照"
            ])
        }

        try systemProxy.restore(snapshot.proxySnapshot)

        let currentIPv4Routes = routes(family: "inet")
        let currentIPv6Routes = routes(family: "inet6")
        let addedRoutes = rollbackCandidates(
            current: currentIPv4Routes + currentIPv6Routes,
            baseline: snapshot.ipv4Routes + snapshot.ipv6Routes
        )
        let currentDefault = defaultRoute()
        let shouldRestoreDefault = shouldRestoreDefaultRoute(current: currentDefault, snapshot: snapshot.defaultIPv4Route)

        for route in addedRoutes {
            _ = try? Shell.run("/sbin/route", ["-n", "delete", route.destination])
        }

        if shouldRestoreDefault, let gateway = snapshot.defaultIPv4Route?.gateway, gateway.isEmpty == false {
            _ = try? Shell.run("/sbin/route", ["-n", "delete", "default"])
            _ = try Shell.run("/sbin/route", ["-n", "add", "default", gateway])
        }
        _ = try? Shell.run("/usr/bin/dscacheutil", ["-flushcache"])

        try removeSnapshot()
        let detail = "已恢复 \(snapshot.proxySnapshot.services.count) 个网络服务，删除 \(addedRoutes.count) 条 TUN 新增路由\(shouldRestoreDefault ? "，并恢复默认路由" : "")。"
        return TunRecoveryRestoreResult(
            restoredNetworkServices: snapshot.proxySnapshot.services.count,
            deletedRoutes: addedRoutes.count,
            restoredDefaultRoute: shouldRestoreDefault,
            detail: detail
        )
    }

    func verifyAdministratorAccess() throws {
        guard geteuid() == 0 else {
            throw NSError(domain: "TunRecovery", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "TUN 回滚高权限验证已迁移到 XPC Helper"
            ])
        }
    }

    private func save(_ snapshot: TunRecoverySnapshot) throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: AppPaths.tunRecoverySnapshotFile, options: .atomic)
    }

    private func removeSnapshot() throws {
        if FileManager.default.fileExists(atPath: AppPaths.tunRecoverySnapshotFile.path) {
            try FileManager.default.removeItem(at: AppPaths.tunRecoverySnapshotFile)
        }
    }

    private func routes(family: String) -> [RouteEntry] {
        guard let result = try? Shell.run("/usr/sbin/netstat", ["-rn", "-f", family]),
              result.status == 0
        else { return [] }

        return result.stdout
            .split(separator: "\n")
            .compactMap { parseRouteLine(String($0)) }
    }

    private func parseRouteLine(_ line: String) -> RouteEntry? {
        let columns = line
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        guard columns.count >= 4 else { return nil }
        let destination = columns[0]
        guard destination != "Destination",
              destination != "Internet:",
              destination != "Internet6:",
              destination != "Routing"
        else { return nil }

        return RouteEntry(
            destination: destination,
            gateway: columns[1],
            flags: columns[2],
            interface: columns[3]
        )
    }

    private func defaultRoute() -> DefaultRouteState? {
        guard let result = try? Shell.run("/sbin/route", ["-n", "get", "default"]),
              result.status == 0
        else { return nil }
        let lines = result.stdout.split(separator: "\n").map(String.init)
        let gateway = value(after: "gateway:", in: lines)
        let interface = value(after: "interface:", in: lines)
        return DefaultRouteState(gateway: gateway, interface: interface, raw: result.stdout)
    }

    private func rollbackCandidates(current: [RouteEntry], baseline: [RouteEntry]) -> [RouteEntry] {
        let baselineKeys = Set(baseline.map(routeKey))
        return current.filter { route in
            baselineKeys.contains(routeKey(route)) == false && isTunRoute(route)
        }
    }

    private func routeKey(_ route: RouteEntry) -> String {
        "\(route.destination)|\(route.gateway)|\(route.interface)"
    }

    private func isTunRoute(_ route: RouteEntry) -> Bool {
        let text = "\(route.destination) \(route.gateway) \(route.interface)".lowercased()
        guard text.contains("utun") else { return false }
        guard route.destination != "default" else { return true }
        guard route.destination.hasPrefix("127.") == false,
              route.destination.hasPrefix("224.") == false,
              route.destination.hasPrefix("255.") == false,
              route.destination.hasPrefix("fe80") == false
        else { return false }
        return safeRouteToken(route.destination)
    }

    private func safeRouteToken(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9:._/%+-]+$"#, options: .regularExpression) != nil
    }

    private func shouldRestoreDefaultRoute(current: DefaultRouteState?, snapshot: DefaultRouteState?) -> Bool {
        guard let snapshot, snapshot.gateway.isEmpty == false else { return false }
        guard let current else { return true }
        if current.interface.lowercased().contains("utun") { return true }
        return current.gateway != snapshot.gateway && current.interface != snapshot.interface
    }

    private func value(after prefix: String, in lines: [String]) -> String {
        guard let line = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }) else { return "" }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
