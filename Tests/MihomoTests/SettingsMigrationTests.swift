import Foundation
import XCTest
@testable import Mihomo

final class SettingsMigrationTests: XCTestCase {
    func testV2SettingsMigrateToCurrentSchemaAndDoNotMigrateAfterReload() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MihomoSettingsMigrationTests-\(UUID().uuidString)", isDirectory: true)
        let settingsFile = root.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var version2 = AppSettings.default
        version2.settingsSchemaVersion = 2

        let migration = try XCTUnwrap(SettingsMigrator.migration(for: version2))
        XCTAssertEqual(migration.settings.settingsSchemaVersion, 7)
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v3：") })
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v4：") })
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v5：") })
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v6：") })
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v7：") })

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(migration.settings).write(to: settingsFile, options: .atomic)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reloaded = try decoder.decode(AppSettings.self, from: Data(contentsOf: settingsFile))

        XCTAssertEqual(reloaded.settingsSchemaVersion, 7)
        XCTAssertNil(try SettingsMigrator.migration(for: reloaded))
    }

    func testV1SettingsRunEveryMigrationStep() throws {
        var version1 = AppSettings.default
        version1.settingsSchemaVersion = 1
        version1.coreSource = .local
        version1.managedCoreEnabled = true

        let migration = try XCTUnwrap(SettingsMigrator.migration(for: version1))

        XCTAssertEqual(migration.settings.settingsSchemaVersion, 7)
        XCTAssertFalse(migration.settings.managedCoreEnabled)
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v2：") })
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v3：") })
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v4：") })
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v5：") })
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v6：") })
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v7：") })
    }

    func testV4MigrationMakesControlChannelLocalAndExpandsDomainSniffing() throws {
        var version4 = AppSettings.default
        version4.settingsSchemaVersion = 4
        version4.controllerHost = "192.168.1.20"
        version4.remoteAPIEnabled = true
        version4.remoteAPIBindAddress = "127.0.0.1"
        version4.controllerSecret = ""
        version4.snifferPorts = "80,443,8443"

        let migration = try XCTUnwrap(SettingsMigrator.migration(for: version4))

        XCTAssertEqual(migration.settings.settingsSchemaVersion, 7)
        XCTAssertEqual(migration.settings.controllerHost, "127.0.0.1")
        XCTAssertEqual(migration.settings.remoteAPIBindAddress, "0.0.0.0")
        XCTAssertFalse(migration.settings.controllerSecret.isEmpty)
        XCTAssertTrue(migration.settings.snifferManagedByApp)
        XCTAssertEqual(migration.settings.snifferHTTPPorts, "80,443,8443")
        XCTAssertEqual(migration.settings.snifferTLSPorts, "80,443,8443")
        XCTAssertEqual(migration.settings.snifferQUICPorts, "")
    }

    func testV5MigrationAddsCompleteGeoDefaults() throws {
        var version5 = AppSettings.default
        version5.settingsSchemaVersion = 5

        let migration = try XCTUnwrap(SettingsMigrator.migration(for: version5))

        XCTAssertEqual(migration.settings.settingsSchemaVersion, 7)
        XCTAssertTrue(migration.settings.countryMMDBURL.hasSuffix("country.mmdb"))
        XCTAssertTrue(migration.settings.asnMMDBURL.hasSuffix("GeoLite2-ASN.mmdb"))
        XCTAssertTrue(migration.settings.snifferManagedByApp)
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v6：") })
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v7：") })
    }

    func testV6MigrationAddsIndependentDirectDelayTestURL() throws {
        var version6 = AppSettings.default
        version6.settingsSchemaVersion = 6
        version6.delayTestURL = "https://proxy.example.com/generate_204"
        version6.directDelayTestURL = ""

        let migration = try XCTUnwrap(SettingsMigrator.migration(for: version6))

        XCTAssertEqual(migration.settings.settingsSchemaVersion, 7)
        XCTAssertEqual(migration.settings.delayTestURL, "https://proxy.example.com/generate_204")
        XCTAssertEqual(migration.settings.directDelayTestURL, AppSettings.default.directDelayTestURL)
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v7：") })
    }
}
