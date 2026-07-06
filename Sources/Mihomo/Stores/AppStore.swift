import AppKit
import Combine
import Foundation
import MihomoShared

private struct ProviderResourceUpdateResult {
    var provider: ProviderItem
    var download: ProviderResourceDownloadResult?
    var errorMessage: String?
}

@MainActor
final class AppStore: ObservableObject {
    @Published var selectedSection: AppSection = .overview
    @Published var settings = AppSettings.default
    @Published var profiles: [ProfileItem] = []
    @Published var isCoreRunning = false
    @Published var coreStatus = "已停止"
    @Published var coreVersion = "未知"
    @Published var currentMode = "rule"
    @Published var systemProxyEnabled = false
    @Published var proxyGroups: [ProxyGroup] = []
    @Published var connections: [ConnectionItem] = []
    @Published var logs: [LogEntry] = []
    @Published var diagnostics: [DiagnosticResult] = []
    @Published var uploadRate: Int64 = 0
    @Published var downloadRate: Int64 = 0
    @Published var trafficSamples: [TrafficSample] = []
    @Published var newRemoteURL = ""
    @Published var newRemoteName = ""
    @Published var profileAutoRefreshStatus = "未启用"
    @Published var lastRuntimeValidation = ""
    @Published var lastSystemProxySnapshot: SystemProxySnapshot?
    @Published var lastSystemDNSSnapshot: SystemProxySnapshot?
    @Published var lastTunRecoverySnapshot: TunRecoverySnapshot?
    @Published var tunRecoveryStatus = "未捕获 TUN 回滚快照"
    @Published var loginItemStatus = "未检查"
    @Published var profileRefreshQueue: [ProfileRefreshJob] = []
    @Published var profileRefreshFailureCount = 0
    @Published var delayTestStatus = "未运行"
    @Published var delayTestFailureSummary = ""
    @Published var logsPaused = false
    @Published var bufferedLogCount = 0
    @Published var offlineProxyGroups: [ProxyGroup] = []
    @Published var configFragments: [ConfigFragment] = []
    @Published var disabledRules: Set<String> = []
    @Published var rules: [RuleItem] = []
    @Published var providers: [ProviderItem] = []
    @Published var configPreview = ""
    @Published var configDiff = ""
    @Published var providerUpdateHistory: [ProviderUpdateRecord] = []
    @Published var advancedStatus = "高级功能待命"
    @Published var managedCoreStatus = "未托管"
    @Published var externalUIStatus = "未安装"
    @Published var resourceUpdateStatus = "资源未更新"
    @Published var geoUpdateStatus = "未更新"
    @Published var backupStatus = "未备份"
    @Published var ageStatus = "Profile 加密未启用"
    @Published var launchDaemonStatus = "未安装"
    @Published var helperStatus = "Helper 未检查"
    @Published var softwareUpdateStatus = "未检查"
    @Published var availableUpdate: AppUpdateManifest?
    @Published var profileEditorProfileID: UUID?
    @Published var connectionDetailConnectionID: String?
    @Published var policyGroupIconImages: [String: NSImage] = [:]
    @Published var networkTakeoverStates: [NetworkTakeoverState] = []
    @Published var settingsMigrationLog: [String] = []
    @Published var diagnosticExportStatus = "尚未导出诊断包"
    @Published var ruleFocusQuery = ""
    @Published var controllerEventStreamStatus = "轮询"

    private let profileStore = ProfileStore()
    private let systemProxy = SystemProxyManager()
    private let tunRecovery = TunRecoveryManager()
    private let loginItem = LoginItemManager()
    private let notificationManager = NotificationManager()
    private let configFragmentStore = ConfigFragmentStore()
    private let managedCoreManager = ManagedCoreManager()
    private let externalUIManager = ExternalUIManager()
    private let geoUpdateManager = GeoUpdateManager()
    private let backupManager = BackupManager()
    private let profileAgeService = ProfileAgeService()
    private let helperClient = MihomoHelperClient()
    private let helperService = HelperServiceManager()
    private let helperAuditService = HelperAuditService()
    private let softwareUpdateManager = SoftwareUpdateManager()
    private let profileQualityAnalyzer = ProfileQualityAnalyzer()
    private var pollingTask: Task<Void, Never>?
    private var profileRefreshTask: Task<Void, Never>?
    private var profileRefreshQueueRunning = false
    private var lastUploadTotal: Int64?
    private var lastDownloadTotal: Int64?
    private var lastTrafficSampleAt: Date?
    private var isExpectedCoreExit = false
    private var shutdownRequested = false
    private var crashRestartCount = 0
    private var bufferedLogs: [LogEntry] = []
    private var pendingLogEntries: [LogEntry] = []
    private var logFlushTask: Task<Void, Never>?
    private var lastLogPruneAt: Date?
    private var ruleHitBaselines: [String: Int] = [:]
    private var availableUpdateManifestURL: URL?
    private var lastNetworkOperations: [NetworkTakeoverKind: String] = [:]
    private var lastNetworkTakeoverRefreshAt = Date.distantPast
    private var profileStatsCache: [UUID: ProfileStatsCacheEntry] = [:]
    private var profileQualityCache: [UUID: ProfileQualityCacheEntry] = [:]
    private var controllerTrafficStreamTask: Task<Void, Never>?
    private var controllerLogStreamTask: Task<Void, Never>?
    private var controllerConnectionStreamTask: Task<Void, Never>?
    private var controllerEventStreamLastEventAt: Date?

    var activeProfile: ProfileItem? {
        profiles.first { $0.id == settings.activeProfileID } ?? profiles.first
    }

    var effectiveMihomoPath: String {
        let localPath = settings.mihomoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        switch settings.coreSource {
        case .managed:
            if FileManager.default.isExecutableFile(atPath: AppPaths.managedCoreFile.path) {
                return AppPaths.managedCoreFile.path
            }
            if let bundled = ManagedCoreManager.bundledCorePath,
               FileManager.default.isExecutableFile(atPath: bundled) {
                return bundled
            }
            return localPath.isEmpty ? AppPaths.managedCoreFile.path : localPath
        case .bundled:
            return ManagedCoreManager.bundledCorePath ?? ""
        case .local:
            return localPath
        }
    }

    var menuBarTitle: String {
        let state = isCoreRunning ? "开" : "关"
        return "Mihomo \(state) ↓\(Formatters.rate(downloadRate))"
    }

    var currentAppVersion: String {
        softwareUpdateManager.currentVersion
    }

    var softwareUpdateSourceDescription: String {
        "GitHub Releases"
    }

    var softwareUpdateSourceURL: URL {
        SoftwareUpdateManager.githubReleasesPage
    }

    var currentAppBuild: String {
        softwareUpdateManager.currentBuild
    }

    var profileStorageDirectory: URL {
        profileStore.profileStorageDirectory(settings: settings)
    }

    var networkModeAdvisory: String? {
        if settings.tunEnabled && systemProxyEnabled {
            return "TUN 与系统代理被标记为同时开启；下一次切换会自动执行互斥恢复，优先保留最新选择。"
        }
        if settings.tunEnabled && settings.autoSetSystemDNS {
            return "TUN 与系统 DNS 接管同时开启；停止核心时会按设置恢复 DNS/TUN 快照，请确保 Helper 已注册。"
        }
        if systemProxyEnabled && settings.autoSetSystemDNS {
            return "系统代理与系统 DNS 接管同时开启；适合需要 DNS 统一出口的场景，退出前会尝试恢复快照。"
        }
        return nil
    }

    func bootstrap() async {
        do {
            try AppPaths.ensureBaseDirectories()
            settings = try profileStore.loadSettings()
            try migrateSettingsIfNeeded()
            profiles = try profileStore.loadProfiles(settings: settings)
            configFragments = try configFragmentStore.loadFragments()
            disabledRules = try configFragmentStore.loadDisabledRules()
            providerUpdateHistory = loadProviderUpdateHistory()
            if settings.activeProfileID == nil {
                settings.activeProfileID = profiles.first?.id
                try profileStore.saveSettings(settings)
            }
            lastSystemProxySnapshot = systemProxy.loadSnapshot()
            lastSystemDNSSnapshot = systemProxy.loadDNSSnapshot()
            lastTunRecoverySnapshot = tunRecovery.loadSnapshot()
            tunRecoveryStatus = lastTunRecoverySnapshot == nil ? "未捕获 TUN 回滚快照" : "已有 TUN 回滚快照"
            refreshNetworkTakeoverStates(force: true)
            refreshManagedCoreStatus()
            externalUIStatus = externalUIManager.status(name: settings.externalUIName)
            ageStatus = settings.profileEncryptionEnabled ? "Profile 加密已启用" : "Profile 加密未启用"
            launchDaemonStatus = MihomoHelperConstants.coreLaunchDaemonPlistPath
            helperStatus = helperService.statusDescription
            refreshConfigArtifacts()
            syncLaunchAtLoginSetting(reportSuccess: false)
            notificationManager.prepare()
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

    func toggleCore() async {
        isCoreRunning ? await stopCore() : await startCore()
    }

    func startCore() async {
        guard let activeProfile else {
            appendLog("error", "没有可用配置")
            return
        }

        do {
            try await ensureHelperReadyForCoreStart()

            if isCoreRunning {
                isExpectedCoreExit = true
                _ = try? await helperClient.stopCore(restoreDNS: false, restoreTun: false)
                try? await Task.sleep(nanoseconds: 400_000_000)
                isExpectedCoreExit = false
            }

            let mihomoPath = effectiveMihomoPath
            let candidate = try profileStore.generateRuntimeConfigCandidate(
                profile: activeProfile,
                settings: settings,
                fragments: configFragments,
                disabledRules: disabledRules
            )
            try profileStore.promoteRuntimeConfig(candidate: candidate)
            try syncGeoDataToRuntimeDirectory()
            let result = try await runWithGeoDataRetry {
                try await helperClient.prepareAndStartCore(
                    mihomoPath: mihomoPath,
                    configPath: AppPaths.runtimeConfigFile,
                    workDirectory: AppPaths.runtimeDirectory,
                    logPath: AppPaths.coreLogFile,
                    autoSetDNS: settings.autoSetSystemDNS,
                    dnsServers: settings.systemDNSServers,
                    captureTun: settings.tunEnabled
                )
            }
            if let validation = result.payload["validation"], validation.isEmpty == false {
                lastRuntimeValidation = validation
            } else {
                lastRuntimeValidation = "mihomo 配置校验通过"
            }
            if settings.autoSetSystemDNS {
                appendLog("info", "Helper 已临时设置系统 DNS：\(settings.systemDNSServers.joined(separator: "、"))")
                recordNetworkOperation(.systemDNS, result: result)
            }
            if settings.tunEnabled {
                lastTunRecoverySnapshot = tunRecovery.loadSnapshot()
                if let tunDetail = result.payload["tunDetail"], tunDetail.isEmpty == false {
                    tunRecoveryStatus = tunDetail
                } else {
                    tunRecoveryStatus = "Helper 已捕获 TUN 回滚快照"
                }
                appendLog("info", tunRecoveryStatus)
                recordNetworkOperation(.tun, result: result)
            }

            isCoreRunning = true
            coreStatus = "启动中"
            startControllerEventStreams()
            appendLog("info", "\(result.message)：\(AppPaths.runtimeConfigFile.path)")
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshController()
        } catch {
            coreStatus = "启动失败"
            try? profileStore.restoreRuntimeBackup()
            appendLog("error", "启动失败：\(error.localizedDescription)")
        }
        refreshNetworkTakeoverStates(force: true)
    }

    private func ensureHelperReadyForCoreStart() async throws {
        do {
            let result = try await helperClient.version()
            helperStatus = "\(result.message)，\(helperService.statusDescription)"
            return
        } catch {
            helperStatus = "Helper 通信失败，正在重建注册：\(error.localizedDescription)"
            appendLog("warning", helperStatus)
        }

        do {
            do {
                try helperService.unregister()
                appendLog("info", "启动前已移除旧 Helper 注册")
            } catch {
                appendLog("warning", "启动前移除旧 Helper 注册跳过：\(error.localizedDescription)")
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
            try helperService.register()
            helperStatus = helperService.statusDescription
            if helperService.requiresApproval {
                helperService.openLoginItemsSettings()
                throw helperStartupError("Helper 已重新注册，但仍需要在系统设置 > 通用 > 登录项与扩展中允许 Mihomo。")
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            let result = try await helperClient.version()
            helperStatus = "\(result.message)，\(helperService.statusDescription)"
            appendLog("info", "Helper 已恢复通信：\(helperStatus)")
        } catch {
            helperService.openLoginItemsSettings()
            throw helperStartupError("Helper 无法通信，已尝试重建注册：\(error.localizedDescription)")
        }
    }

    func stopCore() async {
        isExpectedCoreExit = true
        do {
            let result = try await helperClient.stopCore(
                restoreDNS: settings.autoSetSystemDNS,
                restoreTun: settings.tunEnabled && settings.restoreTunOnStop
            )
            isCoreRunning = false
            coreStatus = "已停止"
            stopControllerEventStreams(status: "轮询")
            lastSystemProxySnapshot = systemProxy.loadSnapshot()
            lastTunRecoverySnapshot = tunRecovery.loadSnapshot()
            if settings.tunEnabled && settings.restoreTunOnStop {
                tunRecoveryStatus = result.message
                recordNetworkOperation(.tun, result: result)
            } else if settings.autoSetSystemDNS {
                recordNetworkOperation(.systemDNS, result: result)
            }
            appendLog("info", result.message)
        } catch {
            isCoreRunning = false
            coreStatus = "停止失败"
            stopControllerEventStreams(status: "轮询")
            appendLog("error", "Helper 停止核心失败：\(error.localizedDescription)")
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        isExpectedCoreExit = false
        refreshNetworkTakeoverStates(force: true)
    }

    func restartCore() async {
        appendLog("info", "正在重启核心")
        await stopCore()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await startCore()
    }

    func refreshController() async {
        let client = controllerClient()
        do {
            async let version = client.version()
            async let mode = client.configMode()
            async let groups = client.proxyGroups()
            async let connectionResult = client.connections()
            publishIfChanged(\.coreVersion, try await version)
            publishIfChanged(\.currentMode, try await mode)
            let loadedGroups = try await groups
            await preloadPolicyGroupIcons(for: loadedGroups)
            publishIfChanged(\.proxyGroups, loadedGroups)
            let (items, up, down) = try await connectionResult
            let connectionsChanged = connections != items
            publishIfChanged(\.connections, items)
            if connectionsChanged {
                updateRuleProviderHitStatistics()
            }
            updateTrafficRates(uploadTotal: up, downloadTotal: down)
            if isCoreRunning {
                crashRestartCount = 0
                publishIfChanged(\.coreStatus, "运行中")
            }
            refreshNetworkTakeoverStates()
        } catch {
            if isCoreRunning {
                publishIfChanged(\.coreStatus, "控制器不可用")
            }
            refreshNetworkTakeoverStates()
        }
    }

    func setMode(_ mode: String) async {
        do {
            let client = controllerClient()
            try await client.setMode(mode)
            currentMode = mode
            appendLog("info", "出站模式已切换为 \(mode)")
        } catch {
            appendLog("error", "模式切换失败：\(error.localizedDescription)")
        }
    }

    func selectProxy(group: String, proxy: String) async {
        do {
            let client = controllerClient()
            try await client.selectProxy(group: group, proxy: proxy)
            if settings.closeConnectionsOnPolicyChange {
                try? await client.closeConnections()
            }
            appendLog("info", "\(group) 已选择 \(proxy)")
            await refreshController()
        } catch {
            appendLog("error", "策略切换失败：\(error.localizedDescription)")
        }
    }

    func testProxyDelay(group: String, proxy: String) async {
        let urls = normalizedDelayTestURLs
        let timeout = normalizedDelayTestTimeout
        let proxyType = proxyNodeType(group: group, proxy: proxy)
        var failures: [String] = []

        if Self.isRejectProxy(type: proxyType, name: proxy) {
            delayTestStatus = "\(proxy) 不支持延迟测试：REJECT 为主动拒绝出站"
            delayTestFailureSummary = ""
            appendLog("info", delayTestStatus)
            return
        }

        do {
            if Self.isDirectProxy(type: proxyType, name: proxy) {
                let delay = try await Self.measureDirectDelay(urls: urls, timeout: timeout)
                updateDelay(proxy: proxy, delay: delay)
                delayTestStatus = "\(proxy)：\(delay) ms（直连）"
                delayTestFailureSummary = ""
                appendLog("info", "\(proxy) 延迟：\(delay) ms（直连测速）")
                return
            }

            let client = controllerClient()
            for url in urls {
                do {
                    let delay = try await client.proxyDelay(proxy: proxy, url: url, timeout: timeout)
                    updateDelay(proxy: proxy, delay: delay)
                    delayTestStatus = "\(proxy)：\(delay) ms"
                    delayTestFailureSummary = ""
                    appendLog("info", "\(proxy) 延迟：\(delay) ms（\(url)）")
                    return
                } catch {
                    failures.append(error.localizedDescription)
                }
            }
            let message = failures.map(friendlyDelayError).joined(separator: "，")
            throw NSError(domain: "DelayTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        } catch {
            delayTestStatus = "\(proxy) 延迟测试失败：\(friendlyDelayError(error.localizedDescription))"
            delayTestFailureSummary = friendlyDelayError(error.localizedDescription)
            appendLog("error", "\(proxy) 延迟测试失败：\(error.localizedDescription)")
        }
    }

    func testGroupDelay(_ group: ProxyGroup) async {
        let rows = group.all.map { PolicyTableRow(group: group, node: $0) }
        await testPolicyRowsDelay(rows, label: group.name)
    }

    func testAllProxyDelays() async {
        let rows = proxyGroups.flatMap { group in
            group.all.map { PolicyTableRow(group: group, node: $0) }
        }
        await testPolicyRowsDelay(rows, label: "全部策略")
    }

    func closeAllConnections() async {
        do {
            let client = controllerClient()
            try await client.closeConnections()
            connections = []
            appendLog("info", "已关闭所有连接")
        } catch {
            appendLog("error", "关闭连接失败：\(error.localizedDescription)")
        }
    }

    func closeConnection(_ id: String) async {
        do {
            let client = controllerClient()
            try await client.closeConnection(id: id)
            connections.removeAll { $0.id == id }
            appendLog("info", "已关闭连接 \(id)")
        } catch {
            appendLog("error", "关闭连接失败：\(error.localizedDescription)")
        }
    }

    func toggleSystemProxy() async {
        do {
            if systemProxyEnabled {
                let result = try await helperClient.restoreSystemProxy()
                systemProxyEnabled = false
                lastSystemProxySnapshot = systemProxy.loadSnapshot()
                recordNetworkOperation(.systemProxy, result: result)
                appendLog("info", result.message)
            } else {
                if settings.tunEnabled {
                    appendLog("warning", "系统代理与 TUN 互斥：开启系统代理前将关闭 TUN。")
                    await setTunEnabled(false)
                }
                let result = try await helperClient.setSystemProxy(host: "127.0.0.1", mixedPort: settings.mixedPort, socksPort: settings.socksPort)
                systemProxyEnabled = true
                lastSystemProxySnapshot = systemProxy.loadSnapshot()
                recordNetworkOperation(.systemProxy, result: result)
                appendLog("info", result.message)
            }
        } catch {
            appendLog("error", "Helper 系统代理操作失败：\(error.localizedDescription)")
        }
        refreshNetworkTakeoverStates(force: true)
    }

    func setTunEnabled(_ enabled: Bool) async {
        guard settings.tunEnabled != enabled else { return }
        let shouldRestoreTunBeforeDisable = settings.tunEnabled && enabled == false && isCoreRunning && settings.restoreTunOnStop
        if enabled && systemProxyEnabled {
            do {
                appendLog("warning", "TUN 与系统代理互斥：开启 TUN 前将关闭系统代理。")
                let result = try await helperClient.restoreSystemProxy()
                systemProxyEnabled = false
                lastSystemProxySnapshot = systemProxy.loadSnapshot()
                recordNetworkOperation(.systemProxy, result: result)
                appendLog("info", result.message)
            } catch {
                appendLog("error", "关闭系统代理失败，已取消开启 TUN：\(error.localizedDescription)")
                refreshNetworkTakeoverStates(force: true)
                return
            }
        }
        if shouldRestoreTunBeforeDisable {
            do {
                let result = try await helperClient.restoreTunSnapshot()
                tunRecoveryStatus = result.message
                recordNetworkOperation(.tun, result: result)
                appendLog("info", "关闭 TUN 前已恢复路由快照：\(result.message)")
            } catch {
                appendLog("warning", "关闭 TUN 前恢复路由快照失败，将继续重启核心：\(error.localizedDescription)")
            }
        }
        var updated = settings
        updated.tunEnabled = enabled
        await saveSettings(updated)
        if isCoreRunning {
            appendLog("info", "TUN 已\(enabled ? "启用" : "关闭")，正在重启核心使配置生效")
            await restartCore()
        } else {
            appendLog("info", "TUN 已\(enabled ? "启用" : "关闭")，下次启动核心时生效")
        }
        refreshNetworkTakeoverStates(force: true)
    }

    func revealProfileStorageDirectory() {
        let directory = profileStorageDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func changeProfileStorageDirectory(to directory: URL) async {
        do {
            let oldSettings = settings
            try profileStore.migrateProfileStorage(profiles: profiles, from: oldSettings, to: directory)
            var updated = settings
            updated.profileStoragePath = directory.standardizedFileURL.path
            settings = updated
            try profileStore.saveSettings(updated)
            refreshConfigArtifacts()
            appendLog("info", "配置存储路径已切换：\(updated.profileStoragePath)")
        } catch {
            appendLog("error", "配置存储路径切换失败：\(error.localizedDescription)")
        }
    }

    func repairSystemProxy() async {
        do {
            let result = try await helperClient.restoreSystemProxy()
            systemProxyEnabled = false
            lastSystemProxySnapshot = systemProxy.loadSnapshot()
            recordNetworkOperation(.systemProxy, result: result)
            appendLog("info", result.message)
        } catch {
            appendLog("error", "Helper 系统代理修复失败：\(error.localizedDescription)")
        }
        refreshNetworkTakeoverStates(force: true)
    }

    func restoreSystemDNS() async {
        do {
            let result = try await helperClient.restoreSystemDNS()
            recordNetworkOperation(.systemDNS, result: result)
            appendLog("info", result.message)
        } catch {
            appendLog("error", "Helper 系统 DNS 恢复失败：\(error.localizedDescription)")
        }
        refreshNetworkTakeoverStates(force: true)
    }

    func restoreTunRecovery() async {
        do {
            let result = try await helperClient.restoreTunSnapshot()
            lastTunRecoverySnapshot = tunRecovery.loadSnapshot()
            tunRecoveryStatus = result.message
            systemProxyEnabled = false
            lastSystemProxySnapshot = systemProxy.loadSnapshot()
            recordNetworkOperation(.tun, result: result)
            appendLog("info", result.message)
        } catch {
            tunRecoveryStatus = "TUN 回滚失败：\(error.localizedDescription)"
            appendLog("error", tunRecoveryStatus)
        }
        refreshNetworkTakeoverStates(force: true)
    }

    func clearNetworkRecoverySnapshots() {
        do {
            try systemProxy.removeSnapshot(at: AppPaths.systemProxySnapshotFile)
            try systemProxy.removeSnapshot(at: AppPaths.systemDNSSnapshotFile)
            try tunRecovery.clearSnapshot()
            lastSystemProxySnapshot = nil
            lastSystemDNSSnapshot = nil
            lastTunRecoverySnapshot = nil
            tunRecoveryStatus = "已清理 TUN 回滚快照"
            lastNetworkOperations[.systemProxy] = "已清理代理快照"
            lastNetworkOperations[.systemDNS] = "已清理 DNS 快照"
            lastNetworkOperations[.tun] = "已清理 TUN 快照"
            appendLog("info", "已清理网络接管恢复快照")
        } catch {
            appendLog("error", "清理网络快照失败：\(error.localizedDescription)")
        }
        refreshNetworkTakeoverStates(force: true)
    }

    func verifyTunPrivileges() async {
        do {
            let result = try await helperClient.verifyPrivileges()
            appendLog("info", result.message)
            tunRecoveryStatus = result.message
        } catch {
            tunRecoveryStatus = "管理员授权验证失败：\(error.localizedDescription)"
            appendLog("error", tunRecoveryStatus)
        }
    }

    func addRemoteProfile() async {
        let url = newRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        do {
            let item = try await profileStore.importRemoteProfile(
                urlString: url,
                name: newRemoteName.trimmingCharacters(in: .whitespacesAndNewlines),
                settings: settings
            )
            profiles.append(item)
            settings.activeProfileID = item.id
            try profileStore.saveProfiles(profiles)
            try profileStore.saveSettings(settings)
            newRemoteURL = ""
            newRemoteName = ""
            refreshConfigArtifacts()
            appendLog("info", "已导入远程订阅 \(item.name)")
        } catch {
            appendLog("error", "远程订阅导入失败：\(error.localizedDescription)")
        }
    }

    func importLocalProfile(url: URL) async {
        do {
            let item = try profileStore.importLocalProfile(fileURL: url, settings: settings)
            profiles.append(item)
            settings.activeProfileID = item.id
            try profileStore.saveProfiles(profiles)
            try profileStore.saveSettings(settings)
            refreshConfigArtifacts()
            appendLog("info", "已导入本地配置 \(item.name)")
        } catch {
            appendLog("error", "本地配置导入失败：\(error.localizedDescription)")
        }
    }

    func refreshProfile(_ profile: ProfileItem) async {
        do {
            let updated = try await profileStore.refreshRemoteProfile(profile, settings: settings)
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = updated
                try profileStore.saveProfiles(profiles)
            }
            refreshConfigArtifacts()
            appendLog("info", "已刷新配置 \(profile.name)")
        } catch {
            appendLog("error", "配置刷新失败：\(error.localizedDescription)")
        }
    }

    func refreshAllRemoteProfiles() async {
        guard profileRefreshQueueRunning == false else {
            appendLog("warning", "订阅刷新队列已在运行")
            return
        }

        let remoteProfiles = profiles.filter(\.isRemote)
        guard remoteProfiles.isEmpty == false else {
            profileAutoRefreshStatus = "没有远程订阅"
            return
        }

        profileRefreshQueueRunning = true
        defer { profileRefreshQueueRunning = false }

        profileRefreshFailureCount = 0
        profileRefreshQueue = remoteProfiles.map { profile in
            ProfileRefreshJob(
                profileID: profile.id,
                profileName: profile.name,
                state: .pending,
                message: "等待队列执行",
                startedAt: nil,
                finishedAt: nil
            )
        }
        profileAutoRefreshStatus = "队列运行中：0/\(remoteProfiles.count)"

        var pendingProfiles = remoteProfiles
        var runningTasks: [Task<ProfileRefreshResult, Never>] = []
        let maxConcurrent = max(1, settings.profileRefreshMaxConcurrent)
        let refreshSettings = settings
        var completed = 0
        var succeeded = 0
        var failed = 0

        while pendingProfiles.isEmpty == false || runningTasks.isEmpty == false {
            while runningTasks.count < maxConcurrent, pendingProfiles.isEmpty == false {
                let profile = pendingProfiles.removeFirst()
                markRefreshJob(profileID: profile.id, state: .running, message: "正在刷新", startedAt: Date(), finishedAt: nil)
                runningTasks.append(Task {
                    let store = ProfileStore()
                    do {
                        let updated = try await store.refreshRemoteProfile(profile, settings: refreshSettings)
                        return ProfileRefreshResult(profileID: profile.id, updated: updated, errorMessage: nil)
                    } catch {
                        return ProfileRefreshResult(profileID: profile.id, updated: nil, errorMessage: error.localizedDescription)
                    }
                })
            }

            guard runningTasks.isEmpty == false else { break }
            let result = await runningTasks.removeFirst().value
            completed += 1

            if let updated = result.updated {
                if let index = profiles.firstIndex(where: { $0.id == result.profileID }) {
                    profiles[index] = updated
                    try? profileStore.saveProfiles(profiles)
                }
                refreshConfigArtifacts()
                succeeded += 1
                markRefreshJob(profileID: result.profileID, state: .succeeded, message: "刷新成功", finishedAt: Date())
            } else {
                failed += 1
                profileRefreshFailureCount = failed
                let profileName = profileRefreshQueue.first { $0.profileID == result.profileID }?.profileName ?? "订阅"
                let message = result.errorMessage ?? "未知错误"
                markRefreshJob(profileID: result.profileID, state: .failed, message: message, finishedAt: Date())
                notificationManager.notify(title: "订阅刷新失败", body: "\(profileName)：\(message)")
                appendLog("error", "订阅刷新失败 \(profileName)：\(message)")
            }
            profileAutoRefreshStatus = "队列运行中：\(completed)/\(remoteProfiles.count)，成功 \(succeeded)，失败 \(failed)"
        }

        profileAutoRefreshStatus = "上次刷新：\(Formatters.shortDate.string(from: Date()))，成功 \(succeeded)/\(remoteProfiles.count)，失败 \(failed)"
    }

    func setActiveProfile(_ profile: ProfileItem) async {
        settings.activeProfileID = profile.id
        do {
            try profileStore.saveSettings(settings)
            refreshConfigArtifacts()
            appendLog("info", "已启用配置 \(profile.name)")
            if isCoreRunning {
                await restartCore()
            }
        } catch {
            appendLog("error", "配置切换失败：\(error.localizedDescription)")
        }
    }

    func profileContent(for profile: ProfileItem) -> String {
        do {
            return try profileStore.loadProfileContent(profile, settings: settings)
        } catch {
            appendLog("error", "读取配置失败：\(error.localizedDescription)")
            return ""
        }
    }

    func saveProfileEditor(profileID: UUID, name: String, content: String) async {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        do {
            var profile = profiles[index]
            profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? profile.name : name
            let updated = try profileStore.saveProfileContent(profile, content: content, settings: settings)
            profiles[index] = updated
            try profileStore.saveProfiles(profiles)
            refreshConfigArtifacts()
            appendLog("info", "已保存配置 \(updated.name)")
        } catch {
            appendLog("error", "保存配置失败：\(error.localizedDescription)")
        }
    }

    func deleteProfile(_ profile: ProfileItem) async {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        do {
            let file = profileStore.profileFile(profile, settings: settings)
            profiles.remove(at: index)
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            if settings.activeProfileID == profile.id {
                settings.activeProfileID = profiles.first?.id
                try profileStore.saveSettings(settings)
            }
            try profileStore.saveProfiles(profiles)
            if profileEditorProfileID == profile.id {
                profileEditorProfileID = settings.activeProfileID
            }
            refreshConfigArtifacts()
            appendLog("info", "已删除配置 \(profile.name)")
        } catch {
            appendLog("error", "删除配置失败：\(error.localizedDescription)")
        }
    }

    func profileStats(for profile: ProfileItem) -> ProfileStats {
        let fingerprint = profileStatsFingerprint(for: profile)
        if let cached = profileStatsCache[profile.id], cached.fingerprint == fingerprint {
            return cached.stats
        }

        do {
            let content = try profileStore.loadProfileContent(profile, settings: settings)
            let snapshot = try ProfileYAMLStructureEditor().snapshot(content: content)
            let providers = configFragmentStore.parseProviders(profileContent: content)
            let stats = ProfileStats(
                lineCount: content.split(separator: "\n", omittingEmptySubsequences: false).count,
                fileSize: content.data(using: .utf8)?.count ?? 0,
                policyGroupCount: snapshot.groups.count,
                proxyCount: snapshot.proxyNames.count,
                ruleCount: snapshot.rules.count,
                proxyProviderCount: providers.filter { $0.kind == "Proxy" }.count,
                ruleProviderCount: providers.filter { $0.kind == "Rule" }.count,
                errorMessage: nil
            )
            profileStatsCache[profile.id] = ProfileStatsCacheEntry(fingerprint: fingerprint, stats: stats)
            return stats
        } catch {
            let stats = ProfileStats(errorMessage: error.localizedDescription)
            profileStatsCache[profile.id] = ProfileStatsCacheEntry(fingerprint: fingerprint, stats: stats)
            return stats
        }
    }

    func profileQualityReport(for profile: ProfileItem?) -> ProfileQualityReport {
        guard let profile else { return .empty }
        let fingerprint = profileQualityFingerprint(for: profile)
        if let cached = profileQualityCache[profile.id], cached.fingerprint == fingerprint {
            return cached.report
        }

        do {
            let content = try profileStore.loadProfileContent(profile, settings: settings)
            let report = profileQualityAnalyzer.analyze(
                profile: profile,
                profileContent: content,
                settings: settings,
                fragments: configFragments,
                disabledRules: disabledRules,
                migrationLog: settingsMigrationLog
            )
            profileQualityCache[profile.id] = ProfileQualityCacheEntry(fingerprint: fingerprint, report: report)
            return report
        } catch {
            let report = ProfileQualityReport(
                score: 0,
                headline: "配置无法读取",
                issues: [
                    .init(
                        severity: .error,
                        title: "Profile 读取失败",
                        detail: error.localizedDescription
                    )
                ],
                runtimeItems: [],
                sourceItems: [],
                diffLayers: [],
                migrationLog: settingsMigrationLog,
                generatedConfig: ""
            )
            profileQualityCache[profile.id] = ProfileQualityCacheEntry(fingerprint: fingerprint, report: report)
            return report
        }
    }

    private func profileStatsFingerprint(for profile: ProfileItem) -> ProfileStatsFingerprint {
        ProfileStatsFingerprint(
            fileName: profile.fileName,
            location: profile.location,
            updatedAt: profile.updatedAt,
            profileStoragePath: settings.profileStoragePath
        )
    }

    private func profileQualityFingerprint(for profile: ProfileItem) -> ProfileQualityFingerprint {
        ProfileQualityFingerprint(
            profile: profileStatsFingerprint(for: profile),
            settings: settings,
            fragments: configFragments,
            disabledRules: disabledRules,
            migrationLog: settingsMigrationLog
        )
    }

    private func makeOfflineProxyGroups(from snapshot: ProfileStructureSnapshot) -> [ProxyGroup] {
        snapshot.groups.map { group in
            let proxyNodes = group.proxies.map { proxy in
                ProxyNode(name: proxy, type: snapshot.proxyNames.contains(proxy) ? "proxy" : "built-in", delay: nil)
            }
            let providerNodes = group.uses.map { provider in
                ProxyNode(name: provider, type: "provider", delay: nil)
            }
            return ProxyGroup(
                name: group.name,
                type: group.type,
                now: "",
                all: proxyNodes + providerNodes,
                icon: nil
            )
        }
    }

    func saveSettings(_ settings: AppSettings) async {
        do {
            var normalized = settings
            normalized.managedCoreEnabled = normalized.coreSource == .managed
            let previous = self.settings
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
            appendLog("info", "设置已保存")
        } catch {
            appendLog("error", "设置保存失败：\(error.localizedDescription)")
        }
    }

    func runDiagnostics() async {
        var results: [DiagnosticResult] = []
        let mihomoPath = effectiveMihomoPath

        if FileManager.default.isExecutableFile(atPath: mihomoPath) {
            results.append(.init(title: "mihomo 可执行文件", detail: mihomoPath, state: .ok))
            if let version = try? Shell.run(mihomoPath, ["-v"]) {
                let detail = [version.stdout, version.stderr]
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                results.append(.init(title: "mihomo 版本", detail: detail.isEmpty ? "可执行但未返回版本" : detail, state: .ok))
            }
        } else {
            results.append(.init(title: "mihomo 可执行文件", detail: "请在设置中选择可执行文件。", state: .failed))
        }

        if let activeProfile {
            let file = profileStore.profileFile(activeProfile, settings: settings)
            let exists = FileManager.default.fileExists(atPath: file.path)
            results.append(.init(title: "当前配置", detail: exists ? activeProfile.name : "配置文件丢失", state: exists ? .ok : .failed))
            do {
                let candidate = try profileStore.generateRuntimeConfigCandidate(
                    profile: activeProfile,
                    settings: settings,
                    fragments: configFragments,
                    disabledRules: disabledRules
                )
                try syncGeoDataToRuntimeDirectory()
                let result = try await helperClient.validateConfig(mihomoPath: mihomoPath, configPath: candidate, workDirectory: AppPaths.runtimeDirectory)
                results.append(.init(title: "运行配置 dry-run", detail: "\(result.message)：\(candidate.path)", state: .ok))
            } catch {
                results.append(.init(title: "运行配置 dry-run", detail: "Helper 校验失败：\(error.localizedDescription)", state: .failed))
            }
        } else {
            results.append(.init(title: "当前配置", detail: "没有启用的配置。", state: .failed))
        }

        let services = systemProxy.networkServices()
        results.append(.init(
            title: "网络服务",
            detail: services.isEmpty ? "未找到网络服务。" : services.joined(separator: "、"),
            state: services.isEmpty ? .warning : .ok
        ))

        refreshNetworkTakeoverStates(force: true)
        results.append(contentsOf: networkTakeoverStates.map { state in
            DiagnosticResult(
                title: "网络接管：\(state.kind.title)",
                detail: "用户期望：\(state.desiredState)\n系统实际：\(state.actualState)\n最近 Helper 操作：\(state.lastOperation)\n恢复动作：\(state.recoveryAction)",
                state: diagnosticState(for: state.health)
            )
        })

        if let snapshot = systemProxy.loadSnapshot() {
            results.append(.init(
                title: "系统代理快照",
                detail: "已保存 \(snapshot.services.count) 个网络服务在开启系统代理前的代理状态。若系统代理异常、端口残留或被错误关闭，可恢复到保存前的状态；TUN/DNS 回滚不再使用此代理快照。",
                state: .warning
            ))
        } else {
            results.append(.init(title: "系统代理快照", detail: "当前没有待恢复的系统代理快照。", state: .ok))
        }

        results.append(.init(
            title: "登录项",
            detail: "\(loginItem.statusDescription)。\(settings.launchAtLogin ? "设置要求登录后自动打开 Mihomo。" : "设置未要求登录后自动打开。")",
            state: settings.launchAtLogin && loginItem.isEnabled == false ? .warning : .ok
        ))

        if settings.tunEnabled {
            if let snapshot = tunRecovery.loadSnapshot() {
                results.append(.init(
                    title: "TUN 回滚快照",
                    detail: "已保存 \(snapshot.ipv4Routes.count) 条 IPv4 路由、\(snapshot.ipv6Routes.count) 条 IPv6 路由和 \(snapshot.proxySnapshot.services.count) 个网络服务的 DNS 状态。回滚 TUN 不会改动系统代理开关。",
                    state: .ok
                ))
            } else {
                results.append(.init(
                    title: "TUN 回滚快照",
                    detail: "尚未捕获快照。启动 TUN 核心前会自动捕获 DNS 与路由状态。",
                    state: .warning
                ))
            }
            results.append(.init(
                title: "TUN 模式",
                detail: "已写入 mihomo runtime overlay。可通过诊断页验证管理员授权，并在停止/退出或手动操作时回滚 DNS/路由；不会再恢复系统代理快照。",
                state: .ok
            ))
        } else {
            results.append(.init(title: "TUN 模式", detail: "未启用。", state: .ok))
        }

        do {
            let client = controllerClient()
            let version = try await client.version()
            let mode = try await client.configMode()
            results.append(.init(title: "Controller", detail: "已连接，版本 \(version)，模式 \(mode)", state: .ok))
        } catch {
            results.append(.init(title: "Controller", detail: error.localizedDescription, state: isCoreRunning ? .failed : .warning))
        }

        results.append(.init(
            title: "日志文件",
            detail: "App：\(AppPaths.appLogFile.path)\nCore：\(AppPaths.coreLogFile.path)\n保留 \(settings.logRetentionDays) 天，单文件 \(settings.logMaxFileSizeMB) MB。",
            state: .ok
        ))

        results.append(.init(
            title: "订阅自动刷新",
            detail: settings.autoRefreshProfiles ? "\(profileAutoRefreshStatus)，并发 \(settings.profileRefreshMaxConcurrent)，失败通知 \(profileRefreshFailureCount) 条。" : "未启用。",
            state: profileRefreshFailureCount > 0 ? .warning : (settings.autoRefreshProfiles ? .ok : .warning)
        ))

        results.append(.init(
            title: "核心来源",
            detail: "当前来源：\(settings.coreSource.title)\n当前有效路径：\(mihomoPath)\n托管路径：\(AppPaths.managedCoreFile.path)\n内置路径：\(ManagedCoreManager.bundledCorePath ?? "未随包提供")\n本地路径：\(settings.mihomoPath.isEmpty ? "未设置" : settings.mihomoPath)",
            state: FileManager.default.isExecutableFile(atPath: mihomoPath) ? .ok : .failed
        ))

        results.append(contentsOf: helperAuditService.localAuditResults(helperStatus: helperService.statusDescription))
        do {
            let helper = try await helperClient.version()
            helperStatus = "\(helper.message)，\(helperService.statusDescription)"
            results.append(.init(title: "XPC Helper", detail: helperStatus, state: .ok))
            let privilege = try await helperClient.verifyPrivileges()
            results.append(.init(title: "Helper 授权", detail: privilege.message, state: .ok))
        } catch {
            helperStatus = helperTroubleshootingDetail(error.localizedDescription)
            results.append(.init(title: "XPC Helper", detail: helperStatus, state: .failed))
        }

        results.append(.init(
            title: "远程 HTTP API",
            detail: settings.remoteAPIEnabled ? "已显式启用，绑定 \(settings.remoteAPIBindAddress):\(settings.controllerPort)，密钥\(settings.controllerSecret.isEmpty ? "未设置" : "已设置")。" : "默认关闭远程访问，仅绑定 127.0.0.1。",
            state: settings.remoteAPIEnabled && settings.controllerSecret.isEmpty ? .warning : .ok
        ))

        results.append(.init(
            title: "外部 UI",
            detail: externalUIStatus,
            state: settings.externalUIEnabled && externalUIStatus == "未安装" ? .warning : .ok
        ))

        let geoFiles = ["geoip.dat", "geosite.dat"].filter {
            FileManager.default.fileExists(atPath: AppPaths.geoDirectory.appendingPathComponent($0).path)
        }
        results.append(.init(
            title: "Geo 数据",
            detail: geoFiles.isEmpty ? "尚未下载 Geo 数据。" : "已存在：\(geoFiles.joined(separator: "、"))",
            state: geoFiles.isEmpty ? .warning : .ok
        ))

        results.append(.init(
            title: "覆写片段与禁用规则",
            detail: "\(configFragments.count) 个片段，\(disabledRules.count) 条禁用规则。JS 覆写\(settings.jsOverrideEnabled ? "已启用" : "未启用")，YAML 覆写\(settings.yamlOverrideEnabled ? "已启用" : "未启用")。",
            state: .ok
        ))

        diagnostics = results
        selectedSection = .diagnostics
    }

    func exportDiagnosticBundle() {
        do {
            let archive = try makeDiagnosticBundle()
            diagnosticExportStatus = "诊断包已导出：\(archive.path)"
            NSWorkspace.shared.activateFileViewerSelecting([archive])
            appendLog("info", diagnosticExportStatus)
        } catch {
            diagnosticExportStatus = "诊断包导出失败：\(error.localizedDescription)"
            appendLog("error", diagnosticExportStatus)
        }
    }

    func refreshConfigArtifacts() {
        guard let activeProfile else {
            publishIfChanged(\.rules, [])
            publishIfChanged(\.providers, [])
            publishIfChanged(\.offlineProxyGroups, [])
            publishIfChanged(\.configPreview, "")
            publishIfChanged(\.configDiff, "")
            return
        }

        do {
            let original = try profileStore.loadProfileContent(activeProfile, settings: settings)
            let snapshot = try ProfileYAMLStructureEditor().snapshot(content: original)
            publishIfChanged(\.rules, configFragmentStore.parseRules(profileContent: original, disabledRules: disabledRules))
            publishIfChanged(\.providers, configFragmentStore.parseProviders(profileContent: original))
            publishIfChanged(\.offlineProxyGroups, makeOfflineProxyGroups(from: snapshot))
            let candidate = try profileStore.generateRuntimeConfigCandidate(
                profile: activeProfile,
                settings: settings,
                fragments: configFragments,
                disabledRules: disabledRules
            )
            let preview = try String(contentsOf: candidate, encoding: .utf8)
            publishIfChanged(\.configPreview, preview)
            publishIfChanged(\.configDiff, configFragmentStore.makeDiff(original: original, generated: preview))
            updateRuleProviderHitStatistics()
            advancedStatus = "配置预览已更新：\(Formatters.shortDate.string(from: Date()))"
        } catch {
            advancedStatus = "配置预览失败：\(error.localizedDescription)"
            appendLog("error", advancedStatus)
        }
    }

    func preloadPolicyGroupIcons() async {
        await preloadPolicyGroupIcons(for: proxyGroups)
    }

    func refreshProvidersFromController() async {
        do {
            providers = try await controllerClient().providers()
            updateRuleProviderHitStatistics()
            advancedStatus = "已从 Controller 读取 \(providers.count) 个 Provider"
        } catch {
            appendLog("warning", "Controller Provider 读取失败，保留本地解析结果：\(error.localizedDescription)")
            refreshConfigArtifacts()
        }
    }

    func updateProvider(_ provider: ProviderItem) async {
        do {
            try await controllerClient().updateProvider(provider)
            appendLog("info", "已请求更新 \(provider.kind) Provider：\(provider.name)")
            recordProviderUpdate(
                provider,
                action: "Controller",
                succeeded: true,
                targetPath: "-",
                message: "Controller 已接受更新请求"
            )
            await refreshProvidersFromController()
        } catch {
            appendLog("error", "Provider 更新失败：\(error.localizedDescription)")
            recordProviderUpdate(
                provider,
                action: "Controller",
                succeeded: false,
                targetPath: "-",
                message: error.localizedDescription
            )
        }
    }

    func updateProviderResource(_ provider: ProviderItem) async {
        do {
            let result = try await ProviderResourceManager().download(provider)
            let backupSuffix = result.backup.map { "；已备份上一版：\($0.path)" } ?? ""
            resourceUpdateStatus = "\(provider.name) 已更新：\(result.target.path)\(backupSuffix)"
            appendLog("info", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "下载",
                succeeded: true,
                targetPath: result.target.path,
                message: resourceUpdateStatus,
                backupPath: result.backup?.path
            )
            refreshConfigArtifacts()
        } catch {
            resourceUpdateStatus = "\(provider.name) 更新失败：\(error.localizedDescription)"
            appendLog("error", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "下载",
                succeeded: false,
                targetPath: provider.path ?? "-",
                message: error.localizedDescription
            )
        }
    }

    func providerUpdateHistory(for provider: ProviderItem) -> [ProviderUpdateRecord] {
        providerUpdateHistory.filter {
            $0.providerKind == provider.kind && $0.providerName == provider.name
        }
    }

    func latestProviderRollbackRecord(for provider: ProviderItem) -> ProviderUpdateRecord? {
        providerUpdateHistory(for: provider).first { record in
            guard let path = record.backupPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  path.isEmpty == false
            else {
                return false
            }
            return FileManager.default.fileExists(atPath: path)
        }
    }

    func rollbackProviderResource(_ provider: ProviderItem) async {
        guard let record = latestProviderRollbackRecord(for: provider),
              let backupPath = record.backupPath
        else {
            resourceUpdateStatus = "\(provider.name) 没有可用的 Provider 备份。"
            appendLog("warning", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "回滚",
                succeeded: false,
                targetPath: provider.path ?? "-",
                message: resourceUpdateStatus
            )
            return
        }

        do {
            let result = try ProviderResourceManager().rollback(provider, from: URL(fileURLWithPath: backupPath))
            resourceUpdateStatus = "\(provider.name) 已回滚：\(result.restoredFrom.path)"
            appendLog("info", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "回滚",
                succeeded: true,
                targetPath: result.target.path,
                message: resourceUpdateStatus,
                backupPath: result.replacedBackup?.path,
                restoredFromPath: result.restoredFrom.path
            )
            refreshConfigArtifacts()
        } catch {
            resourceUpdateStatus = "\(provider.name) 回滚失败：\(error.localizedDescription)"
            appendLog("error", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "回滚",
                succeeded: false,
                targetPath: provider.path ?? "-",
                message: error.localizedDescription,
                restoredFromPath: backupPath
            )
        }
    }

    func updateAllExternalResources() async {
        refreshConfigArtifacts()
        let providerItems = providers.filter {
            $0.remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        let maxConcurrent = max(1, min(settings.profileRefreshMaxConcurrent, 8))
        var succeeded = 0
        var failed = 0
        var completed = 0

        resourceUpdateStatus = "正在并发更新 \(providerItems.count) 个 Provider（并发 \(maxConcurrent)）与 Geo 数据..."
        for batchStart in stride(from: 0, to: providerItems.count, by: maxConcurrent) {
            let batchEnd = min(batchStart + maxConcurrent, providerItems.count)
            let batch = Array(providerItems[batchStart..<batchEnd])

            await withTaskGroup(of: ProviderResourceUpdateResult.self) { group in
                for provider in batch {
                    group.addTask {
                        do {
                            let result = try await ProviderResourceManager().download(provider)
                            return ProviderResourceUpdateResult(provider: provider, download: result, errorMessage: nil)
                        } catch {
                            return ProviderResourceUpdateResult(provider: provider, download: nil, errorMessage: error.localizedDescription)
                        }
                    }
                }

                for await result in group {
                    completed += 1
                    if let download = result.download {
                        succeeded += 1
                        recordProviderUpdate(
                            result.provider,
                            action: "批量下载",
                            succeeded: true,
                            targetPath: download.target.path,
                            message: download.backup == nil ? "批量更新成功" : "批量更新成功；已备份上一版：\(download.backup?.path ?? "")",
                            backupPath: download.backup?.path
                        )
                    } else {
                        failed += 1
                        let message = result.errorMessage ?? "未知错误"
                        appendLog("error", "\(result.provider.name) 更新失败：\(message)")
                        recordProviderUpdate(
                            result.provider,
                            action: "批量下载",
                            succeeded: false,
                            targetPath: result.provider.path ?? "-",
                            message: message
                        )
                    }
                    resourceUpdateStatus = "Provider 更新 \(completed)/\(providerItems.count)，成功 \(succeeded)，失败 \(failed)..."
                }
            }
        }

        if providerItems.isEmpty {
            resourceUpdateStatus = "没有需要下载的 Provider，正在更新 Geo 数据..."
        }

        do {
            let geoStatus = try await updateGeoDataInternal()
            resourceUpdateStatus = "Provider 成功 \(succeeded)，失败 \(failed)；\(geoStatus)"
        } catch {
            resourceUpdateStatus = "Provider 成功 \(succeeded)，失败 \(failed)；Geo 更新失败：\(error.localizedDescription)"
            appendLog("error", resourceUpdateStatus)
        }
        refreshConfigArtifacts()
        appendLog(failed == 0 ? "info" : "warning", resourceUpdateStatus)
    }

    func focusRule(for connection: ConnectionItem) {
        let query = ruleHitKey(type: connection.ruleType, payload: connection.rulePayload)
        ruleFocusQuery = query.isEmpty ? connection.rule : query
        selectedSection = .rules
        appendLog("info", "从连接跳转到规则：\(ruleFocusQuery)")
    }

    func toggleRuleDisabled(_ rule: RuleItem) {
        if disabledRules.contains(rule.content) {
            disabledRules.remove(rule.content)
        } else {
            disabledRules.insert(rule.content)
        }
        do {
            try configFragmentStore.saveDisabledRules(disabledRules)
            refreshConfigArtifacts()
            appendLog("info", disabledRules.contains(rule.content) ? "已禁用规则 \(rule.index)" : "已启用规则 \(rule.index)")
        } catch {
            appendLog("error", "保存禁用规则失败：\(error.localizedDescription)")
        }
    }

    func upsertActiveProfileRule(originalIndex: Int?, rule: EditableProfileRule) async {
        guard let activeProfile,
              let profileIndex = profiles.firstIndex(where: { $0.id == activeProfile.id })
        else {
            appendLog("error", "没有可编辑的当前配置")
            return
        }

        do {
            let content = try profileStore.loadProfileContent(activeProfile, settings: settings)
            let updatedContent = try ProfileYAMLStructureEditor().upsertRule(
                content: content,
                originalIndex: originalIndex,
                rule: rule
            )
            let updatedProfile = try profileStore.saveProfileContent(activeProfile, content: updatedContent, settings: settings)
            profiles[profileIndex] = updatedProfile
            try profileStore.saveProfiles(profiles)
            refreshConfigArtifacts()
            appendLog("info", originalIndex == nil ? "已添加规则" : "已保存规则 \(originalIndex ?? rule.index)")
        } catch {
            appendLog("error", "规则保存失败：\(error.localizedDescription)")
        }
    }

    func deleteActiveProfileRule(index: Int) async {
        guard let activeProfile,
              let profileIndex = profiles.firstIndex(where: { $0.id == activeProfile.id })
        else {
            appendLog("error", "没有可编辑的当前配置")
            return
        }

        do {
            let removedRule = rules.first { $0.index == index }
            let content = try profileStore.loadProfileContent(activeProfile, settings: settings)
            let updatedContent = try ProfileYAMLStructureEditor().deleteRule(content: content, index: index)
            let updatedProfile = try profileStore.saveProfileContent(activeProfile, content: updatedContent, settings: settings)
            profiles[profileIndex] = updatedProfile
            if let removedRule, disabledRules.remove(removedRule.content) != nil {
                try configFragmentStore.saveDisabledRules(disabledRules)
            }
            try profileStore.saveProfiles(profiles)
            refreshConfigArtifacts()
            appendLog("info", "已删除规则 \(index)")
        } catch {
            appendLog("error", "规则删除失败：\(error.localizedDescription)")
        }
    }

    func resetRuleHitStatistics() {
        ruleHitBaselines = currentRuleHitCounts()
        updateRuleProviderHitStatistics()
        appendLog("info", "规则使用计数已重置")
    }

    func addConfigFragment(name: String, kind: ConfigFragmentKind, content: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.isEmpty == false else { return }
        var fragment = ConfigFragment(
            name: trimmedName.isEmpty ? (kind == .yaml ? "YAML 片段" : "JS 片段") : trimmedName,
            kind: kind,
            enabled: true,
            content: content
        )
        fragment.updatedAt = Date()
        configFragments.append(fragment)
        saveConfigFragments()
    }

    func updateConfigFragment(_ fragment: ConfigFragment) {
        guard let index = configFragments.firstIndex(where: { $0.id == fragment.id }) else { return }
        var updated = fragment
        updated.updatedAt = Date()
        configFragments[index] = updated
        saveConfigFragments()
    }

    func deleteConfigFragment(_ fragment: ConfigFragment) {
        configFragments.removeAll { $0.id == fragment.id }
        saveConfigFragments()
    }

    func installManagedCore() async {
        do {
            managedCoreStatus = "正在下载 mihomo core..."
            let version = try await managedCoreManager.installOrUpdate(from: settings.managedCoreDownloadURL)
            managedCoreStatus = version.isEmpty ? AppPaths.managedCoreFile.path : version
            var updated = settings
            updated.coreSource = .managed
            updated.managedCoreEnabled = true
            await saveSettings(updated)
            appendLog("info", "托管 mihomo core 已更新")
        } catch {
            managedCoreStatus = "核心更新失败：\(error.localizedDescription)"
            appendLog("error", managedCoreStatus)
        }
    }

    func installExternalUI() async {
        do {
            externalUIStatus = "正在下载外部 UI..."
            let path = try await externalUIManager.install(name: settings.externalUIName, from: settings.externalUIDownloadURL)
            externalUIStatus = path
            appendLog("info", "外部 UI 已安装：\(path)")
            refreshConfigArtifacts()
        } catch {
            externalUIStatus = "外部 UI 安装失败：\(error.localizedDescription)"
            appendLog("error", externalUIStatus)
        }
    }

    func updateGeoData() async {
        do {
            geoUpdateStatus = "正在更新 Geo 数据..."
            geoUpdateStatus = try await updateGeoDataInternal()
            appendLog("info", geoUpdateStatus)
        } catch {
            geoUpdateStatus = "Geo 更新失败：\(error.localizedDescription)"
            appendLog("error", geoUpdateStatus)
        }
    }

    func installAgeTools(downloadURL: String? = nil) async {
        do {
            ageStatus = "正在下载 Age 工具"
            let source = downloadURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? downloadURL! : settings.ageDownloadURL
            let tools = try await profileAgeService.installTools(from: source)
            var updated = settings
            updated.ageDownloadURL = source
            updated.ageBinaryPath = tools.agePath
            updated.ageKeygenPath = tools.keygenPath
            try profileStore.saveSettings(updated)
            settings = updated
            ageStatus = "Age 工具已安装：\(tools.agePath)"
            appendLog("info", ageStatus)
        } catch {
            ageStatus = "Age 工具安装失败：\(error.localizedDescription)"
            appendLog("error", ageStatus)
        }
    }

    func generateAgeIdentity(draftSettings: AppSettings? = nil) async {
        do {
            var draft = draftSettings ?? settings
            if draft.ageIdentityPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.ageIdentityPath = AppPaths.ageIdentityFile.path
            }
            let identity = try profileAgeService.ensureIdentity(settings: draft)
            var updated = settings
            updated.ageDownloadURL = draft.ageDownloadURL
            updated.ageBinaryPath = draft.ageBinaryPath
            updated.ageKeygenPath = draft.ageKeygenPath
            updated.ageIdentityPath = identity.identityPath
            updated.ageRecipient = identity.recipient
            try profileStore.saveSettings(updated)
            settings = updated
            ageStatus = "Age 身份已就绪：\(identity.recipient)"
            appendLog("info", ageStatus)
        } catch {
            ageStatus = "Age 身份生成失败：\(error.localizedDescription)"
            appendLog("error", ageStatus)
        }
    }

    func migrateProfileEncryptionNow() async {
        do {
            try profileStore.migrateProfileEncryption(profiles, settings: settings)
            ageStatus = settings.profileEncryptionEnabled ? "现有 Profile 已加密" : "现有 Profile 已解密"
            refreshConfigArtifacts()
            appendLog("info", ageStatus)
        } catch {
            ageStatus = "Profile 加密迁移失败：\(error.localizedDescription)"
            appendLog("error", ageStatus)
        }
    }

    func refreshHelperStatus() async {
        do {
            let result = try await helperClient.version()
            helperStatus = "\(result.message)，\(helperService.statusDescription)"
        } catch {
            helperStatus = "\(helperService.statusDescription)：\(error.localizedDescription)"
        }
    }

    func auditHelper() async {
        var results = helperAuditService.localAuditResults(helperStatus: helperService.statusDescription)
        do {
            let version = try await helperClient.version()
            helperStatus = "\(version.message)，\(helperService.statusDescription)"
            results.append(.init(title: "XPC Helper", detail: helperStatus, state: .ok))
            let privilege = try await helperClient.verifyPrivileges()
            results.append(.init(title: "Helper 授权", detail: privilege.message, state: .ok))
        } catch {
            helperStatus = helperTroubleshootingDetail(error.localizedDescription)
            results.append(.init(title: "XPC Helper", detail: helperStatus, state: .failed))
        }
        diagnostics = results
        selectedSection = .diagnostics
    }

    func registerHelper() async {
        do {
            try helperService.register()
            helperStatus = helperService.statusDescription
            appendLog("info", "XPC Helper 注册请求已提交：\(helperStatus)")
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshHelperStatus()
        } catch {
            helperStatus = "XPC Helper 注册失败：\(error.localizedDescription)"
            appendLog("error", helperStatus)
        }
    }

    func unregisterHelper() async {
        do {
            try helperService.unregister()
            helperStatus = helperService.statusDescription
            appendLog("info", "XPC Helper 已取消注册：\(helperStatus)")
        } catch {
            helperStatus = "XPC Helper 卸载失败：\(error.localizedDescription)"
            appendLog("error", helperStatus)
        }
    }

    func repairHelperRegistration() async {
        helperStatus = "正在重建 Helper 注册"
        appendLog("info", helperStatus)

        do {
            do {
                try helperService.unregister()
                appendLog("info", "XPC Helper 旧注册已移除")
            } catch {
                appendLog("warning", "XPC Helper 取消注册跳过：\(error.localizedDescription)")
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            try helperService.register()
            helperStatus = helperService.statusDescription
            appendLog("info", "XPC Helper 注册已重建：\(helperStatus)")
            if helperService.requiresApproval {
                helperService.openLoginItemsSettings()
                helperStatus = "\(helperStatus)。请在系统设置 > 通用 > 登录项与扩展中允许 Mihomo 后重新运行诊断。"
                appendLog("warning", helperStatus)
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            await auditHelper()
        } catch {
            helperService.openLoginItemsSettings()
            helperStatus = helperTroubleshootingDetail(error.localizedDescription)
            appendLog("error", helperStatus)
            upsertDiagnostic(.init(title: "XPC Helper", detail: helperStatus, state: .failed))
            selectedSection = .diagnostics
        }
    }

    func installLaunchDaemon() async {
        guard let activeProfile else {
            launchDaemonStatus = "没有可用配置"
            return
        }
        do {
            let candidate = try profileStore.generateRuntimeConfigCandidate(
                profile: activeProfile,
                settings: settings,
                fragments: configFragments,
                disabledRules: disabledRules
            )
            try syncGeoDataToRuntimeDirectory()
            try profileStore.promoteRuntimeConfig(candidate: candidate)
            let result = try await runWithGeoDataRetry {
                try await helperClient.installCoreLaunchDaemon(
                    corePath: effectiveMihomoPath,
                    configPath: AppPaths.runtimeConfigFile,
                    workDirectory: AppPaths.runtimeDirectory,
                    logPath: AppPaths.coreLogFile
                )
            }
            launchDaemonStatus = result.payload["path"].map { "已安装：\($0)" } ?? result.message
            var updated = settings
            updated.launchDaemonEnabled = true
            await saveSettings(updated)
            appendLog("info", result.message)
        } catch {
            launchDaemonStatus = "LaunchDaemon 安装失败：\(error.localizedDescription)"
            appendLog("error", launchDaemonStatus)
        }
    }

    func uninstallLaunchDaemon() async {
        do {
            let result = try await helperClient.uninstallCoreLaunchDaemon()
            launchDaemonStatus = result.message
            var updated = settings
            updated.launchDaemonEnabled = false
            await saveSettings(updated)
            appendLog("info", result.message)
        } catch {
            launchDaemonStatus = "LaunchDaemon 卸载失败：\(error.localizedDescription)"
            appendLog("error", launchDaemonStatus)
        }
    }

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

    func checkForSoftwareUpdate() async {
        do {
            softwareUpdateStatus = "正在检查 GitHub Releases..."
            let result = try await softwareUpdateManager.checkForUpdate()
            if result.isNewer {
                availableUpdate = result.manifest
                availableUpdateManifestURL = result.manifestURL
                let build = result.manifest.build.map { " (\($0))" } ?? ""
                softwareUpdateStatus = "发现新版本 \(result.manifest.version)\(build)，当前 \(result.currentVersion) (\(result.currentBuild))"
            } else {
                availableUpdate = nil
                availableUpdateManifestURL = nil
                softwareUpdateStatus = "已是最新版本：\(result.currentVersion) (\(result.currentBuild))"
            }
            appendLog("info", softwareUpdateStatus)
        } catch {
            softwareUpdateStatus = "更新检查失败：\(error.localizedDescription)"
            appendLog("error", softwareUpdateStatus)
        }
    }

    func installSoftwareUpdate() async {
        do {
            let manifest: AppUpdateManifest
            let manifestURL: URL
            if let availableUpdate {
                manifest = availableUpdate
                if let availableUpdateManifestURL {
                    manifestURL = availableUpdateManifestURL
                } else {
                    let result = try await softwareUpdateManager.checkForUpdate()
                    manifestURL = result.manifestURL
                }
            } else {
                let result = try await softwareUpdateManager.checkForUpdate()
                guard result.isNewer else {
                    softwareUpdateStatus = "已是最新：\(result.currentVersion) (\(result.currentBuild))"
                    return
                }
                manifest = result.manifest
                manifestURL = result.manifestURL
                availableUpdate = manifest
                availableUpdateManifestURL = manifestURL
            }

            softwareUpdateStatus = "正在下载 \(manifest.version)"
            let message = try await softwareUpdateManager.installUpdate(manifest, manifestURL: manifestURL)
            softwareUpdateStatus = "\(message) 正在重启..."
            appendLog("info", message)
            try? await Task.sleep(nanoseconds: 500_000_000)
            NSApp.terminate(nil)
        } catch {
            softwareUpdateStatus = "更新安装失败：\(error.localizedDescription)"
            appendLog("error", softwareUpdateStatus)
        }
    }

    func handleDeepLink(_ url: URL) async {
        guard url.scheme == "mihomo" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let command = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        do {
            switch command {
            case "install-profile", "profile":
                guard let value = query["url"], let importURL = URL(string: value) else { return }
                if importURL.isFileURL {
                    let item = try profileStore.importLocalProfile(fileURL: importURL, name: query["name"], settings: settings)
                    profiles.append(item)
                    settings.activeProfileID = item.id
                } else {
                    let item = try await profileStore.importRemoteProfile(urlString: value, name: query["name"], settings: settings)
                    profiles.append(item)
                    settings.activeProfileID = item.id
                }
                try profileStore.saveProfiles(profiles)
                try profileStore.saveSettings(settings)
                refreshConfigArtifacts()
                appendLog("info", "深链已导入配置")
            case "install-fragment", "fragment":
                let kind = ConfigFragmentKind(rawValue: query["kind"] ?? "yaml") ?? .yaml
                let content: String
                if let value = query["content"] {
                    content = value
                } else if let value = query["url"], let remote = URL(string: value) {
                    let (data, _) = try await URLSession.shared.data(from: remote)
                    content = String(data: data, encoding: .utf8) ?? ""
                } else {
                    content = ""
                }
                addConfigFragment(name: query["name"] ?? "", kind: kind, content: content)
                appendLog("info", "深链已导入覆写片段")
            default:
                appendLog("warning", "未知深链命令：\(command)")
            }
        } catch {
            appendLog("error", "深链处理失败：\(error.localizedDescription)")
        }
    }

    func appendLog(_ level: String, _ message: String) {
        guard !message.isEmpty else { return }
        for line in message.split(separator: "\n", omittingEmptySubsequences: true) {
            let entry = LogEntry(level: level, message: String(line))
            persistLog(entry)
            if logsPaused {
                bufferedLogs.append(entry)
                bufferedLogCount = bufferedLogs.count
            } else {
                pendingLogEntries.append(entry)
                scheduleLogFlush()
            }
        }
    }

    private func scheduleLogFlush() {
        guard logFlushTask == nil else { return }
        logFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.flushPendingLogs()
        }
    }

    private func flushPendingLogs() {
        guard pendingLogEntries.isEmpty == false else {
            logFlushTask = nil
            return
        }
        logs.append(contentsOf: pendingLogEntries)
        pendingLogEntries.removeAll()
        pruneVisibleLogs()
        logFlushTask = nil
    }

    private func pruneVisibleLogs() {
        if logs.count > 1_200 {
            logs.removeFirst(logs.count - 1_200)
        }
    }

    func networkTakeoverState(for kind: NetworkTakeoverKind) -> NetworkTakeoverState {
        networkTakeoverStates.first { $0.kind == kind } ?? NetworkTakeoverState(
            kind: kind,
            desiredState: "尚未检查",
            actualState: "尚未检查",
            lastOperation: "无记录",
            recoveryAction: "运行诊断",
            health: .inactive
        )
    }

    var networkSecuritySnapshotItems: [NetworkSecuritySnapshotItem] {
        NetworkSecurityCenter.snapshotItems(
            proxySnapshot: lastSystemProxySnapshot,
            dnsSnapshot: lastSystemDNSSnapshot,
            tunSnapshot: lastTunRecoverySnapshot,
            paths: .init(
                systemProxy: AppPaths.systemProxySnapshotFile.path,
                systemDNS: AppPaths.systemDNSSnapshotFile.path,
                tunRecovery: AppPaths.tunRecoverySnapshotFile.path
            )
        )
    }

    var networkSecurityOverallHealth: NetworkTakeoverHealth {
        NetworkSecurityCenter.overallHealth(for: networkTakeoverStates)
    }

    func refreshNetworkTakeoverStates(force: Bool = false) {
        let now = Date()
        if force == false,
           networkTakeoverStates.isEmpty == false,
           now.timeIntervalSince(lastNetworkTakeoverRefreshAt) < 20 {
            return
        }
        lastNetworkTakeoverRefreshAt = now

        let current = try? systemProxy.captureSnapshot()
        publishIfChanged(\.lastSystemProxySnapshot, systemProxy.loadSnapshot())
        publishIfChanged(\.lastSystemDNSSnapshot, systemProxy.loadDNSSnapshot())
        publishIfChanged(\.lastTunRecoverySnapshot, tunRecovery.loadSnapshot())

        publishIfChanged(\.networkTakeoverStates, [
            systemProxyTakeoverState(current: current),
            systemDNSTakeoverState(current: current),
            tunTakeoverState()
        ])
    }

    private func systemProxyTakeoverState(current: SystemProxySnapshot?) -> NetworkTakeoverState {
        let services = current?.services ?? []
        let matched = services.filter { service in
            let webMatches = service.web.enabled && service.web.server == "127.0.0.1" && service.web.port == settings.mixedPort
            let secureMatches = service.secureWeb.enabled && service.secureWeb.server == "127.0.0.1" && service.secureWeb.port == settings.mixedPort
            let socksMatches = settings.socksPort > 0 && service.socks.enabled && service.socks.server == "127.0.0.1" && service.socks.port == settings.socksPort
            return webMatches || secureMatches || socksMatches
        }
        let desired = systemProxyEnabled ? "期望开启：127.0.0.1:\(settings.mixedPort)" : "期望关闭"
        let actual: String
        if services.isEmpty {
            actual = "未能读取网络服务"
        } else if matched.isEmpty {
            actual = "未检测到 Mihomo 系统代理"
        } else {
            actual = "\(matched.count)/\(services.count) 个服务指向 Mihomo"
        }
        let health: NetworkTakeoverHealth
        if systemProxyEnabled {
            health = matched.isEmpty ? .warning : .ok
        } else {
            health = matched.isEmpty ? .inactive : .warning
        }
        return NetworkTakeoverState(
            kind: .systemProxy,
            desiredState: desired,
            actualState: actual,
            lastOperation: lastNetworkOperations[.systemProxy] ?? "无 Helper 操作记录",
            recoveryAction: lastSystemProxySnapshot == nil ? "关闭残留代理" : "恢复代理快照",
            health: services.isEmpty ? .failed : health
        )
    }

    private func systemDNSTakeoverState(current: SystemProxySnapshot?) -> NetworkTakeoverState {
        let services = current?.services ?? []
        let desiredServers = settings.systemDNSServers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let desired: String
        if settings.autoSetSystemDNS {
            desired = isCoreRunning ? "期望随核心启用：\(desiredServers.joined(separator: ", "))" : "期望下次核心启动时启用"
        } else {
            desired = "期望关闭 App 管理 DNS"
        }
        let matched = services.filter { service in
            guard desiredServers.isEmpty == false else { return false }
            return Set(desiredServers).isSubset(of: Set(service.dnsServers))
        }
        let dnsSnapshot = systemProxy.loadDNSSnapshot()
        let actual: String
        if services.isEmpty {
            actual = "未能读取网络服务"
        } else if settings.autoSetSystemDNS && isCoreRunning {
            actual = matched.isEmpty ? "未检测到 App 临时 DNS" : "\(matched.count)/\(services.count) 个服务使用 App DNS"
        } else if dnsSnapshot != nil {
            actual = "存在待恢复 DNS 快照"
        } else {
            actual = "系统 DNS 由用户或系统管理"
        }
        let health: NetworkTakeoverHealth
        if settings.autoSetSystemDNS && isCoreRunning {
            health = matched.isEmpty ? .warning : .ok
        } else {
            health = dnsSnapshot == nil ? .inactive : .warning
        }
        return NetworkTakeoverState(
            kind: .systemDNS,
            desiredState: desired,
            actualState: actual,
            lastOperation: lastNetworkOperations[.systemDNS] ?? "无 Helper 操作记录",
            recoveryAction: dnsSnapshot == nil ? "无 DNS 快照" : "恢复 DNS 快照",
            health: services.isEmpty ? .failed : health
        )
    }

    private func tunTakeoverState() -> NetworkTakeoverState {
        let snapshot = lastTunRecoverySnapshot
        let routeCount = tunRecovery.currentAddedTunRouteCount()
        let desired: String
        if settings.tunEnabled {
            desired = isCoreRunning ? "期望运行中，并可回滚 DNS/路由" : "期望下次核心启动时启用"
        } else {
            desired = "期望关闭"
        }
        let actual: String
        if let snapshot {
            actual = "已有快照：IPv4 \(snapshot.ipv4Routes.count)，IPv6 \(snapshot.ipv6Routes.count)，新增 utun 路由 \(routeCount)"
        } else if settings.tunEnabled && isCoreRunning {
            actual = "核心运行中，但未发现 TUN 回滚快照"
        } else {
            actual = "未检测到 App TUN 快照"
        }
        let health: NetworkTakeoverHealth
        if settings.tunEnabled && isCoreRunning {
            health = snapshot == nil ? .warning : .ok
        } else {
            health = snapshot == nil ? .inactive : .warning
        }
        return NetworkTakeoverState(
            kind: .tun,
            desiredState: desired,
            actualState: actual,
            lastOperation: lastNetworkOperations[.tun] ?? "无 Helper 操作记录",
            recoveryAction: snapshot == nil ? "无 TUN 快照" : "恢复 TUN 路由与 DNS",
            health: health
        )
    }

    private func recordNetworkOperation(_ kind: NetworkTakeoverKind, result: HelperOperationResult) {
        let steps = result.payload["transactionSteps"]?.replacingOccurrences(of: "\n", with: " / ") ?? ""
        let suggestion = result.payload["rollbackSuggestion"].map { "；建议：\($0)" } ?? ""
        let detail = steps.isEmpty ? result.message : "\(result.message)（\(steps)）"
        lastNetworkOperations[kind] = detail + suggestion
    }

    private func diagnosticState(for health: NetworkTakeoverHealth) -> DiagnosticState {
        switch health {
        case .ok, .inactive:
            return .ok
        case .warning:
            return .warning
        case .failed:
            return .failed
        }
    }

    func setLogsPaused(_ paused: Bool) {
        flushPendingLogs()
        logsPaused = paused
        if paused == false, bufferedLogs.isEmpty == false {
            logs.append(contentsOf: bufferedLogs)
            pruneVisibleLogs()
            bufferedLogs.removeAll()
            bufferedLogCount = 0
        }
        appendLog("info", paused ? "日志流已暂停，仍会继续落盘。" : "日志流已继续。")
    }

    func toggleLogPause() {
        setLogsPaused(!logsPaused)
    }

    func clearVisibleLogs() {
        logs.removeAll()
        pendingLogEntries.removeAll()
        bufferedLogs.removeAll()
        bufferedLogCount = 0
    }

    func enterLightweightMode() {
        NSApp.hide(nil)
        appendLog("info", "已进入轻量模式，主窗口隐藏，菜单栏保留。")
    }

    func refreshManagedCoreStatus() {
        let managedAvailable = FileManager.default.isExecutableFile(atPath: AppPaths.managedCoreFile.path)
        let bundledPath = ManagedCoreManager.bundledCorePath
        let bundledAvailable = bundledPath.map { FileManager.default.isExecutableFile(atPath: $0) } ?? false
        let managedText = managedAvailable ? "托管已安装：\(AppPaths.managedCoreFile.path)" : "托管未安装"
        let bundledText = bundledAvailable ? "内置可用：\(bundledPath ?? "")" : "内置不可用"
        managedCoreStatus = "\(managedText)；\(bundledText)"
    }

    func shutdown() async {
        shutdownRequested = true
        profileRefreshTask?.cancel()
        stopControllerEventStreams(status: "轮询")
        _ = try? await helperClient.stopCore(
            restoreDNS: settings.autoSetSystemDNS || (settings.restoreSystemProxyOnQuit && systemProxyEnabled),
            restoreTun: settings.tunEnabled && settings.restoreTunOnStop
        )
    }

    private func saveConfigFragments() {
        do {
            try configFragmentStore.saveFragments(configFragments)
            refreshConfigArtifacts()
            appendLog("info", "覆写片段已保存")
        } catch {
            appendLog("error", "覆写片段保存失败：\(error.localizedDescription)")
        }
    }

    private func updateGeoDataInternal() async throws -> String {
        let status = try await geoUpdateManager.update(geoIPURL: settings.geoIPURL, geoSiteURL: settings.geoSiteURL)
        try syncGeoDataToRuntimeDirectory()
        geoUpdateStatus = status
        return status
    }

    private func syncGeoDataToRuntimeDirectory() throws {
        try AppPaths.ensureBaseDirectories()
        let pairs: [(source: String, targets: [String])] = [
            ("geoip.dat", ["geoip.dat", "GeoIP.dat"]),
            ("geosite.dat", ["geosite.dat", "GeoSite.dat"])
        ]
        for pair in pairs {
            let source = AppPaths.geoDirectory.appendingPathComponent(pair.source)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            for targetName in pair.targets {
                let target = AppPaths.runtimeDirectory.appendingPathComponent(targetName)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: source, to: target)
            }
        }
    }

    private func runWithGeoDataRetry<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            guard isGeoDataFailure(error) else { throw error }
            appendLog("warning", "Geo 数据不可用，正在更新后重试：\(error.localizedDescription)")
            _ = try await updateGeoDataInternal()
            return try await operation()
        }
    }

    private func isGeoDataFailure(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("geosite.dat")
            || message.contains("geoip.dat")
            || message.contains("can't initial geosite")
            || message.contains("can't download geosite")
            || message.contains("geodata")
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
        settings = payload.settings
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

    private func updateRuleProviderHitStatistics() {
        let ruleHits = currentRuleHitCounts()

        let updatedRules = rules.map { rule in
            var updated = rule
            let key = ruleHitKey(content: rule.content)
            let resetBaseline = ruleHitBaselines[key, default: 0]
            updated.hitCount = max(0, ruleHits[key, default: 0] - resetBaseline)
            return updated
        }
        publishIfChanged(\.rules, updatedRules)

        let ruleProviderHits = connections.reduce(into: [String: Int]()) { result, connection in
            guard connection.ruleType.uppercased() == "RULE-SET",
                  connection.rulePayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            else { return }
            result[connection.rulePayload, default: 0] += 1
        }

        let updatedProviders = providers.map { provider in
            var updated = provider
            if provider.kind == "Rule" {
                updated.hitCount = ruleProviderHits[provider.name, default: 0]
            } else if provider.memberNames.isEmpty == false {
                let members = Set(provider.memberNames)
                updated.hitCount = connections.filter { connection in
                    connection.chain
                        .components(separatedBy: " -> ")
                        .contains { members.contains($0) }
                }.count
            }
            return updated
        }
        publishIfChanged(\.providers, updatedProviders)
    }

    private func preloadPolicyGroupIcons(for groups: [ProxyGroup]) async {
        let groupIconPairs = groups.compactMap { group -> (String, String)? in
            guard let icon = group.icon?.trimmingCharacters(in: .whitespacesAndNewlines),
                  icon.isEmpty == false
            else { return nil }
            return (group.id, icon)
        }
        let validIDs = Set(groupIconPairs.map(\.0))
        if policyGroupIconImages.keys.contains(where: { validIDs.contains($0) == false }) {
            policyGroupIconImages = policyGroupIconImages.filter { validIDs.contains($0.key) }
        }

        await withTaskGroup(of: (String, Data?).self) { taskGroup in
            for (groupID, icon) in groupIconPairs where policyGroupIconImages[groupID] == nil {
                taskGroup.addTask {
                    (groupID, await Self.loadPolicyGroupIconData(icon))
                }
            }

            var loadedImages: [String: NSImage] = [:]
            for await (groupID, data) in taskGroup {
                guard let data, let image = NSImage(data: data) else { continue }
                loadedImages[groupID] = image
            }

            if loadedImages.isEmpty == false {
                policyGroupIconImages.merge(loadedImages) { current, _ in current }
            }
        }
    }

    nonisolated private static func loadPolicyGroupIconData(_ icon: String) async -> Data? {
        if let url = URL(string: icon), url.scheme?.hasPrefix("http") == true {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 8
            guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
            return data
        }
        return try? Data(contentsOf: URL(fileURLWithPath: (icon as NSString).expandingTildeInPath))
    }

    private func currentRuleHitCounts() -> [String: Int] {
        connections.reduce(into: [String: Int]()) { result, connection in
            let key = ruleHitKey(type: connection.ruleType, payload: connection.rulePayload)
            guard key.isEmpty == false else { return }
            result[key, default: 0] += 1
        }
    }

    private func ruleHitKey(content: String) -> String {
        let parts = content.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.isEmpty == false else { return "" }
        if parts[0].uppercased() == "MATCH" {
            return "MATCH"
        }
        if parts.count >= 2 {
            return ruleHitKey(type: parts[0], payload: parts[1])
        }
        return parts[0].uppercased()
    }

    private func ruleHitKey(type: String, payload: String) -> String {
        let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedType.isEmpty == false else { return "" }
        return normalizedPayload.isEmpty ? normalizedType : "\(normalizedType),\(normalizedPayload)"
    }

    private func controllerClient() -> MihomoControllerClient {
        MihomoControllerClient(
            host: settings.controllerHost,
            port: settings.controllerPort,
            secret: settings.controllerSecret
        )
    }

    private func controllerEventStreamClient() -> MihomoControllerEventStream {
        MihomoControllerEventStream(
            host: settings.controllerHost,
            port: settings.controllerPort,
            secret: settings.controllerSecret
        )
    }

    private func publishIfChanged<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppStore, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
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

    private func handleCoreExit(_ status: Int32) {
        if isExpectedCoreExit || shutdownRequested {
            appendLog("info", "核心已按计划退出")
            return
        }

        isCoreRunning = false
        coreStatus = "异常退出 \(status)"
        stopControllerEventStreams(status: "降级")
        appendLog("warning", "核心异常退出，状态码 \(status)")

        guard settings.restartCoreOnCrash else { return }
        guard crashRestartCount < max(settings.maxCrashRestarts, 0) else {
            appendLog("error", "崩溃恢复已达到上限")
            return
        }

        crashRestartCount += 1
        let attempt = crashRestartCount
        appendLog("warning", "2 秒后尝试第 \(attempt) 次自动恢复")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self?.startCore()
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
                await self?.refreshAllRemoteProfiles()
            }
        }
    }

    private func persistLog(_ entry: LogEntry) {
        try? AppPaths.ensureBaseDirectories()
        let line = "\(Formatters.shortDate.string(from: entry.date)) [\(entry.level.uppercased())] \(entry.message)\n"
        writeLogLine(line, to: AppPaths.appLogFile, prefix: "mihomo-app")
        if entry.level.lowercased() == "core" {
            writeLogLine(line, to: AppPaths.coreLogFile, prefix: "mihomo-core")
        }
        pruneOldLogsIfNeeded()
    }

    private func writeLogLine(_ line: String, to url: URL, prefix: String) {
        rotateLogIfNeeded(url: url, prefix: prefix)
        if FileManager.default.fileExists(atPath: url.path) == false {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        handle.write(Data(line.utf8))
    }

    private func rotateLogIfNeeded(url: URL, prefix: String) {
        guard settings.logMaxFileSizeMB > 0,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else { return }

        let maxBytes = Int64(settings.logMaxFileSizeMB) * 1_024 * 1_024
        guard size.int64Value >= maxBytes else { return }
        let rotated = AppPaths.rotatedLogFile(prefix: prefix)
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: url, to: rotated)
    }

    private func pruneOldLogsIfNeeded() {
        let now = Date()
        if let lastLogPruneAt, now.timeIntervalSince(lastLogPruneAt) < 300 {
            return
        }
        lastLogPruneAt = now
        guard settings.logRetentionDays > 0,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: AppPaths.logsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              )
        else { return }

        let cutoff = now.addingTimeInterval(-Double(settings.logRetentionDays) * 24 * 60 * 60)
        for url in urls where url.pathExtension == "log" && url.lastPathComponent.hasPrefix("mihomo-") {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values?.contentModificationDate, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func updateTrafficRates(uploadTotal: Int64, downloadTotal: Int64) {
        let now = Date()
        guard let lastAt = lastTrafficSampleAt,
              let lastUpload = lastUploadTotal,
              let lastDownload = lastDownloadTotal
        else {
            lastTrafficSampleAt = now
            lastUploadTotal = uploadTotal
            lastDownloadTotal = downloadTotal
            publishIfChanged(\.uploadRate, 0)
            publishIfChanged(\.downloadRate, 0)
            if connections.isEmpty == false {
                appendTrafficSampleIfNeeded(uploadRate: 0, downloadRate: 0)
            }
            return
        }

        let interval = max(now.timeIntervalSince(lastAt), 0.1)
        let nextUploadRate = max(0, Int64(Double(uploadTotal - lastUpload) / interval))
        let nextDownloadRate = max(0, Int64(Double(downloadTotal - lastDownload) / interval))
        publishIfChanged(\.uploadRate, nextUploadRate)
        publishIfChanged(\.downloadRate, nextDownloadRate)
        lastTrafficSampleAt = now
        lastUploadTotal = uploadTotal
        lastDownloadTotal = downloadTotal
        appendTrafficSampleIfNeeded(uploadRate: nextUploadRate, downloadRate: nextDownloadRate)
    }

    private func appendTrafficSampleIfNeeded(uploadRate: Int64, downloadRate: Int64) {
        if uploadRate == 0,
           downloadRate == 0,
           connections.isEmpty,
           trafficSamples.last?.uploadRate == 0,
           trafficSamples.last?.downloadRate == 0 {
            return
        }

        var updatedSamples = trafficSamples
        updatedSamples.append(TrafficSample(uploadRate: uploadRate, downloadRate: downloadRate))
        if updatedSamples.count > 120 {
            updatedSamples.removeFirst(updatedSamples.count - 120)
        }
        publishIfChanged(\.trafficSamples, updatedSamples)
    }

    private func updateDelay(group: String, proxy: String, delay: Int) {
        guard let groupIndex = proxyGroups.firstIndex(where: { $0.name == group }),
              let proxyIndex = proxyGroups[groupIndex].all.firstIndex(where: { $0.name == proxy })
        else { return }
        proxyGroups[groupIndex].all[proxyIndex].delay = delay
        proxyGroups = proxyGroups
    }

    private func updateDelay(proxy: String, delay: Int) {
        for groupIndex in proxyGroups.indices {
            for proxyIndex in proxyGroups[groupIndex].all.indices where proxyGroups[groupIndex].all[proxyIndex].name == proxy {
                proxyGroups[groupIndex].all[proxyIndex].delay = delay
            }
        }
        proxyGroups = proxyGroups
    }

    private func testPolicyRowsDelay(_ rows: [PolicyTableRow], label: String) async {
        guard rows.isEmpty == false else {
            delayTestStatus = "没有可测速节点"
            return
        }

        let targets = uniqueDelayTargets(from: rows)
        let maxConcurrent = max(1, settings.delayTestConcurrency)
        var pendingTargets = targets
        var runningTasks: [Task<ProxyDelayResult, Never>] = []
        var completed = 0
        var succeeded = 0
        var failed = 0
        var skipped = 0
        var failureReasons: [String: Int] = [:]
        delayTestFailureSummary = ""
        delayTestStatus = "\(label) 测速开始，节点 \(targets.count)，并发 \(maxConcurrent)"

        while pendingTargets.isEmpty == false || runningTasks.isEmpty == false {
            while runningTasks.count < maxConcurrent, pendingTargets.isEmpty == false {
                let target = pendingTargets.removeFirst()
                let host = settings.controllerHost
                let port = settings.controllerPort
                let secret = settings.controllerSecret
                let urls = normalizedDelayTestURLs
                let timeout = normalizedDelayTestTimeout
                runningTasks.append(Task {
                    if Self.isRejectProxy(type: target.type, name: target.proxy) {
                        return ProxyDelayResult(proxy: target.proxy, delay: nil, errorMessage: nil, skippedMessage: "REJECT 不可测速")
                    }
                    if Self.isDirectProxy(type: target.type, name: target.proxy) {
                        do {
                            let delay = try await Self.measureDirectDelay(urls: urls, timeout: timeout)
                            return ProxyDelayResult(proxy: target.proxy, delay: delay, errorMessage: nil, skippedMessage: nil)
                        } catch {
                            return ProxyDelayResult(proxy: target.proxy, delay: nil, errorMessage: error.localizedDescription, skippedMessage: nil)
                        }
                    }
                    let client = MihomoControllerClient(host: host, port: port, secret: secret)
                    var failures: [String] = []
                    for url in urls {
                        do {
                            let delay = try await client.proxyDelay(proxy: target.proxy, url: url, timeout: timeout)
                            return ProxyDelayResult(proxy: target.proxy, delay: delay, errorMessage: nil, skippedMessage: nil)
                        } catch {
                            failures.append(error.localizedDescription)
                        }
                    }
                    return ProxyDelayResult(proxy: target.proxy, delay: nil, errorMessage: failures.joined(separator: "，"), skippedMessage: nil)
                })
            }

            guard runningTasks.isEmpty == false else { break }
            let result = await runningTasks.removeFirst().value
            completed += 1
            if let delay = result.delay {
                succeeded += 1
                updateDelay(proxy: result.proxy, delay: delay)
            } else if result.skippedMessage != nil {
                skipped += 1
            } else {
                failed += 1
                let reason = friendlyDelayError(result.errorMessage ?? "未知错误")
                failureReasons[reason, default: 0] += 1
            }
            let summary = delayFailureSummary(failureReasons)
            delayTestFailureSummary = summary
            delayTestStatus = "\(label)：\(completed)/\(targets.count)，成功 \(succeeded)，失败 \(failed)，跳过 \(skipped)"
        }

        if failed > 0 {
            appendLog("warning", "\(label) 测速失败原因：\(delayFailureSummary(failureReasons))")
        }
        appendLog("info", "\(label) 测速完成：成功 \(succeeded)，失败 \(failed)，跳过 \(skipped)")
    }

    private var normalizedDelayTestURL: String {
        let value = settings.delayTestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? AppSettings.default.delayTestURL : value
    }

    private var normalizedDelayTestURLs: [String] {
        var seen: Set<String> = []
        var urls: [String] = []
        for url in [normalizedDelayTestURL, AppSettings.default.delayTestURL, "https://www.gstatic.com/generate_204"] {
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false, seen.insert(trimmed).inserted else { continue }
            urls.append(trimmed)
        }
        return urls
    }

    private var normalizedDelayTestTimeout: Int {
        min(max(settings.delayTestTimeoutMS, 3000), 30000)
    }

    private func uniqueDelayTargets(from rows: [PolicyTableRow]) -> [ProxyDelayTarget] {
        var seen: Set<String> = []
        var targets: [ProxyDelayTarget] = []
        for row in rows where seen.contains(row.node.name) == false {
            seen.insert(row.node.name)
            targets.append(ProxyDelayTarget(proxy: row.node.name, type: row.node.type))
        }
        return targets
    }

    private func proxyNodeType(group: String, proxy: String) -> String {
        proxyGroups
            .first { $0.name == group }?
            .all
            .first { $0.name == proxy }?
            .type ?? proxy
    }

    nonisolated private static func isDirectProxy(type: String, name: String) -> Bool {
        type.localizedCaseInsensitiveCompare("direct") == .orderedSame
            || name.localizedCaseInsensitiveCompare("direct") == .orderedSame
    }

    nonisolated private static func isRejectProxy(type: String, name: String) -> Bool {
        type.localizedCaseInsensitiveCompare("reject") == .orderedSame
            || name.localizedCaseInsensitiveCompare("reject") == .orderedSame
    }

    nonisolated private static func measureDirectDelay(urls: [String], timeout: Int) async throws -> Int {
        var failures: [String] = []
        for urlString in urls {
            guard let url = URL(string: urlString) else {
                failures.append("测速 URL 无效")
                continue
            }

            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                request.timeoutInterval = TimeInterval(timeout) / 1000

                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = TimeInterval(timeout) / 1000
                configuration.timeoutIntervalForResource = TimeInterval(timeout) / 1000
                configuration.waitsForConnectivity = false
                configuration.connectionProxyDictionary = [
                    kCFNetworkProxiesHTTPEnable as String: false,
                    kCFNetworkProxiesHTTPSEnable as String: false,
                    kCFNetworkProxiesSOCKSEnable as String: false
                ]

                let session = URLSession(configuration: configuration)
                defer { session.finishTasksAndInvalidate() }
                let startedAt = Date()
                _ = try await session.data(for: request)
                return max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
            } catch {
                failures.append(error.localizedDescription)
            }
        }

        throw NSError(domain: "DirectDelay", code: 1, userInfo: [
            NSLocalizedDescriptionKey: failures.isEmpty ? "DIRECT 直连测速失败" : failures.joined(separator: "，")
        ])
    }

    private func friendlyDelayError(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveContains("timeout") {
            return "超时"
        }
        if trimmed == "An error occurred in the delay test" {
            return "测速 URL 不可达"
        }
        if trimmed.localizedCaseInsensitiveContains("could not resolve host") || trimmed.localizedCaseInsensitiveContains("no such host") {
            return "DNS 解析失败"
        }
        if trimmed.localizedCaseInsensitiveContains("connection refused") {
            return "连接被拒绝"
        }
        if trimmed.localizedCaseInsensitiveContains("unauthorized") || trimmed.localizedCaseInsensitiveContains("401") {
            return "Controller 密钥错误"
        }
        return trimmed.isEmpty ? "未知错误" : trimmed
    }

    private func delayFailureSummary(_ reasons: [String: Int]) -> String {
        guard reasons.isEmpty == false else { return "" }
        return reasons
            .sorted {
                if $0.value == $1.value {
                    return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
                }
                return $0.value > $1.value
            }
            .prefix(3)
            .map { "\($0.key) x\($0.value)" }
            .joined(separator: "，")
    }

    private func helperTroubleshootingDetail(_ errorMessage: String) -> String {
        let status = helperService.statusDescription
        let guidance: String
        if helperService.requiresApproval {
            guidance = "请在系统设置 > 通用 > 登录项与扩展中允许 Mihomo 的后台项目，然后重新运行诊断。"
        } else {
            guidance = "请点击“修复 Helper”重建注册；若系统弹出授权或后台项目提示，请批准后重新运行诊断。"
        }
        return "\(status)：\(errorMessage)\n\(guidance)"
    }

    private func helperStartupError(_ message: String) -> NSError {
        NSError(domain: "MihomoHelperStartup", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func upsertDiagnostic(_ result: DiagnosticResult) {
        if let index = diagnostics.firstIndex(where: { $0.title == result.title }) {
            diagnostics[index] = result
        } else {
            diagnostics.append(result)
        }
    }

    private func markRefreshJob(
        profileID: UUID,
        state: ProfileRefreshJobState,
        message: String,
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        guard let index = profileRefreshQueue.firstIndex(where: { $0.profileID == profileID }) else { return }
        profileRefreshQueue[index].state = state
        profileRefreshQueue[index].message = message
        if let startedAt {
            profileRefreshQueue[index].startedAt = startedAt
        }
        if let finishedAt {
            profileRefreshQueue[index].finishedAt = finishedAt
        }
    }

    private func recordProviderUpdate(
        _ provider: ProviderItem,
        action: String,
        succeeded: Bool,
        targetPath: String,
        message: String,
        backupPath: String? = nil,
        restoredFromPath: String? = nil
    ) {
        providerUpdateHistory.insert(.init(
            providerName: provider.name,
            providerKind: provider.kind,
            action: action,
            succeeded: succeeded,
            targetPath: targetPath,
            message: message,
            backupPath: backupPath,
            restoredFromPath: restoredFromPath
        ), at: 0)
        if providerUpdateHistory.count > 80 {
            providerUpdateHistory.removeLast(providerUpdateHistory.count - 80)
        }
        saveProviderUpdateHistory()
    }

    private func loadProviderUpdateHistory() -> [ProviderUpdateRecord] {
        guard FileManager.default.fileExists(atPath: AppPaths.providerUpdateHistoryFile.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: AppPaths.providerUpdateHistoryFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ProviderUpdateRecord].self, from: data)
        } catch {
            appendLog("warning", "Provider 更新历史读取失败：\(error.localizedDescription)")
            return []
        }
    }

    private func saveProviderUpdateHistory() {
        do {
            try AppPaths.ensureBaseDirectories()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(providerUpdateHistory)
            try data.write(to: AppPaths.providerUpdateHistoryFile, options: .atomic)
        } catch {
            appendLog("warning", "Provider 更新历史保存失败：\(error.localizedDescription)")
        }
    }

    private func makeDiagnosticBundle() throws -> URL {
        try AppPaths.ensureBaseDirectories()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let root = AppPaths.backupsDirectory.appendingPathComponent("Diagnostics-\(stamp)", isDirectory: true)
        let archive = AppPaths.backupsDirectory.appendingPathComponent("Mihomo-Diagnostics-\(stamp).zip")
        let manager = FileManager.default
        if manager.fileExists(atPath: root.path) {
            try manager.removeItem(at: root)
        }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)

        let summary = diagnosticSummaryText()
        try summary.write(to: root.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)

        if manager.fileExists(atPath: AppPaths.runtimeConfigFile.path) {
            try manager.copyItem(at: AppPaths.runtimeConfigFile, to: root.appendingPathComponent("runtime-config.yaml"))
        } else if configPreview.isEmpty == false {
            try configPreview.write(to: root.appendingPathComponent("runtime-config-preview.yaml"), atomically: true, encoding: .utf8)
        }

        let recentLogs = logs.suffix(300)
            .map { "[\(Formatters.shortDate.string(from: $0.date))] \($0.level.uppercased()) \($0.message)" }
            .joined(separator: "\n")
        try recentLogs.write(to: root.appendingPathComponent("app-log-tail.txt"), atomically: true, encoding: .utf8)

        if manager.fileExists(atPath: AppPaths.coreLogFile.path) {
            try? manager.copyItem(at: AppPaths.coreLogFile, to: root.appendingPathComponent("core.log"))
        }

        if manager.fileExists(atPath: archive.path) {
            try manager.removeItem(at: archive)
        }
        let result = try Shell.run("/usr/bin/zip", ["-r", "-X", archive.path, root.lastPathComponent], workDirectory: root.deletingLastPathComponent())
        guard result.status == 0 else {
            throw NSError(domain: "DiagnosticExport", code: Int(result.status), userInfo: [
                NSLocalizedDescriptionKey: result.stderr.isEmpty ? result.stdout : result.stderr
            ])
        }
        try? manager.removeItem(at: root)
        return archive
    }

    private func diagnosticSummaryText() -> String {
        let redactedSettings = settings.redactedSecretsForDisk
        let settingsSummary = """
        coreSource: \(redactedSettings.coreSource.rawValue)
        mixedPort: \(redactedSettings.mixedPort)
        socksPort: \(redactedSettings.socksPort)
        tunEnabled: \(redactedSettings.tunEnabled)
        systemProxyEnabled: \(systemProxyEnabled)
        autoSetSystemDNS: \(redactedSettings.autoSetSystemDNS)
        dnsEnhancedMode: \(redactedSettings.dnsEnhancedMode)
        profileStoragePath: \(profileStorageDirectory.path)
        """
        let networkSummary = networkTakeoverStates.map {
            "- \($0.kind.title): desired=\($0.desiredState); actual=\($0.actualState); health=\($0.health.rawValue); recovery=\($0.recoveryAction)"
        }.joined(separator: "\n")
        let diagnosticSummary = diagnostics.map {
            "- \($0.state.rawValue.uppercased()) \($0.title): \($0.detail)"
        }.joined(separator: "\n")
        let providerSummary = providerUpdateHistory.prefix(30).map {
            let backup = $0.backupPath.map { " backup=\($0)" } ?? ""
            let restored = $0.restoredFromPath.map { " restoredFrom=\($0)" } ?? ""
            return "- \(Formatters.shortDate.string(from: $0.date)) \($0.providerKind) \($0.providerName) \($0.action) \($0.succeeded ? "OK" : "FAIL") path=\($0.targetPath)\(backup)\(restored) message=\($0.message)"
        }.joined(separator: "\n")

        return """
        Mihomo Diagnostic Bundle
        Generated: \(Formatters.shortDate.string(from: Date()))
        App: \(currentAppVersion) (\(currentAppBuild))
        Core: \(coreVersion)
        Core status: \(coreStatus)
        Advisory: \(networkModeAdvisory ?? "None")

        Settings
        \(settingsSummary)

        Network Takeover
        \(networkSummary.isEmpty ? "No network takeover states." : networkSummary)

        Diagnostics
        \(diagnosticSummary.isEmpty ? "No diagnostics have been run." : diagnosticSummary)

        Provider Update History
        \(providerSummary.isEmpty ? "No provider update history." : providerSummary)
        """
    }

    private func migrateSettingsIfNeeded() throws {
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

    private var controllerPollingIntervalNanoseconds: UInt64 {
        guard let controllerEventStreamLastEventAt,
              Date().timeIntervalSince(controllerEventStreamLastEventAt) < 8
        else {
            return 3_000_000_000
        }
        return 8_000_000_000
    }

    private func startControllerEventStreams() {
        guard controllerTrafficStreamTask == nil,
              controllerLogStreamTask == nil,
              controllerConnectionStreamTask == nil
        else {
            return
        }

        let client = controllerEventStreamClient()
        let logLevel = settings.logLevel
        controllerEventStreamLastEventAt = nil
        controllerEventStreamStatus = "连接中"

        controllerTrafficStreamTask = Task { [weak self] in
            await self?.runControllerEventStream(label: "流量", makeStream: client.trafficEvents)
        }
        controllerLogStreamTask = Task { [weak self] in
            await self?.runControllerEventStream(label: "日志", makeStream: { client.logEvents(level: logLevel) })
        }
        controllerConnectionStreamTask = Task { [weak self] in
            await self?.runControllerEventStream(label: "连接", makeStream: client.connectionEvents)
        }
    }

    private func stopControllerEventStreams(status: String) {
        controllerTrafficStreamTask?.cancel()
        controllerLogStreamTask?.cancel()
        controllerConnectionStreamTask?.cancel()
        controllerTrafficStreamTask = nil
        controllerLogStreamTask = nil
        controllerConnectionStreamTask = nil
        controllerEventStreamLastEventAt = nil
        controllerEventStreamStatus = status
    }

    private func runControllerEventStream(
        label: String,
        makeStream: @escaping () -> AsyncThrowingStream<ControllerStreamEvent, Error>
    ) async {
        var failureCount = 0
        while !Task.isCancelled && isCoreRunning {
            do {
                for try await event in makeStream() {
                    failureCount = 0
                    handleControllerStreamEvent(event)
                }
            } catch {
                guard !Task.isCancelled else { return }
                failureCount += 1
                controllerEventStreamStatus = controllerEventStreamLastEventAt == nil ? "轮询" : "降级"
                if failureCount == 1 {
                    appendLog("warning", "\(label) WebSocket 事件流不可用，保留轮询：\(error.localizedDescription)")
                }
            }

            guard !Task.isCancelled && isCoreRunning else { return }
            let backoffSeconds = min(UInt64(max(failureCount, 1) * 2), 12)
            try? await Task.sleep(nanoseconds: backoffSeconds * 1_000_000_000)
        }
    }

    private func handleControllerStreamEvent(_ event: ControllerStreamEvent) {
        controllerEventStreamLastEventAt = Date()
        if controllerEventStreamStatus != "实时" {
            controllerEventStreamStatus = "实时"
        }

        switch event {
        case .traffic(let uploadRate, let downloadRate):
            publishIfChanged(\.uploadRate, uploadRate)
            publishIfChanged(\.downloadRate, downloadRate)
            appendTrafficSampleIfNeeded(uploadRate: uploadRate, downloadRate: downloadRate)
        case .log(let level, let message):
            appendLog(level, message)
        case .connections(let items, let uploadTotal, let downloadTotal):
            let connectionsChanged = connections != items
            publishIfChanged(\.connections, items)
            if connectionsChanged {
                updateRuleProviderHitStatistics()
            }
            updateTrafficRates(uploadTotal: uploadTotal, downloadTotal: downloadTotal)
        }
    }

    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshController()
                let interval = self?.controllerPollingIntervalNanoseconds ?? 3_000_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }
}

private struct ProfileRefreshResult {
    var profileID: UUID
    var updated: ProfileItem?
    var errorMessage: String?
}

private struct ProxyDelayResult {
    var proxy: String
    var delay: Int?
    var errorMessage: String?
    var skippedMessage: String?
}

private struct ProxyDelayTarget {
    var proxy: String
    var type: String
}

private struct ProfileStatsFingerprint: Hashable {
    var fileName: String
    var location: String
    var updatedAt: Date
    var profileStoragePath: String
}

private struct ProfileQualityFingerprint: Hashable {
    var profile: ProfileStatsFingerprint
    var settings: AppSettings
    var fragments: [ConfigFragment]
    var disabledRules: Set<String>
    var migrationLog: [String]
}

private struct ProfileStatsCacheEntry {
    var fingerprint: ProfileStatsFingerprint
    var stats: ProfileStats
}

private struct ProfileQualityCacheEntry {
    var fingerprint: ProfileQualityFingerprint
    var report: ProfileQualityReport
}
