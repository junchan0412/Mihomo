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
    @Published var pendingProfileRefreshPreviews: [RemoteProfileRefreshPreview] = []
    @Published var delayTestStatus = "未运行"
    @Published var delayTestFailureSummary = ""
    @Published var policyDelayHistory: [PolicyDelayHistoryEntry] = []
    @Published var recentProxySelections: [RecentProxySelection] = []
    @Published var favoritePolicyGroupNames: Set<String> = []
    @Published var offlineProxyGroups: [ProxyGroup] = []
    @Published var configFragments: [ConfigFragment] = []
    @Published var configRevisions: [ConfigRevision] = []
    @Published var configFragmentRefreshStatus = "没有远程覆写"
    @Published var configFragmentRefreshFailureCount = 0
    @Published var isConfigFragmentRefreshInProgress = false
    @Published var configFragmentImportStatus = ""
    @Published var disabledRules: Set<String> = []
    @Published var rules: [RuleItem] = []
    @Published var providers: [ProviderItem] = []
    @Published var nodeProviders: [NodeProvider] = []
    @Published var nodeProviderUndoTitle: String?
    @Published var configPreview = ""
    @Published var configDiff = ""
    @Published var providerUpdateHistory: [ProviderUpdateRecord] = []
    @Published var advancedStatus = "高级功能待命"
    @Published var managedCoreStatus = "未托管"
    @Published var resourceUpdateStatus = "资源未更新"
    @Published var isResourceBatchOperationInProgress = false
    @Published var geoUpdateStatus = "未更新"
    @Published var backupStatus = "未备份"
    @Published var ageStatus = "Profile 加密未启用"
    @Published var launchDaemonStatus = "未安装"
    @Published var helperStatus = "Helper 未检查"
    @Published var softwareUpdateStatus = "未检查"
    @Published var softwareUpdatePhase: SoftwareUpdatePhase = .idle
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
    @Published var isCommandPalettePresented = false

    let logStore = LogStore()
    let activityStore = RuntimeActivityStore()

    let profileStore = ProfileStore()
    let systemProxy = SystemProxyManager()
    let tunRecovery = TunRecoveryManager()
    let loginItem = LoginItemManager()
    let notificationManager = NotificationManager()
    let configFragmentStore = ConfigFragmentStore()
    let configRevisionStore = ConfigRevisionStore()
    let nodeProviderStore = NodeProviderStore()
    let nodeProviderSynchronizer = NodeProviderProfileSynchronizer()
    var nodeProviderUndoSnapshot: NodeProviderUndoSnapshot?
    let managedCoreManager = ManagedCoreManager()
    let geoUpdateManager = GeoUpdateManager()
    let profileSettingsSynchronizer = ProfileSettingsSynchronizer()
    let backupManager = BackupManager()
    let profileAgeService = ProfileAgeService()
    let helperClient = MihomoHelperClient()
    let helperService = HelperServiceManager()
    let legacyHelperInstaller = LegacyHelperInstaller()
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
    var preparedSoftwareUpdate: PreparedUpdatePackage?
    var softwareUpdateTask: Task<Void, Never>?
    var lastNetworkOperations: [NetworkTakeoverKind: String] = [:]
    var lastNetworkTakeoverRefreshAt = Date.distantPast
    var lastSystemProxyGuardAttemptAt = Date.distantPast
    var systemProxyGuardTask: Task<Void, Never>?
    var profileStatsCache: [UUID: ProfileStatsCacheEntry] = [:]
    var profileQualityCache: [UUID: ProfileQualityCacheEntry] = [:]
    var controllerTrafficStreamTask: Task<Void, Never>?
    var controllerLogStreamTask: Task<Void, Never>?
    var controllerConnectionStreamTask: Task<Void, Never>?
    var controllerEventStreamLastEventAt: Date?
    var controllerConnectionStreamLastEventAt: Date?

}
