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

    static var tunRecoverySnapshotFile: URL {
        supportDirectory.appendingPathComponent("tun-recovery-snapshot.json")
    }

    static var appLogFile: URL {
        logsDirectory.appendingPathComponent("mihomo-app.log")
    }

    static func ensureBaseDirectories() throws {
        let manager = FileManager.default
        for directory in [supportDirectory, profilesDirectory, runtimeDirectory, logsDirectory] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
