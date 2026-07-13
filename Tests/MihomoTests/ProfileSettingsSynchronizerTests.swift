import XCTest
@testable import Mihomo

final class ProfileSettingsSynchronizerTests: XCTestCase {
    private let synchronizer = ProfileSettingsSynchronizer()

    func testProfileValuesOverrideLinkedAppSettings() throws {
        let profile = """
        mixed-port: 19090
        socks-port: 19091
        allow-lan: true
        log-level: debug
        tun:
          enable: true
          stack: mixed
        dns:
          enable: true
          enhanced-mode: redir-host
          nameserver: [system, https://dns.example/dns-query]
          fallback: [https://fallback.example/dns-query]
        sniffer:
          enable: true
          parse-pure-ip: false
          force-dns-mapping: false
          override-destination: true
          sniff:
            HTTP:
              ports: [80, 8080-8088]
            TLS:
              ports: [443, 8443]
            QUIC:
              ports: [443]
          force-domain: [+.example.com]
          skip-domain: [+.push.apple.com]
          skip-dst-address: [1.1.1.1/32]
          skip-src-address: [192.168.1.0/24]
        """

        let result = try synchronizer.applyingProfile(profile, to: .default)

        XCTAssertEqual(result.mixedPort, 19090)
        XCTAssertEqual(result.socksPort, 19091)
        XCTAssertTrue(result.allowLAN)
        XCTAssertEqual(result.logLevel, "debug")
        XCTAssertTrue(result.tunEnabled)
        XCTAssertEqual(result.dnsEnhancedMode, "redir-host")
        XCTAssertEqual(result.dnsNameservers, ["system", "https://dns.example/dns-query"])
        XCTAssertEqual(result.dnsFallbacks, ["https://fallback.example/dns-query"])
        XCTAssertTrue(result.snifferEnabled)
        XCTAssertFalse(result.snifferParsePureIP)
        XCTAssertFalse(result.snifferForceDNSMapping)
        XCTAssertTrue(result.snifferOverrideDestination)
        XCTAssertEqual(result.snifferHTTPPorts, "80,8080-8088")
        XCTAssertEqual(result.snifferTLSPorts, "443,8443")
        XCTAssertEqual(result.snifferQUICPorts, "443")
        XCTAssertEqual(result.snifferForceDomains, "+.example.com")
        XCTAssertEqual(result.snifferSkipDestinationAddresses, "1.1.1.1/32")
    }

    func testLinkedAppChangesAreWrittenBackWithoutRemovingProfileContent() throws {
        let profile = """
        mixed-port: 7890
        proxies:
          - name: node-a
            type: direct
        rules:
          - MATCH,DIRECT
        dns:
          enable: true
          ipv6: false
          enhanced-mode: fake-ip
          nameserver: [system]
        """
        var previous = AppSettings.default
        previous.dnsNameservers = ["system"]
        var updated = previous
        updated.mixedPort = 17890
        updated.allowLAN = true
        updated.dnsEnhancedMode = "redir-host"
        updated.dnsNameservers = ["https://1.1.1.1/dns-query"]
        updated.tunEnabled = true
        updated.snifferEnabled = false

        let result = try synchronizer.syncingAppChanges(from: previous, to: updated, in: profile)

        XCTAssertTrue(result.contains("mixed-port: 17890"))
        XCTAssertTrue(result.contains("allow-lan: true"))
        XCTAssertTrue(result.contains("enhanced-mode: redir-host"))
        XCTAssertTrue(result.contains("https://1.1.1.1/dns-query"))
        XCTAssertTrue(result.contains("ipv6: false"))
        XCTAssertTrue(result.contains("node-a"))
        XCTAssertTrue(result.contains("MATCH,DIRECT"))
        XCTAssertTrue(result.contains("tun:"))
        XCTAssertTrue(result.contains("sniffer:"))
        XCTAssertTrue(result.contains("enable: false"))
    }

    func testUnrelatedAppChangeDoesNotRewriteProfile() throws {
        let profile = "mixed-port: 7890\nrules: [MATCH,DIRECT]\n"
        let previous = AppSettings.default
        var updated = previous
        updated.showMenuBarTrafficRates.toggle()

        let result = try synchronizer.syncingAppChanges(from: previous, to: updated, in: profile)

        XCTAssertEqual(result, profile)
    }

    @MainActor
    func testAppStoreWritesLinkedSettingsToActiveProfileFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MihomoProfileSettingsSync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let profileID = UUID()
        let fileName = "\(profileID.uuidString).yaml"
        let file = directory.appendingPathComponent(fileName)
        try "mixed-port: 7890\nrules: [MATCH,DIRECT]\n".write(to: file, atomically: true, encoding: .utf8)

        var previous = AppSettings.default
        previous.profileStoragePath = directory.path
        previous.activeProfileID = profileID
        var updated = previous
        updated.mixedPort = 17890

        let store = AppStore()
        store.settings = previous
        store.profiles = [ProfileItem(
            id: profileID,
            name: "Sync Test",
            source: .local,
            location: file.path,
            fileName: fileName,
            updatedAt: Date()
        )]

        let changed = try store.synchronizeActiveProfileSettings(
            from: previous,
            to: updated,
            persistProfileList: false
        )

        XCTAssertTrue(changed)
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("mixed-port: 17890"))
    }

    @MainActor
    func testAppStoreLoadsActiveProfileValuesIntoSettings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MihomoProfileSettingsLoad-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let profileID = UUID()
        let fileName = "\(profileID.uuidString).yaml"
        let file = directory.appendingPathComponent(fileName)
        try "mixed-port: 19090\nallow-lan: true\ntun: {enable: true}\n".write(
            to: file,
            atomically: true,
            encoding: .utf8
        )

        var settings = AppSettings.default
        settings.profileStoragePath = directory.path
        let profile = ProfileItem(
            id: profileID,
            name: "Load Test",
            source: .local,
            location: file.path,
            fileName: fileName,
            updatedAt: Date()
        )
        let store = AppStore()
        store.settings = settings
        store.profiles = [profile]

        try store.synchronizeAppSettings(from: profile, persistSettings: false)

        XCTAssertEqual(store.settings.activeProfileID, profileID)
        XCTAssertEqual(store.settings.mixedPort, 19090)
        XCTAssertTrue(store.settings.allowLAN)
        XCTAssertTrue(store.settings.tunEnabled)
    }
}
