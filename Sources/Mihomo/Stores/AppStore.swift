import AppKit
import Combine
import Foundation
import MihomoShared

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
    @Published var diagnostics: [DiagnosticResult] = []
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
    @Published var resourceUpdateStatus = "资源未更新"
    @Published var geoUpdateStatus = "未更新"
    @Published var backupStatus = "未备份"
    @Published var ageStatus = "Profile 加密未启用"
    @Published var launchDaemonStatus = "未安装"
    @Published var helperStatus = "Helper 未检查"
    @Published var softwareUpdateStatus = "未检查"
    @Published var availableUpdate: AppUpdateManifest?
    @Published var connectionDetailConnectionID: String?
    @Published var policyGroupIconImages: [String: NSImage] = [:]
    @Published var networkTakeoverStates: [NetworkTakeoverState] = []
    @Published var settingsMigrationLog: [String] = []
    @Published var diagnosticExportStatus = "尚未导出诊断包"
    @Published var lastDiagnosticBundleURL: URL?
    @Published var ruleFocusQuery = ""
    @Published var networkWorkspaceTab: NetworkWorkspaceTab = .overview
    @Published var isLightweightModeActive = false

    let logStore = LogStore()
    let activityStore = RuntimeActivityStore()

    var connections: [ConnectionItem] {
        get { activityStore.connections }
        set { activityStore.replaceConnections(newValue) }
    }

    var uploadRate: Int64 {
        get { activityStore.uploadRate }
        set { activityStore.uploadRate = newValue }
    }

    var downloadRate: Int64 {
        get { activityStore.downloadRate }
        set { activityStore.downloadRate = newValue }
    }

    var trafficSamples: [TrafficSample] {
        get { activityStore.trafficSamples }
        set { activityStore.trafficSamples = newValue }
    }

    var controllerEventStreamStatus: String {
        get { activityStore.eventStreamStatus }
        set { activityStore.eventStreamStatus = newValue }
    }

    var logs: [LogEntry] {
        get { logStore.entries }
        set { logStore.entries = newValue }
    }

    var logsPaused: Bool {
        get { logStore.isPaused }
        set { logStore.isPaused = newValue }
    }

    var bufferedLogCount: Int {
        get { logStore.bufferedCount }
        set { logStore.bufferedCount = newValue }
    }

    let profileStore = ProfileStore()
    let systemProxy = SystemProxyManager()
    let tunRecovery = TunRecoveryManager()
    let loginItem = LoginItemManager()
    let notificationManager = NotificationManager()
    let configFragmentStore = ConfigFragmentStore()
    let managedCoreManager = ManagedCoreManager()
    let geoUpdateManager = GeoUpdateManager()
    let profileSettingsSynchronizer = ProfileSettingsSynchronizer()
    let backupManager = BackupManager()
    let profileAgeService = ProfileAgeService()
    let helperClient = MihomoHelperClient()
    let helperService = HelperServiceManager()
    let helperAuditService = HelperAuditService()
    let softwareUpdateManager = SoftwareUpdateManager()
    let profileQualityAnalyzer = ProfileQualityAnalyzer()
    let logPersistenceWriter = LogPersistenceWriter()
    let spotlightIndexer = SpotlightIndexer()
    var pollingTask: Task<Void, Never>?
    var profileRefreshTask: Task<Void, Never>?
    var profileRefreshQueueRunning = false
    var lastUploadTotal: Int64?
    var lastDownloadTotal: Int64?
    var lastTrafficSampleAt: Date?
    var isExpectedCoreExit = false
    var shutdownRequested = false
    var crashRestartCount = 0
    var bufferedLogs: [LogEntry] = []
    var pendingLogEntries: [LogEntry] = []
    var logFlushTask: Task<Void, Never>?
    var ruleHitBaselines: [String: Int] = [:]
    var ruleHitTotals: [String: Int] = [:]
    var providerHitTotals: [String: Int] = [:]
    var observedConnectionHitIDs: Set<String> = []
    var availableUpdateManifestURL: URL?
    var lastNetworkOperations: [NetworkTakeoverKind: String] = [:]
    var lastNetworkTakeoverRefreshAt = Date.distantPast
    var profileStatsCache: [UUID: ProfileStatsCacheEntry] = [:]
    var profileQualityCache: [UUID: ProfileQualityCacheEntry] = [:]
    var controllerTrafficStreamTask: Task<Void, Never>?
    var controllerLogStreamTask: Task<Void, Never>?
    var controllerConnectionStreamTask: Task<Void, Never>?
    var controllerEventStreamLastEventAt: Date?

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
            helperStatus = helperService.statusDescription
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

    func preloadPolicyGroupIcons() async {
        await preloadPolicyGroupIcons(for: proxyGroups)
    }

    func enterLightweightMode() {
        isLightweightModeActive = true
        NSApp.hide(nil)
        appendLog("info", "已进入轻量模式，主窗口隐藏，菜单栏保留。")
    }

    func preloadPolicyGroupIcons(for groups: [ProxyGroup]) async {
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
            guard let (data, _) = try? await NetworkClient.data(for: request, kind: .controller) else { return nil }
            return data
        }
        return try? Data(contentsOf: URL(fileURLWithPath: (icon as NSString).expandingTildeInPath))
    }

    func controllerClient() -> MihomoControllerClient {
        MihomoControllerClient(
            host: settings.localControlHost,
            port: settings.controllerPort,
            secret: settings.controllerSecret
        )
    }

    func publishIfChanged<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppStore, Value>, _ value: Value) {
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

}
