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

        XCTAssertTrue(generated.contains("mixed-port: 9999"))
        XCTAssertTrue(generated.contains("socks-port: 7892"))
        XCTAssertTrue(generated.contains("tun:"))
        XCTAssertTrue(generated.contains("rule-providers:"))
        XCTAssertFalse(generated.contains("DOMAIN-SUFFIX,example.com,Auto"))
        XCTAssertTrue(generated.contains("MATCH,DIRECT"))
    }

    func testYAMLOverrideTakesPriorityOverProfileAndAppDefaults() throws {
        let profile = """
        mixed-port: 9000
        dns:
          enable: true
          enhanced-mode: redir-host
        """
        let fragment = ConfigFragment(
            name: "Runtime preferences",
            kind: .yaml,
            enabled: true,
            content: """
            mixed-port: 9100
            dns:
              enhanced-mode: fake-ip
            """
        )
        let settings = AppSettings(mixedPort: 7890, dnsEnhancedMode: "normal", dnsNameservers: ["system"])

        let generated = try RuntimeConfigBuilder().build(
            profileContent: profile,
            settings: settings,
            fragments: [fragment]
        )

        XCTAssertTrue(generated.contains("mixed-port: 9100"))
        XCTAssertTrue(generated.contains("enhanced-mode: fake-ip"))
    }

    func testAppManagedControlChannelOverridesProfileEndpointAndSecret() throws {
        let profile = """
        external-controller: 192.168.1.20:9999
        secret: profile-secret
        external-controller-unix: /tmp/mihomo.sock
        """
        let settings = AppSettings(
            controllerHost: "10.0.0.8",
            controllerPort: 19090,
            controllerSecret: "app-secret"
        )

        let generated = try RuntimeConfigBuilder().build(profileContent: profile, settings: settings)

        XCTAssertTrue(generated.contains("external-controller: 127.0.0.1:19090"))
        XCTAssertTrue(generated.contains("secret: app-secret"))
        XCTAssertFalse(generated.contains("192.168.1.20:9999"))
        XCTAssertFalse(generated.contains("profile-secret"))
        XCTAssertFalse(generated.contains("external-controller-unix"))
    }

    func testAppManagedDomainSniffingEmitsProtocolAndExceptionSettings() throws {
        let settings = AppSettings(
            snifferManagedByApp: true,
            snifferEnabled: true,
            snifferParsePureIP: true,
            snifferForceDNSMapping: true,
            snifferOverrideDestination: true,
            snifferHTTPPorts: "80,8080-8088",
            snifferTLSPorts: "443,8443",
            snifferQUICPorts: "443",
            snifferForceDomains: "+.example.com",
            snifferSkipDomains: "+.push.apple.com",
            snifferSkipDestinationAddresses: "1.1.1.1/32",
            snifferSkipSourceAddresses: "192.168.1.0/24"
        )

        let generated = try RuntimeConfigBuilder().build(profileContent: "", settings: settings)

        XCTAssertTrue(generated.contains("parse-pure-ip: true"))
        XCTAssertTrue(generated.contains("force-dns-mapping: true"))
        XCTAssertTrue(generated.contains("override-destination: true"))
        XCTAssertTrue(generated.contains("QUIC:"))
        XCTAssertTrue(generated.contains("8080-8088"))
        XCTAssertTrue(generated.contains("+.push.apple.com"))
        XCTAssertTrue(generated.contains("1.1.1.1/32"))
        XCTAssertTrue(generated.contains("192.168.1.0/24"))
    }

    func testSnifferUsesSafeDefaultDestinationExclusions() throws {
        let generated = try RuntimeConfigBuilder().build(
            profileContent: "",
            settings: AppSettings(snifferEnabled: true, snifferSkipDestinationAddresses: "")
        )

        XCTAssertTrue(generated.contains("91.105.192.0/23"))
        XCTAssertTrue(generated.contains("2001:b28:f23f::/48"))
    }

    func testProfileDomainSniffingOverridesAppDefaults() throws {
        let profile = """
        sniffer:
          enable: false
          sniff:
            TLS:
              ports: [9443]
        """
        let settings = AppSettings(snifferManagedByApp: true, snifferEnabled: true)

        let generated = try RuntimeConfigBuilder().build(profileContent: profile, settings: settings)

        XCTAssertTrue(generated.contains("enable: false"))
        XCTAssertTrue(generated.contains("9443"))
    }

    func testTunBuildsMihomoDNSHijackingAndFakeIPPlan() throws {
        let settings = AppSettings(tunEnabled: true, dnsEnabled: false, dnsEnhancedMode: "fake-ip")

        let generated = try RuntimeConfigBuilder().build(profileContent: "", settings: settings)

        XCTAssertTrue(generated.contains("stack: mixed"))
        XCTAssertTrue(generated.contains("dns-hijack:"))
        XCTAssertTrue(generated.contains("any:53"))
        XCTAssertTrue(generated.contains("fake-ip-range: 198.18.0.1/16"))
        XCTAssertTrue(generated.contains("store-fake-ip: true"))
    }

    func testNetworkRuntimePlanForcesDNSWhenTunIsEnabled() {
        let plan = NetworkRuntimePlan(settings: AppSettings(tunEnabled: true, dnsEnabled: false))

        XCTAssertTrue(plan.tunEnabled)
        XCTAssertTrue(plan.dnsEnabled)
        XCTAssertEqual(plan.dnsHijackTargets, ["any:53"])
    }

    func testTunOverridesContradictoryProfileDNSDisable() throws {
        let profile = """
        tun:
          enable: true
        dns:
          enable: false
        """

        let generated = try RuntimeConfigBuilder().build(
            profileContent: profile,
            settings: AppSettings(tunEnabled: true, dnsEnabled: false)
        )

        XCTAssertFalse(generated.contains("enable: false"))
        XCTAssertTrue(generated.contains("dns-hijack:"))
    }

    func testIndependentNodeProvidersAreInjectedWithoutChangingProfileContent() throws {
        let provider = NodeProvider(
            id: UUID(uuidString: "6E6BB02D-A610-4E5B-8D5D-52B0D8F0B067")!,
            name: "独立订阅",
            url: "https://example.com/subscription",
            path: "proxy_providers/managed-subscription.yaml",
            interval: 7_200
        )

        let generated = try RuntimeConfigBuilder().build(
            profileContent: "proxy-groups: []\n",
            settings: AppSettings(),
            nodeProviders: [provider]
        )

        XCTAssertTrue(generated.contains("独立订阅:"), generated)
        XCTAssertTrue(generated.contains("https://example.com/subscription"), generated)
        XCTAssertTrue(generated.contains("managed-subscription.yaml"), generated)
        XCTAssertTrue(generated.contains("interval: 7200"), generated)
    }

    func testDisabledIndependentNodeProviderIsNotInjected() throws {
        let provider = NodeProvider(name: "已停用订阅", url: "https://example.com/subscription", enabled: false)

        let generated = try RuntimeConfigBuilder().build(
            profileContent: "proxy-groups: []\n",
            settings: AppSettings(),
            nodeProviders: [provider]
        )

        XCTAssertFalse(generated.contains("已停用订阅:"), generated)
    }

    func testIndependentNodeProviderNameCollisionIsReported() throws {
        let provider = NodeProvider(name: "shared", url: "https://example.com/subscription")

        XCTAssertThrowsError(try RuntimeConfigBuilder().build(
            profileContent: """
            proxy-providers:
              shared:
                type: http
                url: https://example.com/existing
            """,
            settings: AppSettings(),
            nodeProviders: [provider]
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("同名"))
        }
    }
}
