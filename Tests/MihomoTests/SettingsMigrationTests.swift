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
        XCTAssertEqual(migration.settings.settingsSchemaVersion, 4)
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v3：") })
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v4：") })

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(migration.settings).write(to: settingsFile, options: .atomic)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reloaded = try decoder.decode(AppSettings.self, from: Data(contentsOf: settingsFile))

        XCTAssertEqual(reloaded.settingsSchemaVersion, 4)
        XCTAssertNil(try SettingsMigrator.migration(for: reloaded))
    }

    func testV1SettingsRunEveryMigrationStep() throws {
        var version1 = AppSettings.default
        version1.settingsSchemaVersion = 1
        version1.coreSource = .local
        version1.managedCoreEnabled = true

        let migration = try XCTUnwrap(SettingsMigrator.migration(for: version1))

        XCTAssertEqual(migration.settings.settingsSchemaVersion, 4)
        XCTAssertFalse(migration.settings.managedCoreEnabled)
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v2：") })
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v3：") })
        XCTAssertTrue(migration.log.contains { $0.hasPrefix("v4：") })
    }
}
