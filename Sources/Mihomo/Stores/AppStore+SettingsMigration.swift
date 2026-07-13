import Foundation

struct SettingsMigration {
    var settings: AppSettings
    var log: [String]
}

enum SettingsMigrator {
    static func migration(
        for settings: AppSettings,
        targetVersion: Int = AppSettings.default.settingsSchemaVersion
    ) throws -> SettingsMigration? {
        guard settings.settingsSchemaVersion < targetVersion else { return nil }

        let sourceVersion = settings.settingsSchemaVersion
        var migrated = settings
        var log = ["发现设置结构 v\(sourceVersion)，准备迁移到 v\(targetVersion)。"]

        while migrated.settingsSchemaVersion < targetVersion {
            switch migrated.settingsSchemaVersion {
            case ..<2:
                migrated.managedCoreEnabled = migrated.coreSource == .managed
                migrated.settingsSchemaVersion = 2
                log.append("v2：写入 settingsSchemaVersion，并同步 coreSource 与 managedCoreEnabled。")
            case 2:
                migrated.settingsSchemaVersion = 3
                log.append("v3：升级 settingsSchemaVersion 标记；现有设置无需额外转换。")
            case 3:
                migrated.settingsSchemaVersion = 4
                log.append("v4：加入订阅失败通知偏好与菜单栏速率显示偏好，默认保持非打扰与原有显示行为。")
            case 4:
                let legacyPorts = migrated.snifferPorts.trimmingCharacters(in: .whitespacesAndNewlines)
                migrated.controllerHost = migrated.localControlHost
                migrated.snifferManagedByApp = true
                migrated.snifferHTTPPorts = legacyPorts.isEmpty ? "80,443" : legacyPorts
                migrated.snifferTLSPorts = legacyPorts.isEmpty ? "443" : legacyPorts
                migrated.snifferQUICPorts = ""
                if migrated.remoteAPIEnabled {
                    if migrated.remoteAPIBindAddress == "127.0.0.1" || migrated.remoteAPIBindAddress == "localhost" {
                        migrated.remoteAPIBindAddress = "0.0.0.0"
                    }
                    if migrated.controllerSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        migrated.controllerSecret = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
                    }
                }
                migrated.settingsSchemaVersion = 5
                log.append("v5：本机控制通道改为应用自动管理；域名嗅探升级为按 HTTP、TLS、QUIC 和高级规则配置。")
            case 5:
                migrated.snifferManagedByApp = true
                migrated.settingsSchemaVersion = 6
                log.append("v6：移除 App 内置 External UI 管理，并补齐 Country.mmdb 与 ASN.mmdb 默认 Geo 数据。")
            default:
                throw NSError(
                    domain: "Mihomo.SettingsMigration",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "缺少从 v\(migrated.settingsSchemaVersion) 到 v\(targetVersion) 的设置迁移步骤。"
                    ]
                )
            }
        }

        return SettingsMigration(settings: migrated, log: log)
    }
}

extension AppStore {
    func migrateSettingsIfNeeded() throws {
        let currentVersion = settings.settingsSchemaVersion
        guard currentVersion < AppSettings.default.settingsSchemaVersion else {
            settingsMigrationLog = ["设置结构 v\(currentVersion) 已是最新。"]
            return
        }

        let backup = settings
        var migrationLog = ["发现设置结构 v\(currentVersion)，准备迁移到 v\(AppSettings.default.settingsSchemaVersion)。"]

        do {
            guard let migration = try SettingsMigrator.migration(for: settings) else { return }
            migrationLog = migration.log
            settings = migration.settings
            try profileStore.saveSettings(migration.settings)
            settingsMigrationLog = migrationLog + ["迁移完成，已保存设置。"]
            appendLog("info", settingsMigrationLog.joined(separator: " "))
        } catch {
            settings = backup
            settingsMigrationLog = migrationLog + ["迁移失败，已回滚内存设置：\(error.localizedDescription)"]
            throw error
        }
    }
}
