import Foundation

extension ProfileStore {
    func generateRuntimeConfig(profile: ProfileItem, settings: AppSettings) throws -> URL {
        let candidate = try generateRuntimeConfigCandidate(profile: profile, settings: settings)
        try promoteRuntimeConfig(candidate: candidate)
        return AppPaths.runtimeConfigFile
    }

    func generateRuntimeConfigCandidate(profile: ProfileItem, settings: AppSettings) throws -> URL {
        try generateRuntimeConfigCandidate(profile: profile, settings: settings, fragments: [], disabledRules: [])
    }

    func generateRuntimeConfigCandidate(
        profile: ProfileItem,
        settings: AppSettings,
        fragments: [ConfigFragment],
        disabledRules: Set<String>,
        nodeProviders: [NodeProvider] = []
    ) throws -> URL {
        try AppPaths.ensureBaseDirectories()
        let applicableFragments = fragments.filter { $0.applies(to: profile.id) }
        var profileContent = try loadProfileContent(profile, settings: settings)
        if settings.jsOverrideEnabled {
            profileContent = try jsOverrideRunner.apply(fragments: applicableFragments, to: profileContent)
        }
        let content = try runtimeConfigBuilder.build(
            profileContent: profileContent,
            settings: settings,
            fragments: applicableFragments,
            disabledRules: disabledRules,
            nodeProviders: nodeProviders.filter { $0.applies(to: profile.id) }
        )
        try content.write(to: AppPaths.runtimeCandidateConfigFile, atomically: true, encoding: .utf8)
        return AppPaths.runtimeCandidateConfigFile
    }

    func promoteRuntimeConfig(candidate: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: AppPaths.runtimeConfigFile.path) {
            if manager.fileExists(atPath: AppPaths.runtimeBackupConfigFile.path) {
                try manager.removeItem(at: AppPaths.runtimeBackupConfigFile)
            }
            try manager.copyItem(at: AppPaths.runtimeConfigFile, to: AppPaths.runtimeBackupConfigFile)
        }
        if manager.fileExists(atPath: AppPaths.runtimeConfigFile.path) {
            try manager.removeItem(at: AppPaths.runtimeConfigFile)
        }
        try manager.copyItem(at: candidate, to: AppPaths.runtimeConfigFile)
    }

    func restoreRuntimeBackup() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: AppPaths.runtimeBackupConfigFile.path) else { return }
        if manager.fileExists(atPath: AppPaths.runtimeConfigFile.path) {
            try manager.removeItem(at: AppPaths.runtimeConfigFile)
        }
        try manager.copyItem(at: AppPaths.runtimeBackupConfigFile, to: AppPaths.runtimeConfigFile)
    }
}
