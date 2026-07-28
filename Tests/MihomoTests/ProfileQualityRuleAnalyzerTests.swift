import XCTest
@testable import Mihomo

final class ProfileQualityRuleAnalyzerTests: XCTestCase {
    func testAnalyzerFlagsRuleTypeAndPayloadTypos() {
        let profile = makeProfile(name: "Rule Typos", fileName: "rule-typos.yaml")
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

        let report = analyze(profile: profile, content: content)

        XCTAssertTrue(report.issues.contains { $0.title == "规则类型可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "规则匹配内容可疑" })
    }

    func testAnalyzerFlagsCIDRPortAndNetworkRulePayloadRisks() {
        let profile = makeProfile(name: "Rule Payload Risks", fileName: "rule-payload-risks.yaml")
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

        let report = analyze(profile: profile, content: content)

        XCTAssertEqual(report.issues.filter { $0.title == "CIDR 地址格式可疑" }.count, 2)
        XCTAssertTrue(report.issues.contains { $0.title == "端口规则可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "NETWORK 规则可疑" })
    }

    func testAnalyzerFlagsProcessGeoIPAndASNRulePayloadRisks() {
        let profile = makeProfile(name: "Process And GeoIP Risks", fileName: "process-geoip-risks.yaml")
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

        let report = analyze(profile: profile, content: content)

        XCTAssertTrue(report.issues.contains { $0.title == "CIDR 地址格式可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "GEOIP 规则可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "IP-ASN 规则可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "进程名称规则可疑" })
        XCTAssertTrue(report.issues.contains { $0.title == "进程路径规则可疑" })
    }

    func testAnalyzerFlagsPolicyGroupMemberAndProviderReferenceRisks() {
        let profile = makeProfile(name: "Policy Group References", fileName: "policy-group-references.yaml")
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

        let report = analyze(profile: profile, content: content)

        XCTAssertTrue(report.issues.contains { $0.title == "策略组节点不存在" })
        XCTAssertTrue(report.issues.contains { $0.title == "策略组 Provider 类型不匹配" })
        XCTAssertTrue(report.issues.contains { $0.title == "Proxy Provider 不存在" })
    }

    func testSnifferRuleIssueIdentifiesAppSettingsAsSource() {
        let profile = makeProfile(name: "Source Labels", fileName: "source-labels.yaml")
        var settings = AppSettings.default
        settings.snifferManagedByApp = true
        settings.snifferEnabled = true
        settings.snifferSkipDomains = "https://example.com/path"

        let report = ProfileQualityAnalyzer().analyze(
            profile: profile,
            profileContent: "proxies: [{name: direct, type: direct}]\nrules: [MATCH,DIRECT]\n",
            settings: settings,
            fragments: [],
            disabledRules: []
        )

        let issue = report.issues.first { $0.title == "域名嗅探规则格式可疑" }
        XCTAssertEqual(issue?.source, .appSettings)
    }

    private func makeProfile(name: String, fileName: String) -> ProfileItem {
        ProfileItem(
            id: UUID(),
            name: name,
            source: .local,
            location: "/tmp/\(fileName)",
            fileName: fileName,
            updatedAt: Date()
        )
    }

    private func analyze(profile: ProfileItem, content: String) -> ProfileQualityReport {
        ProfileQualityAnalyzer().analyze(
            profile: profile,
            profileContent: content,
            settings: AppSettings(),
            fragments: [],
            disabledRules: []
        )
    }
}
