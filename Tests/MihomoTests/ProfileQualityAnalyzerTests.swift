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
        XCTAssertTrue(report.issues.contains { $0.title == "Sniffer domain 格式可疑" })
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

    func testAnalyzerFlagsRuleTypeAndPayloadTypos() {
        let profile = ProfileItem(
            id: UUID(),
            name: "Rule Typos",
            source: .local,
            location: "/tmp/rule-typos.yaml",
            fileName: "rule-typos.yaml",
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
        rules:
          - DOMAIN-SUFFX,example.com,DIRECT
          - DOMAIN,https://example.com/path,DIRECT
          - MATCH,DIRECT
        """

        let report = ProfileQualityAnalyzer().analyze(
            profile: profile,
            profileContent: content,
            settings: AppSettings(),
            fragments: [],
            disabledRules: []
        )

        XCTAssertTrue(report.issues.contains { $0.title == "规则类型可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "规则匹配内容可疑" })
    }

    func testAnalyzerFlagsCIDRPortAndNetworkRulePayloadRisks() {
        let profile = ProfileItem(
            id: UUID(),
            name: "Rule Payload Risks",
            source: .local,
            location: "/tmp/rule-payload-risks.yaml",
            fileName: "rule-payload-risks.yaml",
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
        rules:
          - IP-CIDR,example.com/24,DIRECT
          - IP-CIDR6,192.168.0.0/64,DIRECT
          - DST-PORT,99999,DIRECT
          - NETWORK,http,DIRECT
          - MATCH,DIRECT
        """

        let report = ProfileQualityAnalyzer().analyze(
            profile: profile,
            profileContent: content,
            settings: AppSettings(),
            fragments: [],
            disabledRules: []
        )

        XCTAssertEqual(report.issues.filter { $0.title == "CIDR 地址格式可疑" }.count, 2)
        XCTAssertTrue(report.issues.contains { $0.title == "端口规则可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "NETWORK 规则可疑" })
    }

    func testAnalyzerFlagsProcessGeoIPAndASNRulePayloadRisks() {
        let profile = ProfileItem(
            id: UUID(),
            name: "Process And GeoIP Risks",
            source: .local,
            location: "/tmp/process-geoip-risks.yaml",
            fileName: "process-geoip-risks.yaml",
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
        rules:
          - SRC-IP-CIDR,example.com/24,DIRECT
          - GEOIP,https://example.com/cn,DIRECT
          - IP-ASN,AS13335,DIRECT
          - PROCESS-NAME,/Applications/Safari.app/Contents/MacOS/Safari,DIRECT
          - PROCESS-PATH,Safari,DIRECT
          - MATCH,DIRECT
        """

        let report = ProfileQualityAnalyzer().analyze(
            profile: profile,
            profileContent: content,
            settings: AppSettings(),
            fragments: [],
            disabledRules: []
        )

        XCTAssertTrue(report.issues.contains { $0.title == "CIDR 地址格式可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "GEOIP 规则可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "IP-ASN 规则可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "进程名称规则可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "进程路径规则可疑" })
    }

    func testAnalyzerFlagsPolicyGroupMemberAndProviderReferenceRisks() {
        let profile = ProfileItem(
            id: UUID(),
            name: "Policy Group References",
            source: .local,
            location: "/tmp/policy-group-references.yaml",
            fileName: "policy-group-references.yaml",
            updatedAt: Date()
        )
        let content = """
        proxies:
          - name: node-a
            type: direct
        proxy-providers:
          remote-proxies:
            type: http
            url: https://example.com/proxies.yaml
        rule-providers:
          remote-rules:
            type: http
            behavior: domain
            url: https://example.com/rules.yaml
        proxy-groups:
          - name: Auto
            type: select
            proxies:
              - node-a
              - missing-node
              - DIRECT
            use:
              - remote-rules
              - missing-proxies
        rules:
          - MATCH,Auto
        """

        let report = ProfileQualityAnalyzer().analyze(
            profile: profile,
            profileContent: content,
            settings: AppSettings(),
            fragments: [],
            disabledRules: []
        )

        XCTAssertTrue(report.issues.contains { $0.title == "策略组节点不存在" })
        XCTAssertTrue(report.issues.contains { $0.title == "策略组 Provider 类型不匹配" })
        XCTAssertTrue(report.issues.contains { $0.title == "Proxy Provider 不存在" })
    }
}
