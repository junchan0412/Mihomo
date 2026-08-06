import XCTest
@testable import Mihomo

final class AppSettingsValidationTests: XCTestCase {
    func testDefaultSettingsAreValid() {
        XCTAssertTrue(AppSettingsValidation.validate(.default).isEmpty)
    }

    func testPortsAndConcurrencyReportFieldLevelIssues() {
        var settings = AppSettings.default
        settings.controllerPort = 0
        settings.mixedPort = 9_090
        settings.socksPort = 9_090
        settings.profileRefreshMaxConcurrent = 13
        settings.delayTestTimeoutMS = 999

        let issues = AppSettingsValidation.validate(settings)

        XCTAssertEqual(AppSettingsValidation.issue(for: .controllerPort, in: settings), "控制端口必须是 1–65535 之间的整数。")
        XCTAssertTrue(issues.contains { $0.field == .mixedPort && $0.message.contains("不能使用同一端口") })
        XCTAssertTrue(issues.contains { $0.field == .socksPort && $0.message.contains("不能使用同一端口") })
        XCTAssertTrue(issues.contains { $0.field == .profileRefreshMaxConcurrent && $0.message.contains("1–12") })
        XCTAssertTrue(issues.contains { $0.field == .delayTestTimeoutMS && $0.message.contains("1000–60000") })
    }

    func testInvalidURLAndAddressInputsAreRejected() {
        var settings = AppSettings.default
        settings.delayTestURL = "javascript:alert(1)"
        settings.remoteAPIBindAddress = "999.999.1.1"
        settings.systemDNSServers = ["1.1.1.1/33"]
        settings.snifferSkipSourceAddresses = "10.0.0.0/8,not-an-address"

        let issues = AppSettingsValidation.validate(settings)

        XCTAssertTrue(issues.contains { $0.field == .delayTestURL })
        XCTAssertTrue(issues.contains { $0.field == .remoteAPIBindAddress })
        XCTAssertTrue(issues.contains { $0.field == .systemDNSServers })
        XCTAssertTrue(issues.contains { $0.field == .snifferSkipSourceAddresses })
    }

    func testDNSListsAcceptIPHostnameAndSupportedSchemes() {
        var settings = AppSettings.default
        settings.dnsNameservers = ["1.1.1.1", "dns.example.com", "https://dns.google/dns-query"]
        settings.dnsFallbacks = ["tls://1.0.0.1"]

        XCTAssertFalse(AppSettingsValidation.validate(settings).contains { $0.field == .dnsNameservers })
        XCTAssertFalse(AppSettingsValidation.validate(settings).contains { $0.field == .dnsFallbacks })
    }
}
