import Foundation

extension AppStore {
    func migrateSettingsIfNeeded() throws {
        let currentVersion = settings.settingsSchemaVersion
        guard currentVersion < AppSettings.default.settingsSchemaVersion else {
            settingsMigrationLog = ["设置结构 v\(currentVersion) 已是最新。"]
            return
        }

        let backup = settings
        var migrated = settings
        var log: [String] = []
        log.append("发现设置结构 v\(currentVersion)，准备迁移到 v\(AppSettings.default.settingsSchemaVersion)。")

        if currentVersion < 2 {
            migrated.managedCoreEnabled = migrated.coreSource == .managed
            migrated.settingsSchemaVersion = 2
            log.append("v2：写入 settingsSchemaVersion，并同步 coreSource 与 managedCoreEnabled。")
        }

        do {
            settings = migrated
            try profileStore.saveSettings(migrated)
            settingsMigrationLog = log + ["迁移完成，已保存设置。"]
            appendLog("info", settingsMigrationLog.joined(separator: " "))
        } catch {
            settings = backup
            settingsMigrationLog = log + ["迁移失败，已回滚内存设置：\(error.localizedDescription)"]
            throw error
        }
    }
}
