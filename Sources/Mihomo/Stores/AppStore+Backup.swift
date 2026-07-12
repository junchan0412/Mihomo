import Foundation

struct BackupSecretChecklistItem: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var isPresent: Bool

    var statusTitle: String {
        isPresent ? "已就绪" : "缺失"
    }
}

extension AppStore {
    func createLocalBackup() {
        do {
            let archive = try backupManager.createLocalArchive()
            backupStatus = "本地备份：\(archive.path)"
            appendLog("info", backupStatus)
        } catch {
            backupStatus = "本地备份失败：\(error.localizedDescription)"
            appendLog("error", backupStatus)
        }
    }

    func restoreLocalBackup(url: URL) async {
        do {
            try backupManager.restoreLocalArchive(url)
            try reloadPersistentState()
            backupStatus = "已从本地备份恢复：\(url.lastPathComponent)"
            appendLog("info", backupStatus)
        } catch {
            backupStatus = "本地恢复失败：\(error.localizedDescription)"
            appendLog("error", backupStatus)
        }
    }

    func uploadWebDAVBackup() async {
        do {
            let archive = try backupManager.createLocalArchive()
            let target = try await backupManager.uploadWebDAV(
                archive: archive,
                urlString: settings.backupWebDAVURL,
                username: settings.backupWebDAVUsername,
                password: settings.backupWebDAVPassword
            )
            backupStatus = "WebDAV 已上传：\(target)"
            appendLog("info", backupStatus)
        } catch {
            backupStatus = "WebDAV 上传失败：\(error.localizedDescription)"
            appendLog("error", backupStatus)
        }
    }

    func restoreWebDAVBackup() async {
        do {
            let archive = try await backupManager.downloadWebDAV(
                urlString: settings.backupWebDAVURL,
                username: settings.backupWebDAVUsername,
                password: settings.backupWebDAVPassword
            )
            try backupManager.restoreLocalArchive(archive)
            try reloadPersistentState()
            backupStatus = "WebDAV 已恢复：\(archive.lastPathComponent)"
            appendLog("info", backupStatus)
        } catch {
            backupStatus = "WebDAV 恢复失败：\(error.localizedDescription)"
            appendLog("error", backupStatus)
        }
    }

    func uploadGistBackup() async {
        do {
            let payload = try backupManager.encodePayload(makeBackupPayload())
            let gistID = try await backupManager.uploadGist(payload: payload, token: settings.gistToken, gistID: settings.gistID)
            if gistID != settings.gistID {
                var updated = settings
                updated.gistID = gistID
                await saveSettings(updated)
            }
            backupStatus = "Gist 已同步：\(gistID)"
            appendLog("info", backupStatus)
        } catch {
            backupStatus = "Gist 同步失败：\(error.localizedDescription)"
            appendLog("error", backupStatus)
        }
    }

    func restoreGistBackup() async {
        do {
            let content = try await backupManager.downloadGist(token: settings.gistToken, gistID: settings.gistID)
            let payload = try backupManager.decodePayload(content)
            try applyBackupPayload(payload)
            backupStatus = "Gist 已恢复：\(payload.createdAt)"
            appendLog("info", backupStatus)
        } catch {
            backupStatus = "Gist 恢复失败：\(error.localizedDescription)"
            appendLog("error", backupStatus)
        }
    }

    func exportPortableSecrets(to url: URL, passphrase: String) {
        do {
            let bundle = try LocalSecretVault().exportPortableSecrets(passphrase: passphrase)
            try bundle.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            backupStatus = "Secret bundle 已导出：\(url.lastPathComponent)"
            appendLog("info", backupStatus)
        } catch {
            backupStatus = "Secret bundle 导出失败：\(error.localizedDescription)"
            appendLog("error", backupStatus)
        }
    }

    func importPortableSecrets(from url: URL, passphrase: String) async {
        do {
            let bundle = try String(contentsOf: url, encoding: .utf8)
            let secrets = try LocalSecretVault().importPortableSecrets(bundle, passphrase: passphrase)
            var updated = settings
            updated.applySecrets(secrets)
            await saveSettings(updated)
            backupStatus = "Secret bundle 已导入：\(url.lastPathComponent)"
            appendLog("info", backupStatus)
        } catch {
            backupStatus = "Secret bundle 导入失败：\(error.localizedDescription)"
            appendLog("error", backupStatus)
        }
    }

    func applyManualSecrets(from draft: AppSettings) {
        let manualSecrets = AppSecretValues(settings: draft)
        let appliedFields = BackupSecretPolicy.manualSecretFieldNames(manualSecrets)
        guard appliedFields.isEmpty == false else {
            backupStatus = "人工输入 Secret 未应用：没有填写 Secret。"
            appendLog("info", backupStatus)
            return
        }

        do {
            settings = BackupSecretPolicy.restoredSettingsByApplyingManualSecrets(
                manualSecrets,
                to: settings
            )
            try profileStore.saveSettings(settings)
            refreshConfigArtifacts()
            backupStatus = "人工输入 Secret 已应用：\(appliedFields.joined(separator: "、"))"
            appendLog("info", backupStatus)
        } catch {
            backupStatus = "人工输入 Secret 应用失败：\(error.localizedDescription)"
            appendLog("error", backupStatus)
        }
    }


    private func reloadPersistentState() throws {
        settings = try profileStore.loadSettings()
        profiles = try profileStore.loadProfiles(settings: settings)
        configFragments = try configFragmentStore.loadFragments()
        disabledRules = try configFragmentStore.loadDisabledRules()
        refreshConfigArtifacts()
    }

    private func makeBackupPayload() throws -> BackupPayload {
        let contents = Dictionary(uniqueKeysWithValues: try profiles.map { profile in
            (profile.fileName, try profileStore.loadProfileStoredContent(profile, settings: settings))
        })
        return BackupPayload(
            createdAt: Date(),
            settings: settings.redactedSecretsForDisk,
            profiles: profiles,
            fragments: configFragments,
            disabledRules: disabledRules.sorted(),
            profileContents: contents
        )
    }

    private func applyBackupPayload(_ payload: BackupPayload) throws {
        try AppPaths.ensureBaseDirectories()
        settings = BackupSecretPolicy.restoredSettings(payload.settings, preservingSecretsFrom: settings)
        profiles = payload.profiles
        configFragments = payload.fragments
        disabledRules = Set(payload.disabledRules)
        try profileStore.saveSettings(settings)
        try profileStore.saveProfiles(profiles)
        try configFragmentStore.saveFragments(configFragments)
        try configFragmentStore.saveDisabledRules(disabledRules)
        try FileManager.default.createDirectory(at: profileStore.profileStorageDirectory(settings: settings), withIntermediateDirectories: true)
        for profile in profiles {
            if let content = payload.profileContents[profile.fileName] {
                try content.write(to: profileStore.profileFile(profile, settings: settings), atomically: true, encoding: .utf8)
            }
        }
        refreshConfigArtifacts()
    }
}

enum BackupSecretPolicy {
    static func restoredSettings(_ restored: AppSettings, preservingSecretsFrom current: AppSettings) -> AppSettings {
        let restoredSecrets = AppSecretValues(settings: restored)
        let currentSecrets = AppSecretValues(settings: current)
        let mergedSecrets = AppSecretValues(
            controllerSecret: restoredSecrets.controllerSecret.isEmpty ? currentSecrets.controllerSecret : restoredSecrets.controllerSecret,
            backupWebDAVPassword: restoredSecrets.backupWebDAVPassword.isEmpty ? currentSecrets.backupWebDAVPassword : restoredSecrets.backupWebDAVPassword,
            gistToken: restoredSecrets.gistToken.isEmpty ? currentSecrets.gistToken : restoredSecrets.gistToken
        )

        var result = restored
        result.applySecrets(mergedSecrets)
        return result
    }

    static func restoredSettingsByApplyingManualSecrets(
        _ manualSecrets: AppSecretValues,
        to current: AppSettings
    ) -> AppSettings {
        let normalized = normalizedManualSecrets(manualSecrets)
        let currentSecrets = AppSecretValues(settings: current)
        let mergedSecrets = AppSecretValues(
            controllerSecret: normalized.controllerSecret.isEmpty ? currentSecrets.controllerSecret : normalized.controllerSecret,
            backupWebDAVPassword: normalized.backupWebDAVPassword.isEmpty ? currentSecrets.backupWebDAVPassword : normalized.backupWebDAVPassword,
            gistToken: normalized.gistToken.isEmpty ? currentSecrets.gistToken : normalized.gistToken
        )

        var result = current
        result.applySecrets(mergedSecrets)
        return result
    }

    static func manualSecretFieldNames(_ manualSecrets: AppSecretValues) -> [String] {
        let normalized = normalizedManualSecrets(manualSecrets)
        var fields: [String] = []
        if normalized.controllerSecret.isEmpty == false {
            fields.append("Controller Secret")
        }
        if normalized.backupWebDAVPassword.isEmpty == false {
            fields.append("WebDAV 密码")
        }
        if normalized.gistToken.isEmpty == false {
            fields.append("Gist Token")
        }
        return fields
    }

    static func secretChecklist(for settings: AppSettings) -> [BackupSecretChecklistItem] {
        secretChecklist(for: AppSecretValues(settings: settings))
    }

    static func secretChecklist(for secrets: AppSecretValues) -> [BackupSecretChecklistItem] {
        let normalized = normalizedManualSecrets(secrets)
        return [
            BackupSecretChecklistItem(
                title: "Controller Secret",
                isPresent: normalized.controllerSecret.isEmpty == false
            ),
            BackupSecretChecklistItem(
                title: "WebDAV 密码",
                isPresent: normalized.backupWebDAVPassword.isEmpty == false
            ),
            BackupSecretChecklistItem(
                title: "Gist Token",
                isPresent: normalized.gistToken.isEmpty == false
            )
        ]
    }

    static func missingSecretFieldNames(for settings: AppSettings) -> [String] {
        secretChecklist(for: settings)
            .filter { $0.isPresent == false }
            .map(\.title)
    }

    private static func normalizedManualSecrets(_ secrets: AppSecretValues) -> AppSecretValues {
        AppSecretValues(
            controllerSecret: secrets.controllerSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            backupWebDAVPassword: secrets.backupWebDAVPassword.trimmingCharacters(in: .whitespacesAndNewlines),
            gistToken: secrets.gistToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
