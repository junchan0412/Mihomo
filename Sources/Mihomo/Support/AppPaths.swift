import Foundation

enum AppPaths {
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mihomo", isDirectory: true)
    }

    static var profilesDirectory: URL {
        supportDirectory.appendingPathComponent("Profiles", isDirectory: true)
    }

    static var runtimeDirectory: URL {
        supportDirectory.appendingPathComponent("Runtime", isDirectory: true)
    }

    static var coreDirectory: URL {
        supportDirectory.appendingPathComponent("Core", isDirectory: true)
    }

    static var geoDirectory: URL {
        supportDirectory.appendingPathComponent("Geo", isDirectory: true)
    }

    static var backupsDirectory: URL {
        supportDirectory.appendingPathComponent("Backups", isDirectory: true)
    }

    static var providerBackupsDirectory: URL {
        backupsDirectory.appendingPathComponent("ProviderResources", isDirectory: true)
    }

    static var toolsDirectory: URL {
        supportDirectory.appendingPathComponent("Tools", isDirectory: true)
    }

    static var logsDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Mihomo", isDirectory: true)
    }

    static var settingsFile: URL {
        supportDirectory.appendingPathComponent("settings.json")
    }

    static var profilesFile: URL {
        supportDirectory.appendingPathComponent("profiles.json")
    }

    static var configFragmentsFile: URL {
        supportDirectory.appendingPathComponent("config-fragments.json")
    }

    static var disabledRulesFile: URL {
        supportDirectory.appendingPathComponent("disabled-rules.json")
    }

    static var providerUpdateHistoryFile: URL {
        supportDirectory.appendingPathComponent("provider-update-history.json")
    }

    static var nodeProvidersFile: URL {
        supportDirectory.appendingPathComponent("node-providers.json")
    }

    static var secretVaultFile: URL {
        supportDirectory.appendingPathComponent("secrets.vault")
    }

    static var ageIdentityFile: URL {
        supportDirectory.appendingPathComponent("profile-age-identity.txt")
    }

    static var runtimeConfigFile: URL {
        runtimeDirectory.appendingPathComponent("config.yaml")
    }

    static var runtimeCandidateConfigFile: URL {
        runtimeDirectory.appendingPathComponent("config.candidate.yaml")
    }

    static var runtimeBackupConfigFile: URL {
        runtimeDirectory.appendingPathComponent("config.previous.yaml")
    }

    static var systemProxySnapshotFile: URL {
        supportDirectory.appendingPathComponent("system-proxy-snapshot.json")
    }

    static var systemDNSSnapshotFile: URL {
        supportDirectory.appendingPathComponent("system-dns-snapshot.json")
    }

    static var tunRecoverySnapshotFile: URL {
        supportDirectory.appendingPathComponent("tun-recovery-snapshot.json")
    }

    static var pendingHelperReregistrationFile: URL {
        runtimeDirectory.appendingPathComponent("pending-helper-reregistration.json")
    }

    static var appLogFile: URL {
        logsDirectory.appendingPathComponent("mihomo-app.log")
    }

    static var coreLogFile: URL {
        logsDirectory.appendingPathComponent("mihomo-core.log")
    }

    static var managedCoreFile: URL {
        coreDirectory.appendingPathComponent("mihomo")
    }

    static func rotatedLogFile(prefix: String, date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return logsDirectory.appendingPathComponent("\(prefix)-\(formatter.string(from: date)).log")
    }

    static func ensureBaseDirectories() throws {
        let manager = FileManager.default
        for directory in [supportDirectory, profilesDirectory, runtimeDirectory, coreDirectory, geoDirectory, backupsDirectory, providerBackupsDirectory, toolsDirectory, logsDirectory] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
