import AppKit
import Foundation
import MihomoShared

extension AppStore {
    func bootstrap() async {
        // Every load is isolated. A single unreadable file used to abort the whole sequence, so a
        // corrupt profiles.json meant polling never started, auto-start never ran and the Geo and
        // helper status stayed blank — with nothing but one log line to explain it.
        bootstrapStep("准备数据目录") { try AppPaths.ensureBaseDirectories() }
        bootstrapStep("读取设置") { settings = try profileStore.loadSettings() }
        bootstrapStep("迁移设置") { try migrateSettingsIfNeeded() }
        bootstrapStep("读取配置列表") { profiles = try profileStore.loadProfiles(settings: settings) }
        bootstrapStep("读取覆写") { configFragments = try configFragmentStore.loadFragments() }
        bootstrapStep("读取版本历史") { configRevisions = try configRevisionStore.loadIndex() }
        bootstrapStep("读取节点提供商") { nodeProviders = try nodeProviderStore.load() }
        bootstrapStep("导入 Profile 节点提供商") { try importNodeProviders(from: profiles) }
        bootstrapStep("读取禁用规则") { disabledRules = try configFragmentStore.loadDisabledRules() }
        providerUpdateHistory = loadProviderUpdateHistory()
        loadPolicyInteractionHistory()

        if settings.activeProfileID == nil {
            settings.activeProfileID = profiles.first?.id
        }
        if let activeProfile {
            bootstrapStep("同步当前配置设置") { try synchronizeAppSettings(from: activeProfile) }
        } else {
            bootstrapStep("保存设置") { try profileStore.saveSettings(settings) }
        }

        lastSystemProxySnapshot = systemProxy.loadSnapshot()
        lastSystemDNSSnapshot = systemProxy.loadDNSSnapshot()
        lastTunRecoverySnapshot = tunRecovery.loadSnapshot()
        tunRecoveryStatus = lastTunRecoverySnapshot == nil ? "未捕获 TUN 回滚快照" : "已有 TUN 回滚快照"
        refreshNetworkTakeoverStates(force: true)
        refreshManagedCoreStatus()
        refreshGeoDataStatus()
        bootstrapStep("同步 Geo 数据到运行目录") { try syncGeoDataToRuntimeDirectory() }

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
    }

    private func bootstrapStep(_ description: String, _ work: () throws -> Void) {
        do {
            try work()
        } catch {
            appendLog("error", "初始化步骤失败（\(description)）：\(error.localizedDescription)")
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
        profileRefreshGeneration = UUID()
        let generation = profileRefreshGeneration
        guard settings.autoRefreshProfiles, settings.profileRefreshIntervalHours > 0 else {
            profileAutoRefreshStatus = "未启用"
            return
        }

        profileAutoRefreshStatus = "已启用，每 \(settings.profileRefreshIntervalHours) 小时刷新"
        let interval = UInt64(settings.profileRefreshIntervalHours) * 60 * 60 * 1_000_000_000
        profileRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      let self,
                      self.profileRefreshGeneration == generation,
                      self.settings.autoRefreshProfiles
                else {
                    return
                }
                await self.refreshAllRemoteSubscriptions()
            }
        }
    }
}
