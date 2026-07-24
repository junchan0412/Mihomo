import Foundation

final class ProfileStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let runtimeConfigBuilder = RuntimeConfigBuilder()
    private let jsOverrideRunner = JSOverrideRunner()
    private let secretVault = LocalSecretVault()
    private let ageService = ProfileAgeService()
    private let nodeProviderSynchronizer = NodeProviderProfileSynchronizer()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadSettings() throws -> AppSettings {
        try AppPaths.ensureBaseDirectories()
        guard FileManager.default.fileExists(atPath: AppPaths.settingsFile.path) else {
            var settings = AppSettings.default
            settings.mihomoPath = locateMihomoBinary() ?? ""
            try saveSettings(settings)
            return settings
        }
        let data = try Data(contentsOf: AppPaths.settingsFile)
        var settings = try decoder.decode(AppSettings.self, from: data)
        let inlineSecrets = AppSecretValues(settings: settings)
        let vaultSecrets = (try? secretVault.loadSecrets()) ?? .empty

        if inlineSecrets.isEmpty {
            settings.applySecrets(vaultSecrets)
        } else {
            settings.applySecrets(mergedSecrets(inlineSecrets: inlineSecrets, vaultSecrets: vaultSecrets))
            try saveSettings(settings)
        }

        return settings
    }

    func saveSettings(_ settings: AppSettings) throws {
        try AppPaths.ensureBaseDirectories()
        try secretVault.saveSecrets(AppSecretValues(settings: settings))
        let data = try encoder.encode(settings.redactedSecretsForDisk)
        try data.write(to: AppPaths.settingsFile, options: .atomic)
    }

    func profileStorageDirectory(settings: AppSettings = .default) -> URL {
        let value = settings.profileStoragePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else { return AppPaths.profilesDirectory }
        return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
            .standardizedFileURL
    }

    func loadProfiles(settings: AppSettings = .default) throws -> [ProfileItem] {
        try AppPaths.ensureBaseDirectories()
        try ensureProfileStorageDirectory(settings: settings)
        guard FileManager.default.fileExists(atPath: AppPaths.profilesFile.path) else {
            let item = try createDefaultProfile(settings: settings)
            try saveProfiles([item])
            return [item]
        }
        let data = try Data(contentsOf: AppPaths.profilesFile)
        let profiles = try decoder.decode([ProfileItem].self, from: data)
        if profiles.isEmpty {
            let item = try createDefaultProfile(settings: settings)
            try saveProfiles([item])
            return [item]
        }
        return profiles
    }

    func saveProfiles(_ profiles: [ProfileItem]) throws {
        try AppPaths.ensureBaseDirectories()
        let data = try encoder.encode(profiles)
        try data.write(to: AppPaths.profilesFile, options: .atomic)
    }

    func createDefaultProfile(settings: AppSettings = .default) throws -> ProfileItem {
        try ensureProfileStorageDirectory(settings: settings)
        let id = UUID()
        let fileName = "\(id.uuidString).yaml"
        let url = profileStorageDirectory(settings: settings).appendingPathComponent(fileName)
        try defaultProfileYAML.write(to: url, atomically: true, encoding: .utf8)
        return ProfileItem(
            id: id,
            name: "Blank Profile",
            source: .local,
            location: url.path,
            fileName: fileName,
            updatedAt: Date()
        )
    }

    func importLocalProfile(fileURL: URL, name: String? = nil, settings: AppSettings = .default) throws -> ProfileItem {
        try AppPaths.ensureBaseDirectories()
        try ensureProfileStorageDirectory(settings: settings)
        let id = UUID()
        let fileName = "\(id.uuidString).yaml"
        let target = profileStorageDirectory(settings: settings).appendingPathComponent(fileName)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        try writeProfileContent(content, to: target, settings: settings)
        return ProfileItem(
            id: id,
            name: name?.isEmpty == false ? name! : fileURL.deletingPathExtension().lastPathComponent,
            source: .local,
            location: fileURL.path,
            fileName: fileName,
            updatedAt: Date()
        )
    }

    func importRemoteProfile(urlString: String, name: String? = nil, settings: AppSettings = .default) async throws -> ProfileItem {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Mihomo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid subscription URL"])
        }
        let pinningSession = CertificatePinningSession(expectedFingerprint: nil)
        let (data, response, fingerprint) = try await pinningSession.fetch(url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Mihomo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Subscription request failed"])
        }

        let id = UUID()
        let fileName = "\(id.uuidString).yaml"
        try ensureProfileStorageDirectory(settings: settings)
        let target = profileStorageDirectory(settings: settings).appendingPathComponent(fileName)
        let content = try profileString(data: data)
        try writeProfileContent(content, to: target, settings: settings)

        var item = ProfileItem(
            id: id,
            name: name?.isEmpty == false ? name! : url.host ?? "Remote Profile",
            source: .remote,
            location: urlString,
            fileName: fileName,
            updatedAt: Date(),
            certificateFingerprint: fingerprint
        )
        applySubscriptionInfo(response: http, to: &item)
        return item
    }

    func refreshRemoteProfile(_ profile: ProfileItem, settings: AppSettings = .default) async throws -> ProfileItem {
        guard profile.source == .remote, let url = URL(string: profile.location) else {
            return profile
        }
        let pinningSession = CertificatePinningSession(expectedFingerprint: profile.certificateFingerprint)
        let (data, response, fingerprint) = try await pinningSession.fetch(url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Mihomo", code: 3, userInfo: [NSLocalizedDescriptionKey: "Subscription refresh failed"])
        }
        let content = try profileString(data: data)
        let previousContent = try loadProfileContent(profile, settings: settings)
        let preservedContent = try nodeProviderSynchronizer.preservingExistingProviders(
            from: previousContent,
            in: content
        )
        try writeProfileContent(preservedContent, to: profileFile(profile, settings: settings), settings: settings)
        var updated = profile
        updated.updatedAt = Date()
        updated.certificateFingerprint = fingerprint ?? profile.certificateFingerprint
        applySubscriptionInfo(response: http, to: &updated)
        return updated
    }

    func profileFile(_ profile: ProfileItem, settings: AppSettings = .default) -> URL {
        profileStorageDirectory(settings: settings).appendingPathComponent(profile.fileName)
    }

    func loadProfileContent(_ profile: ProfileItem, settings: AppSettings = .default) throws -> String {
        let stored = try loadProfileStoredContent(profile, settings: settings)
        return try ageService.decryptedContent(stored, settings: settings)
    }

    func loadProfileStoredContent(_ profile: ProfileItem, settings: AppSettings = .default) throws -> String {
        try String(contentsOf: profileFile(profile, settings: settings), encoding: .utf8)
    }

    func saveProfileContent(_ profile: ProfileItem, content: String, settings: AppSettings = .default) throws -> ProfileItem {
        try AppPaths.ensureBaseDirectories()
        guard content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw NSError(domain: "Mihomo", code: 4, userInfo: [NSLocalizedDescriptionKey: "Profile content cannot be empty"])
        }

        try writeProfileContent(content, to: profileFile(profile, settings: settings), settings: settings)
        var updated = profile
        updated.updatedAt = Date()
        return updated
    }

    func migrateProfileEncryption(_ profiles: [ProfileItem], settings: AppSettings) throws {
        for profile in profiles {
            let plain = try loadProfileContent(profile, settings: settings)
            try writeProfileContent(plain, to: profileFile(profile, settings: settings), settings: settings)
        }
    }

    func migrateProfileStorage(profiles: [ProfileItem], from oldSettings: AppSettings, to directory: URL) throws {
        try AppPaths.ensureBaseDirectories()
        let targetDirectory = directory.standardizedFileURL
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        for profile in profiles {
            let source = profileFile(profile, settings: oldSettings).standardizedFileURL
            let target = targetDirectory.appendingPathComponent(profile.fileName).standardizedFileURL
            guard source.path != target.path else { continue }
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: source, to: target)
        }
    }

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

    func locateMihomoBinary() -> String? {
        if let bundled = ManagedCoreManager.bundledCorePath,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        let candidates = [
            AppPaths.managedCoreFile.path,
            "/opt/homebrew/bin/mihomo",
            "/usr/local/bin/mihomo",
            "/usr/bin/mihomo",
            "/opt/homebrew/bin/clash",
            "/usr/local/bin/clash"
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        if let result = try? Shell.run("/usr/bin/which", ["mihomo"]), result.status == 0 {
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { return path }
        }
        return nil
    }

    private func applySubscriptionInfo(response: HTTPURLResponse, to item: inout ProfileItem) {
        guard let value = response.value(forHTTPHeaderField: "subscription-userinfo") else { return }
        let pairs = value.split(separator: ";").reduce(into: [String: Int64]()) { result, part in
            let components = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if components.count == 2 {
                result[components[0]] = Int64(components[1])
            }
        }
        item.uploadUsed = pairs["upload"]
        item.downloadUsed = pairs["download"]
        item.total = pairs["total"]
        if let expire = pairs["expire"] {
            item.expireAt = Date(timeIntervalSince1970: TimeInterval(expire))
        }
    }

    private func writeProfileContent(_ content: String, to url: URL, settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stored = try ageService.encryptedContent(content, settings: settings)
        try stored.write(to: url, atomically: true, encoding: .utf8)
    }

    private func ensureProfileStorageDirectory(settings: AppSettings) throws {
        try FileManager.default.createDirectory(
            at: profileStorageDirectory(settings: settings),
            withIntermediateDirectories: true
        )
    }

    private func profileString(data: Data) throws -> String {
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Mihomo", code: 5, userInfo: [NSLocalizedDescriptionKey: "Profile content is not UTF-8 text"])
        }
        return content
    }

    private func mergedSecrets(inlineSecrets: AppSecretValues, vaultSecrets: AppSecretValues) -> AppSecretValues {
        AppSecretValues(
            controllerSecret: inlineSecrets.controllerSecret.isEmpty ? vaultSecrets.controllerSecret : inlineSecrets.controllerSecret,
            backupWebDAVPassword: inlineSecrets.backupWebDAVPassword.isEmpty ? vaultSecrets.backupWebDAVPassword : inlineSecrets.backupWebDAVPassword,
            gistToken: inlineSecrets.gistToken.isEmpty ? vaultSecrets.gistToken : inlineSecrets.gistToken
        )
    }

    private var defaultProfileYAML: String {
        """
        proxies: []
        proxy-groups:
          - name: GLOBAL
            type: select
            proxies:
              - DIRECT
        rules:
          - MATCH,DIRECT
        """
    }
}
