import XCTest
@testable import Mihomo

final class ProfileQualityAnalyzerTests: XCTestCase {
    func testRuntimeSourceItemsIdentifyAppOverlayProfileAndYamlFragments() {
        let profile = ProfileItem(
            id: UUID(),
            name: "Local",
            source: .local,
            location: "/tmp/local.yaml",
            fileName: "local.yaml",
            updatedAt: Date()
        )
        let content = """
        mixed-port: 9999
        proxies:
          - name: node-a
            type: direct
        proxy-groups:
          - name: Auto
            type: select
            proxies:
              - node-a
        rules:
          - MATCH,DIRECT
        """
        let fragment = ConfigFragment(
            name: "Rule providers",
            kind: .yaml,
            enabled: true,
            content: """
            rule-providers:
              reject-list:
                type: http
                behavior: domain
                url: https://example.com/reject.yaml
            """
        )
        let settings = AppSettings(
            mixedPort: 7891,
            socksPort: 7892,
            tunEnabled: true,
            dnsNameservers: ["https://1.1.1.1/dns-query"]
        )

        let report = ProfileQualityAnalyzer().analyze(
            profile: profile,
            profileContent: content,
            settings: settings,
            fragments: [fragment],
            disabledRules: []
        )

        let sources = Dictionary(uniqueKeysWithValues: report.sourceItems.map { ($0.path, $0) })
        XCTAssertEqual(sources["mixed-port"]?.source, "App overlay")
        XCTAssertEqual(sources["mixed-port"]?.value, "7891")
        XCTAssertEqual(sources["mixed-port"]?.isAppManaged, true)
        XCTAssertEqual(sources["proxy-groups"]?.source, "Profile")
        XCTAssertEqual(sources["rule-providers"]?.source, "YAML 片段")
        XCTAssertEqual(sources["tun"]?.source, "App overlay")
    }

    func testAnalyzerFlagsRuntimeSchemaRisks() {
        let profile = ProfileItem(
            id: UUID(),
            name: "Risky",
            source: .local,
            location: "/tmp/risky.yaml",
            fileName: "risky.yaml",
            updatedAt: Date()
        )
        let content = """
        proxies:
          - name: node-a
            type: direct
        proxy-groups:
          - name: Auto
            type: select
            proxies:
              - node-a
        proxy-providers:
          remote-proxies:
            type: http
            path: ../remote.yaml
        rules:
          - MATCH,DIRECT
        """
        let settings = AppSettings(
            mixedPort: 7890,
            tunEnabled: true,
            snifferEnabled: true,
            snifferPorts: "99999",
            dnsEnhancedMode: "unknown-mode",
            dnsNameservers: ["https://1.1.1.1/dns-query"]
        )

        let report = ProfileQualityAnalyzer().analyze(
            profile: profile,
            profileContent: content,
            settings: settings,
            fragments: [],
            disabledRules: []
        )

        XCTAssertTrue(report.issues.contains { $0.title == "DNS enhanced-mode 可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "Sniffer 端口可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "HTTP Provider 缺少 URL" })
        XCTAssertTrue(report.issues.contains { $0.title == "Provider path 不安全" })
    }
}
