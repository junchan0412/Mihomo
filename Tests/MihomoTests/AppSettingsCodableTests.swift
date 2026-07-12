import Foundation
import XCTest
@testable import Mihomo

final class AppSettingsCodableTests: XCTestCase {
    func testRoundTripPreservesNonDefaultSettings() throws {
        let profileID = UUID(uuidString: "8C08A1E5-8DF4-48BE-9E15-5503C3176AE6")!
        let settings = AppSettings(
            settingsSchemaVersion: 3,
            mihomoPath: "/opt/mihomo/bin/mihomo",
            coreSource: .local,
            activeProfileID: profileID,
            profileStoragePath: "/Users/test/Profiles",
            controllerHost: "127.0.0.2",
            controllerPort: 19090,
            mixedPort: 17890,
            socksPort: 17891,
            allowLAN: true,
            tunEnabled: true,
            logLevel: "debug",
            autoStartCore: true,
            closeConnectionsOnPolicyChange: false,
            restartCoreOnCrash: false,
            maxCrashRestarts: 5,
            autoRefreshProfiles: true,
            profileRefreshIntervalHours: 6,
            lightweightMode: true,
            restoreSystemProxyOnQuit: false,
            delayTestURL: "https://example.com/generate_204",
            delayTestTimeoutMS: 2500,
            launchAtLogin: true,
            restoreTunOnStop: false,
            profileRefreshMaxConcurrent: 4,
            resourceUpdateMaxConcurrent: 7,
            delayTestConcurrency: 9,
            logRetentionDays: 14,
            logMaxFileSizeMB: 32,
            managedCoreEnabled: false,
            managedCoreDownloadURL: "https://example.com/mihomo.gz",
            managedCoreSHA256: String(repeating: "a", count: 64),
            launchDaemonEnabled: true,
            autoSetSystemDNS: true,
            systemDNSServers: ["9.9.9.9"],
            externalUIEnabled: true,
            externalUIName: "zashboard",
            externalUIDownloadURL: "https://example.com/ui.zip",
            externalUISHA256: String(repeating: "b", count: 64),
            remoteAPIEnabled: true,
            remoteAPIBindAddress: "0.0.0.0",
            controllerSecret: "controller-secret",
            yamlOverrideEnabled: false,
            jsOverrideEnabled: true,
            snifferEnabled: true,
            snifferPorts: "80,443,8443",
            snifferForceDomains: "example.com",
            snifferSkipDomains: "skip.example.com",
            dnsEnhancedMode: "redir-host",
            dnsNameservers: ["https://dns.example.com/dns-query"],
            dnsFallbacks: ["https://fallback.example.com/dns-query"],
            geoIPURL: "https://example.com/geoip.dat",
            geoSiteURL: "https://example.com/geosite.dat",
            geoIPSHA256: String(repeating: "c", count: 64),
            geoSiteSHA256: String(repeating: "d", count: 64),
            backupWebDAVURL: "https://webdav.example.com/mihomo",
            backupWebDAVUsername: "backup-user",
            backupWebDAVPassword: "backup-password",
            gistToken: "gist-token",
            gistID: "gist-id",
            softwareUpdateManifestURL: "https://example.com/latest.json",
            profileEncryptionEnabled: true,
            ageBinaryPath: "/usr/local/bin/age",
            ageKeygenPath: "/usr/local/bin/age-keygen",
            ageIdentityPath: "/Users/test/.config/mihomo/identity.txt",
            ageRecipient: "age1recipient",
            ageDownloadURL: "https://example.com/age.tar.gz",
            ageDownloadSHA256: String(repeating: "e", count: 64)
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
    }

    func testLegacyJSONMissingChecksumFieldsUsesCurrentDefaults() throws {
        let data = Data("""
        {
          "settingsSchemaVersion": 1,
          "mihomoPath": "/usr/local/bin/mihomo",
          "managedCoreEnabled": false,
          "controllerHost": "127.0.0.1",
          "controllerPort": 9090,
          "mixedPort": 7890
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.managedCoreSHA256, AppSettings.default.managedCoreSHA256)
        XCTAssertEqual(decoded.externalUISHA256, AppSettings.default.externalUISHA256)
        XCTAssertEqual(decoded.geoIPSHA256, AppSettings.default.geoIPSHA256)
        XCTAssertEqual(decoded.geoSiteSHA256, AppSettings.default.geoSiteSHA256)
        XCTAssertEqual(decoded.ageDownloadSHA256, AppSettings.default.ageDownloadSHA256)
    }

    func testLegacyManagedCoreEnabledMigratesCoreSource() throws {
        let managedData = Data("""
        {
          "mihomoPath": "/custom/mihomo",
          "managedCoreEnabled": true
        }
        """.utf8)
        let localData = Data("""
        {
          "mihomoPath": "/custom/mihomo",
          "managedCoreEnabled": false
        }
        """.utf8)

        let managed = try JSONDecoder().decode(AppSettings.self, from: managedData)
        let local = try JSONDecoder().decode(AppSettings.self, from: localData)

        XCTAssertEqual(managed.coreSource, .managed)
        XCTAssertTrue(managed.managedCoreEnabled)
        XCTAssertEqual(local.coreSource, .local)
        XCTAssertFalse(local.managedCoreEnabled)
    }

    func testRedactedSecretsForDiskRemovesInlineSecretsBeforeEncoding() throws {
        let settings = AppSettings(
            controllerSecret: "controller-secret",
            backupWebDAVURL: "https://webdav.example.com",
            backupWebDAVUsername: "user",
            backupWebDAVPassword: "webdav-password",
            gistToken: "gist-token",
            gistID: "gist-id"
        )

        let redacted = settings.redactedSecretsForDisk
        let encoded = String(data: try JSONEncoder().encode(redacted), encoding: .utf8) ?? ""

        XCTAssertEqual(redacted.controllerSecret, "")
        XCTAssertEqual(redacted.backupWebDAVPassword, "")
        XCTAssertEqual(redacted.gistToken, "")
        XCTAssertFalse(encoded.contains("controller-secret"))
        XCTAssertFalse(encoded.contains("webdav-password"))
        XCTAssertFalse(encoded.contains("gist-token"))

        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(encoded.utf8))
        XCTAssertEqual(decoded.backupWebDAVURL, "https://webdav.example.com")
        XCTAssertEqual(decoded.gistID, "gist-id")
    }

    func testBackupRestorePolicyPreservesCurrentSecretsForRedactedPayload() {
        let current = AppSettings(
            controllerSecret: "current-controller",
            backupWebDAVPassword: "current-webdav",
            gistToken: "current-gist",
            gistID: "current-gist-id"
        )
        let restored = AppSettings(
            backupWebDAVURL: "https://restored.example.com",
            backupWebDAVUsername: "restored-user",
            gistID: "restored-gist-id"
        ).redactedSecretsForDisk

        let merged = BackupSecretPolicy.restoredSettings(restored, preservingSecretsFrom: current)

        XCTAssertEqual(merged.controllerSecret, "current-controller")
        XCTAssertEqual(merged.backupWebDAVPassword, "current-webdav")
        XCTAssertEqual(merged.gistToken, "current-gist")
        XCTAssertEqual(merged.backupWebDAVURL, "https://restored.example.com")
        XCTAssertEqual(merged.backupWebDAVUsername, "restored-user")
        XCTAssertEqual(merged.gistID, "restored-gist-id")
    }

    func testBackupRestorePolicyUsesInlineSecretsFromLegacyPayload() {
        let current = AppSettings(
            controllerSecret: "current-controller",
            backupWebDAVPassword: "current-webdav",
            gistToken: "current-gist"
        )
        let restored = AppSettings(
            controllerSecret: "legacy-controller",
            backupWebDAVPassword: "legacy-webdav",
            gistToken: "legacy-gist"
        )

        let merged = BackupSecretPolicy.restoredSettings(restored, preservingSecretsFrom: current)

        XCTAssertEqual(merged.controllerSecret, "legacy-controller")
        XCTAssertEqual(merged.backupWebDAVPassword, "legacy-webdav")
        XCTAssertEqual(merged.gistToken, "legacy-gist")
    }

    func testManualSecretRestoreAppliesOnlyFilledFields() {
        let current = AppSettings(
            controllerHost: "127.0.0.2",
            controllerPort: 19090,
            controllerSecret: "current-controller",
            backupWebDAVURL: "https://webdav.example.com",
            backupWebDAVPassword: "current-webdav",
            gistToken: "current-gist"
        )
        let manual = AppSecretValues(
            controllerSecret: "  manual-controller  ",
            backupWebDAVPassword: "   ",
            gistToken: "manual-gist\n"
        )

        let merged = BackupSecretPolicy.restoredSettingsByApplyingManualSecrets(manual, to: current)
        let fields = BackupSecretPolicy.manualSecretFieldNames(manual)

        XCTAssertEqual(merged.controllerHost, "127.0.0.2")
        XCTAssertEqual(merged.controllerPort, 19090)
        XCTAssertEqual(merged.backupWebDAVURL, "https://webdav.example.com")
        XCTAssertEqual(merged.controllerSecret, "manual-controller")
        XCTAssertEqual(merged.backupWebDAVPassword, "current-webdav")
        XCTAssertEqual(merged.gistToken, "manual-gist")
        XCTAssertEqual(fields, ["Controller Secret", "Gist Token"])
    }

    func testSecretChecklistReportsPresentAndMissingFieldsWithoutValues() {
        let settings = AppSettings(
            controllerSecret: "controller-secret",
            backupWebDAVPassword: "   ",
            gistToken: "gist-token"
        )

        let checklist = BackupSecretPolicy.secretChecklist(for: settings)
        let byTitle = Dictionary(uniqueKeysWithValues: checklist.map { ($0.title, $0) })

        XCTAssertEqual(checklist.count, 3)
        XCTAssertEqual(byTitle["Controller Secret"]?.isPresent, true)
        XCTAssertEqual(byTitle["Controller Secret"]?.statusTitle, "已就绪")
        XCTAssertEqual(byTitle["WebDAV 密码"]?.isPresent, false)
        XCTAssertEqual(byTitle["WebDAV 密码"]?.statusTitle, "缺失")
        XCTAssertEqual(byTitle["Gist Token"]?.isPresent, true)
        XCTAssertEqual(BackupSecretPolicy.missingSecretFieldNames(for: settings), ["WebDAV 密码"])
    }
}
