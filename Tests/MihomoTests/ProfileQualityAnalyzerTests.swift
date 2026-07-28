import XCTest
@testable import Mihomo

final class ProfileQualityAnalyzerTests: XCTestCase {
    func testProviderOnlyProfileDoesNotWarnAboutMissingOutboundSource() {
        let profile = ProfileItem(
            id: UUID(), name: "Provider Only", source: .local,
            location: "/tmp/provider-only.yaml", fileName: "provider-only.yaml", updatedAt: Date()
        )
        let content = """
        proxy-providers:
          remote:
            type: http
            url: https://example.com/nodes.yaml
            path: ./proxy_providers/remote.yaml
        proxy-groups:
          - name: Auto
            type: select
            use:
              - remote
        rules:
          - MATCH,Auto
        """

        let report = ProfileQualityAnalyzer().analyze(
            profile: profile, profileContent: content, settings: AppSettings(), fragments: [], disabledRules: []
        )

        XCTAssertFalse(report.issues.contains { $0.title == "没有可用出站来源" })
    }

    func testRuntimeSourceItemsIdentifyConfigPriorityAndAppDefaults() {
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
        XCTAssertEqual(sources["mixed-port"]?.source, "Profile 配置")
        XCTAssertEqual(sources["mixed-port"]?.value, "9999")
        XCTAssertEqual(sources["mixed-port"]?.usesAppDefault, false)
        XCTAssertEqual(sources["proxy-groups"]?.source, "Profile 配置")
        XCTAssertEqual(sources["rule-providers"]?.source, "YAML 覆写")
        XCTAssertEqual(sources["tun"]?.source, "应用默认")
        XCTAssertEqual(sources["tun"]?.usesAppDefault, true)
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
            snifferHTTPPorts: "99999",
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
        XCTAssertTrue(report.issues.contains { $0.title == "域名嗅探端口可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "HTTP Provider 缺少 URL" })
        XCTAssertTrue(report.issues.contains { $0.title == "Provider path 不安全" })
    }

    func testAnalyzerFlagsDetailedRuntimeSchemaRisks() {
        let profile = ProfileItem(
            id: UUID(),
            name: "Detailed Risks",
            source: .local,
            location: "/tmp/detailed.yaml",
            fileName: "detailed.yaml",
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
        rule-providers:
          bad-rules:
            type: http
            behavior: process
            url: https://example.com/rules.yaml
        rules:
          - RULE-SET,bad-rules,DIRECT
        """
        let settings = AppSettings(
            mixedPort: 7890,
            tunEnabled: true,
            snifferEnabled: true,
            snifferForceDomains: "https://example.com/path",
            dnsNameservers: ["ftp://resolver.example.com"]
        )

        let report = ProfileQualityAnalyzer().analyze(
            profile: profile,
            profileContent: content,
            settings: settings,
            fragments: [],
            disabledRules: []
        )

        XCTAssertTrue(report.issues.contains { $0.title == "DNS nameserver 格式可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "域名嗅探规则格式可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "Rule Provider behavior 可疑" })
    }

    func testRuntimeSchemaFlagsUnsupportedTunStack() {
        let issues = ProfileQualityAnalyzer().validateRuntimeSchema(
            root: [
                "mixed-port": 7890,
                "tun": [
                    "enable": true,
                    "stack": "unsupported",
                    "dns-hijack": ["any:53"]
                ]
            ],
            providers: [],
            settings: AppSettings(tunEnabled: true)
        )

        XCTAssertTrue(issues.contains { $0.title == "TUN stack 可疑" })
    }

}
