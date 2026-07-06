import XCTest
@testable import Mihomo

final class NetworkSecurityCenterTests: XCTestCase {
    func testSnapshotItemsDescribeIndependentRecoveryBoundaries() {
        let date = Date(timeIntervalSince1970: 1_785_000_000)
        let service = NetworkServiceProxyState(
            service: "Wi-Fi",
            web: ProxyEndpointState(enabled: true, server: "127.0.0.1", port: 7890),
            secureWeb: ProxyEndpointState(enabled: true, server: "127.0.0.1", port: 7890),
            socks: ProxyEndpointState(enabled: false, server: "", port: 0),
            bypassDomains: ["localhost"],
            dnsServers: ["1.1.1.1"]
        )
        let proxySnapshot = SystemProxySnapshot(createdAt: date, services: [service])
        let dnsSnapshot = SystemProxySnapshot(createdAt: date.addingTimeInterval(10), services: [service])
        let tunSnapshot = TunRecoverySnapshot(
            createdAt: date.addingTimeInterval(20),
            proxySnapshot: proxySnapshot,
            ipv4Routes: [.init(destination: "0.0.0.0/1", gateway: "utun9", flags: "UGSc", interface: "utun9")],
            ipv6Routes: [],
            defaultIPv4Route: .init(gateway: "192.168.1.1", interface: "en0", raw: "gateway: 192.168.1.1")
        )

        let items = NetworkSecurityCenter.snapshotItems(
            proxySnapshot: proxySnapshot,
            dnsSnapshot: dnsSnapshot,
            tunSnapshot: tunSnapshot,
            paths: .init(systemProxy: "/proxy.json", systemDNS: "/dns.json", tunRecovery: "/tun.json")
        )

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].kind, .systemProxy)
        XCTAssertTrue(items[0].detail.contains("HTTP"))
        XCTAssertTrue(items[0].detail.contains("不会恢复 DNS 或 TUN 路由"))
        XCTAssertEqual(items[1].kind, .systemDNS)
        XCTAssertTrue(items[1].detail.contains("不恢复代理端口"))
        XCTAssertEqual(items[2].kind, .tunRecovery)
        XCTAssertTrue(items[2].detail.contains("默认路由"))
        XCTAssertEqual(items.map(\.health), [.warning, .warning, .warning])
    }

    func testOverallHealthUsesHighestSeverity() {
        let ok = NetworkTakeoverState(
            kind: .systemProxy,
            desiredState: "on",
            actualState: "on",
            lastOperation: "ok",
            recoveryAction: "-",
            health: .ok
        )
        let warning = NetworkTakeoverState(
            kind: .systemDNS,
            desiredState: "on",
            actualState: "snapshot",
            lastOperation: "warn",
            recoveryAction: "restore",
            health: .warning
        )
        let failed = NetworkTakeoverState(
            kind: .tun,
            desiredState: "on",
            actualState: "missing snapshot",
            lastOperation: "failed",
            recoveryAction: "restore",
            health: .failed
        )

        XCTAssertEqual(NetworkSecurityCenter.overallHealth(for: []), .inactive)
        XCTAssertEqual(NetworkSecurityCenter.overallHealth(for: [ok]), .ok)
        XCTAssertEqual(NetworkSecurityCenter.overallHealth(for: [ok, warning]), .warning)
        XCTAssertEqual(NetworkSecurityCenter.overallHealth(for: [ok, warning, failed]), .failed)
    }
}
