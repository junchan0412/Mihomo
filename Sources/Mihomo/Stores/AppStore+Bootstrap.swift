import AppKit
import Foundation
import MihomoShared

extension AppStore {
    func bootstrap() async {
        do {
            try AppPaths.ensureBaseDirectories()
            settings = try profileStore.loadSettings()
            try migrateSettingsIfNeeded()
            profiles = try profileStore.loadProfiles(settings: settings)
            configFragments = try configFragmentStore.loadFragments()
            configRevisions = try configRevisionStore.loadIndex()
            nodeProviders = try nodeProviderStore.load()
            try importNodeProviders(from: profiles)
            disabledRules = try configFragmentStore.loadDisabledRules()
            providerUpdateHistory = loadProviderUpdateHistory()
            loadPolicyInteractionHistory()
            if settings.activeProfileID == nil {
                settings.activeProfileID = profiles.first?.id
            }
            if let activeProfile {
                try synchronizeAppSettings(from: activeProfile)
            } else {
                try profileStore.saveSettings(settings)
            }
            lastSystemProxySnapshot = systemProxy.loadSnapshot()
            lastSystemDNSSnapshot = systemProxy.loadDNSSnapshot()
            lastTunRecoverySnapshot = tunRecovery.loadSnapshot()
            tunRecoveryStatus = lastTunRecoverySnapshot == nil ? "未捕获 TUN 回滚快照" : "已有 TUN 回滚快照"
            refreshNetworkTakeoverStates(force: true)
            refreshManagedCoreStatus()
            refreshGeoDataStatus()
            do {
                try syncGeoDataToRuntimeDirectory()
            } catch {
                appendLog("warning", "同步 Geo 数据到运行目录失败：\(error.localizedDescription)")
            }
            ageStatus = settings.profileEncryptionEnabled ? "Profile 加密已启用" : "Profile 加密未启用"
            launchDaemonStatus = MihomoHelperConstants.coreLaunchDaemonPlistPath
            helperStatus = helperInstallationDescription
            await resumeHelperRegistrationAfterUpdateIfNeeded()
            refreshConfigArtifacts()
            syncLaunchAtLoginSetting(reportSuccess: false)
            appendLog("info", "已加载 \(profiles.count) 个配置")
            startPolling()
            startProfileAutoRefreshIfNeeded()
            if settings.autoStartCore {
                await startCore()
            }
            if settings.lightweightMode {
                enterLightweightMode()
            }
            await refreshController()
        } catch {
            appendLog("error", "初始化失败：\(error.localizedDescription)")
        }
    }

    func saveSettings(_ settings: AppSettings) async {
        do {
            var normalized = settings
            normalized.managedCoreEnabled = normalized.coreSource == .managed
            normalized.snifferManagedByApp = true
            if normalized.tunEnabled {
                normalized.dnsEnabled = true
            }
            let previous = self.settings
            if previous.notifyProfileRefreshFailures == false,
               normalized.notifyProfileRefreshFailures {
                let authorized = await notificationManager.requestAuthorization()
                if authorized == false {
                    normalized.notifyProfileRefreshFailures = false
                    appendLog("warning", "通知权限未授予；已保持订阅失败通知关闭。")
                }
            }
            let synchronizedProfile = try synchronizeActiveProfileSettings(from: previous, to: normalized)
            if previous.profileEncryptionEnabled != normalized.profileEncryptionEnabled {
                try profileStore.migrateProfileEncryption(profiles, settings: normalized)
            }
            self.settings = normalized
            try profileStore.saveSettings(normalized)
            ageStatus = normalized.profileEncryptionEnabled ? "Profile 加密已启用" : "Profile 加密未启用"
            refreshManagedCoreStatus()
            syncLaunchAtLoginSetting(reportSuccess: true)
            startProfileAutoRefreshIfNeeded()
            refreshConfigArtifacts()
            appendLog("info", synchronizedProfile ? "设置已保存，并同步至当前配置" : "设置已保存")
        } catch {
            appendLog("error", "设置保存失败：\(error.localizedDescription)")
        }
    }

    func enterLightweightMode() {
        isLightweightModeActive = true
        NSApp.hide(nil)
        appendLog("info", "已进入轻量模式，主窗口隐藏，菜单栏保留。")
    }

    private func syncLaunchAtLoginSetting(reportSuccess: Bool) {
        do {
            try loginItem.setEnabled(settings.launchAtLogin)
            loginItemStatus = loginItem.statusDescription
            if reportSuccess {
                appendLog("info", "登录项状态：\(loginItemStatus)")
            }
        } catch {
            loginItemStatus = "登录项设置失败：\(error.localizedDescription)"
            appendLog("error", loginItemStatus)
        }
    }

    private func startProfileAutoRefreshIfNeeded() {
        profileRefreshTask?.cancel()
        guard settings.autoRefreshProfiles, settings.profileRefreshIntervalHours > 0 else {
            profileAutoRefreshStatus = "未启用"
            return
        }

        profileAutoRefreshStatus = "已启用，每 \(settings.profileRefreshIntervalHours) 小时刷新"
        let interval = UInt64(settings.profileRefreshIntervalHours) * 60 * 60 * 1_000_000_000
        profileRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                await self?.refreshAllRemoteSubscriptions()
            }
        }
    }
}
