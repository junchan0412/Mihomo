import Foundation

struct NetworkSecurityCenter {
    static func snapshotItems(
        proxySnapshot: SystemProxySnapshot?,
        dnsSnapshot: SystemProxySnapshot?,
        tunSnapshot: TunRecoverySnapshot?,
        paths: NetworkSecuritySnapshotPaths
    ) -> [NetworkSecuritySnapshotItem] {
        [
            proxySnapshotItem(proxySnapshot, path: paths.systemProxy),
            dnsSnapshotItem(dnsSnapshot, path: paths.systemDNS),
            tunSnapshotItem(tunSnapshot, path: paths.tunRecovery)
        ]
    }

    static func overallHealth(for states: [NetworkTakeoverState]) -> NetworkTakeoverHealth {
        if states.contains(where: { $0.health == .failed }) { return .failed }
        if states.contains(where: { $0.health == .warning }) { return .warning }
        if states.contains(where: { $0.health == .ok }) { return .ok }
        return .inactive
    }

    private static func proxySnapshotItem(_ snapshot: SystemProxySnapshot?, path: String) -> NetworkSecuritySnapshotItem {
        guard let snapshot else {
            return .init(
                kind: .systemProxy,
                path: path,
                createdAt: nil,
                status: "无待恢复代理快照",
                detail: "系统代理恢复只使用此文件；DNS 与 TUN 回滚不会改动代理开关。",
                health: .inactive
            )
        }

        return .init(
            kind: .systemProxy,
            path: path,
            createdAt: snapshot.createdAt,
            status: "已保存 \(snapshot.services.count) 个网络服务",
            detail: "用于恢复 HTTP、HTTPS、SOCKS 代理与 bypass 域名。不会恢复 DNS 或 TUN 路由。",
            health: .warning
        )
    }

    private static func dnsSnapshotItem(_ snapshot: SystemProxySnapshot?, path: String) -> NetworkSecuritySnapshotItem {
        guard let snapshot else {
            return .init(
                kind: .systemDNS,
                path: path,
                createdAt: nil,
                status: "无待恢复 DNS 快照",
                detail: "系统 DNS 接管只使用此文件；恢复 DNS 不会改变系统代理或 TUN 路由。",
                health: .inactive
            )
        }

        let servicesWithDNS = snapshot.services.filter { $0.dnsServers.isEmpty == false }.count
        return .init(
            kind: .systemDNS,
            path: path,
            createdAt: snapshot.createdAt,
            status: "已保存 \(snapshot.services.count) 个网络服务",
            detail: "\(servicesWithDNS) 个服务有原始 DNS。用于停止核心或手动修复时恢复 DNS，不恢复代理端口。",
            health: .warning
        )
    }

    private static func tunSnapshotItem(_ snapshot: TunRecoverySnapshot?, path: String) -> NetworkSecuritySnapshotItem {
        guard let snapshot else {
            return .init(
                kind: .tunRecovery,
                path: path,
                createdAt: nil,
                status: "无 TUN 回滚快照",
                detail: "启动 TUN 核心前会捕获 DNS、IPv4/IPv6 路由和默认路由；回滚不会恢复系统代理开关。",
                health: .inactive
            )
        }

        let routeCount = snapshot.ipv4Routes.count + snapshot.ipv6Routes.count
        let defaultRoute = snapshot.defaultIPv4Route.map { "\($0.gateway) / \($0.interface)" } ?? "未记录默认路由"
        return .init(
            kind: .tunRecovery,
            path: path,
            createdAt: snapshot.createdAt,
            status: "已保存 \(routeCount) 条路由",
            detail: "DNS 服务 \(snapshot.proxySnapshot.services.count) 个，默认路由 \(defaultRoute)。用于删除新增 utun 路由并恢复必要默认路由。",
            health: .warning
        )
    }
}
