import XCTest
@testable import Mihomo

final class RuntimeConfigBuilderTests: XCTestCase {
    func testBuildAppliesOverlayFragmentsAndDisabledRules() throws {
        let profile = """
        mixed-port: 9999
        allow-lan: true
        proxies:
          - name: node-a
            type: direct
        proxy-groups:
          - name: Auto
            type: select
            proxies:
              - node-a
        rules:
          - DOMAIN-SUFFIX,example.com,Auto
          - MATCH,DIRECT
        """
        let fragment = ConfigFragment(
            name: "Add provider",
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

        let generated = try RuntimeConfigBuilder().build(
            profileContent: profile,
            settings: settings,
            fragments: [fragment],
            disabledRules: ["DOMAIN-SUFFIX,example.com,Auto"]
        )

        XCTAssertTrue(generated.contains("mixed-port: 7891"))
        XCTAssertTrue(generated.contains("socks-port: 7892"))
        XCTAssertTrue(generated.contains("tun:"))
        XCTAssertTrue(generated.contains("rule-providers:"))
        XCTAssertFalse(generated.contains("DOMAIN-SUFFIX,example.com,Auto"))
        XCTAssertTrue(generated.contains("MATCH,DIRECT"))
    }
}
