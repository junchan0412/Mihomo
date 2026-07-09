import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case networkSecurity
    case activity
    case policies
    case profiles
    case rules
    case resources
    case advanced
    case logs
    case diagnostics
    case settings

    var id: String { rawValue }

    static var sidebarSections: [AppSection] {
        allCases.filter { section in
            section != .settings && section != .logs
        }
    }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .networkSecurity: return "网络安全"
        case .activity: return "活动"
        case .policies: return "策略"
        case .profiles: return "配置"
        case .rules: return "规则"
        case .resources: return "资源"
        case .advanced: return "高级"
        case .logs: return "日志"
        case .diagnostics: return "诊断"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .networkSecurity: return "shield.lefthalf.filled"
        case .activity: return "waveform.path.ecg"
        case .policies: return "switch.2"
        case .profiles: return "doc.text"
        case .rules: return "list.bullet.rectangle"
        case .resources: return "shippingbox"
        case .advanced: return "wrench.and.screwdriver"
        case .logs: return "terminal"
        case .diagnostics: return "stethoscope"
        case .settings: return "gearshape"
        }
    }
}

enum ProfileSource: String, Codable, CaseIterable {
    case local
    case remote
}

enum CoreSource: String, Codable, CaseIterable, Identifiable, Hashable {
    case managed
    case bundled
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .managed: return "托管远程"
        case .bundled: return "随包内置"
        case .local: return "本地外部"
        }
    }

    var detail: String {
        switch self {
        case .managed: return "由应用下载并维护 mihomo core"
        case .bundled: return "使用 App 包内附带的 mihomo core"
        case .local: return "使用用户指定的本地可执行文件"
        }
    }
}

enum NetworkTakeoverKind: String, CaseIterable, Identifiable, Hashable {
    case systemProxy
    case systemDNS
    case tun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemProxy: return "系统代理"
        case .systemDNS: return "系统 DNS"
        case .tun: return "TUN / 路由"
        }
    }

    var systemImage: String {
        switch self {
        case .systemProxy: return "network"
        case .systemDNS: return "globe"
        case .tun: return "lock.shield"
        }
    }
}

enum NetworkTakeoverHealth: String, Hashable {
    case ok
    case warning
    case inactive
    case failed
}

struct NetworkTakeoverState: Identifiable, Hashable {
    var id: NetworkTakeoverKind { kind }
    var kind: NetworkTakeoverKind
    var desiredState: String
    var actualState: String
    var lastOperation: String
    var recoveryAction: String
    var health: NetworkTakeoverHealth
}

enum NetworkSecuritySnapshotKind: String, Hashable {
    case systemProxy
    case systemDNS
    case tunRecovery

    var title: String {
        switch self {
        case .systemProxy: return "系统代理快照"
        case .systemDNS: return "系统 DNS 快照"
        case .tunRecovery: return "TUN 回滚快照"
        }
    }

    var systemImage: String {
        switch self {
        case .systemProxy: return "network"
        case .systemDNS: return "globe"
        case .tunRecovery: return "lock.shield"
        }
    }
}

struct NetworkSecuritySnapshotItem: Identifiable, Hashable {
    var id: NetworkSecuritySnapshotKind { kind }
    var kind: NetworkSecuritySnapshotKind
    var path: String
    var createdAt: Date?
    var status: String
    var detail: String
    var health: NetworkTakeoverHealth
}

struct NetworkSecuritySnapshotPaths: Hashable {
    var systemProxy: String
    var systemDNS: String
    var tunRecovery: String
}

struct ProfileItem: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var source: ProfileSource
    var location: String
    var fileName: String
    var updatedAt: Date
    var uploadUsed: Int64?
    var downloadUsed: Int64?
    var total: Int64?
    var expireAt: Date?
    var certificateFingerprint: String?

    var isRemote: Bool { source == .remote }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case source
        case location
        case fileName
        case updatedAt
        case uploadUsed
        case downloadUsed
        case total
        case expireAt
        case certificateFingerprint
    }

    init(
        id: UUID,
        name: String,
        source: ProfileSource,
        location: String,
        fileName: String,
        updatedAt: Date,
        uploadUsed: Int64? = nil,
        downloadUsed: Int64? = nil,
        total: Int64? = nil,
        expireAt: Date? = nil,
        certificateFingerprint: String? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.location = location
        self.fileName = fileName
        self.updatedAt = updatedAt
        self.uploadUsed = uploadUsed
        self.downloadUsed = downloadUsed
        self.total = total
        self.expireAt = expireAt
        self.certificateFingerprint = certificateFingerprint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        source = try container.decode(ProfileSource.self, forKey: .source)
        location = try container.decode(String.self, forKey: .location)
        fileName = try container.decode(String.self, forKey: .fileName)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        uploadUsed = try container.decodeIfPresent(Int64.self, forKey: .uploadUsed)
        downloadUsed = try container.decodeIfPresent(Int64.self, forKey: .downloadUsed)
        total = try container.decodeIfPresent(Int64.self, forKey: .total)
        expireAt = try container.decodeIfPresent(Date.self, forKey: .expireAt)
        certificateFingerprint = try container.decodeIfPresent(String.self, forKey: .certificateFingerprint)
    }
}

struct AppSettings: Codable, Hashable {
    var settingsSchemaVersion: Int
    var mihomoPath: String
    var coreSource: CoreSource
    var activeProfileID: UUID?
    var profileStoragePath: String
    var controllerHost: String
    var controllerPort: Int
    var mixedPort: Int
    var socksPort: Int
    var allowLAN: Bool
    var tunEnabled: Bool
    var logLevel: String
    var autoStartCore: Bool
    var closeConnectionsOnPolicyChange: Bool
    var restartCoreOnCrash: Bool
    var maxCrashRestarts: Int
    var autoRefreshProfiles: Bool
    var profileRefreshIntervalHours: Int
    var lightweightMode: Bool
    var restoreSystemProxyOnQuit: Bool
    var delayTestURL: String
    var delayTestTimeoutMS: Int
    var launchAtLogin: Bool
    var restoreTunOnStop: Bool
    var profileRefreshMaxConcurrent: Int
    var delayTestConcurrency: Int
    var logRetentionDays: Int
    var logMaxFileSizeMB: Int
    var managedCoreEnabled: Bool
    var managedCoreDownloadURL: String
    var launchDaemonEnabled: Bool
    var autoSetSystemDNS: Bool
    var systemDNSServers: [String]
    var externalUIEnabled: Bool
    var externalUIName: String
    var externalUIDownloadURL: String
    var remoteAPIEnabled: Bool
    var remoteAPIBindAddress: String
    var controllerSecret: String
    var yamlOverrideEnabled: Bool
    var jsOverrideEnabled: Bool
    var snifferEnabled: Bool
    var snifferPorts: String
    var snifferForceDomains: String
    var snifferSkipDomains: String
    var dnsEnhancedMode: String
    var dnsNameservers: [String]
    var dnsFallbacks: [String]
    var geoIPURL: String
    var geoSiteURL: String
    var backupWebDAVURL: String
    var backupWebDAVUsername: String
    var backupWebDAVPassword: String
    var gistToken: String
    var gistID: String
    var softwareUpdateManifestURL: String
    var profileEncryptionEnabled: Bool
    var ageBinaryPath: String
    var ageKeygenPath: String
    var ageIdentityPath: String
    var ageRecipient: String
    var ageDownloadURL: String

    static let `default` = AppSettings()

    init(
        settingsSchemaVersion: Int = 2,
        mihomoPath: String = "",
        coreSource: CoreSource = .managed,
        activeProfileID: UUID? = nil,
        profileStoragePath: String = "",
        controllerHost: String = "127.0.0.1",
        controllerPort: Int = 9090,
        mixedPort: Int = 7890,
        socksPort: Int = 0,
        allowLAN: Bool = false,
        tunEnabled: Bool = false,
        logLevel: String = "info",
        autoStartCore: Bool = false,
        closeConnectionsOnPolicyChange: Bool = true,
        restartCoreOnCrash: Bool = true,
        maxCrashRestarts: Int = 3,
        autoRefreshProfiles: Bool = false,
        profileRefreshIntervalHours: Int = 24,
        lightweightMode: Bool = false,
        restoreSystemProxyOnQuit: Bool = true,
        delayTestURL: String = "https://cp.cloudflare.com/generate_204",
        delayTestTimeoutMS: Int = 8000,
        launchAtLogin: Bool = false,
        restoreTunOnStop: Bool = true,
        profileRefreshMaxConcurrent: Int = 2,
        delayTestConcurrency: Int = 6,
        logRetentionDays: Int = 7,
        logMaxFileSizeMB: Int = 8,
        managedCoreEnabled: Bool? = nil,
        managedCoreDownloadURL: String = "https://github.com/MetaCubeX/mihomo/releases/download/v1.19.27/mihomo-darwin-arm64-v1.19.27.gz",
        launchDaemonEnabled: Bool = false,
        autoSetSystemDNS: Bool = false,
        systemDNSServers: [String] = ["1.1.1.1", "8.8.8.8"],
        externalUIEnabled: Bool = false,
        externalUIName: String = "zashboard",
        externalUIDownloadURL: String = "https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip",
        remoteAPIEnabled: Bool = false,
        remoteAPIBindAddress: String = "127.0.0.1",
        controllerSecret: String = "",
        yamlOverrideEnabled: Bool = true,
        jsOverrideEnabled: Bool = false,
        snifferEnabled: Bool = false,
        snifferPorts: String = "80,443",
        snifferForceDomains: String = "",
        snifferSkipDomains: String = "",
        dnsEnhancedMode: String = "fake-ip",
        dnsNameservers: [String] = ["https://1.1.1.1/dns-query", "https://dns.google/dns-query"],
        dnsFallbacks: [String] = [],
        geoIPURL: String = "https://github.com/MetaCubeX/meta-rules-dat/releases/latest/download/geoip.dat",
        geoSiteURL: String = "https://github.com/MetaCubeX/meta-rules-dat/releases/latest/download/geosite.dat",
        backupWebDAVURL: String = "",
        backupWebDAVUsername: String = "",
        backupWebDAVPassword: String = "",
        gistToken: String = "",
        gistID: String = "",
        softwareUpdateManifestURL: String = "",
        profileEncryptionEnabled: Bool = false,
        ageBinaryPath: String = "",
        ageKeygenPath: String = "",
        ageIdentityPath: String = "",
        ageRecipient: String = "",
        ageDownloadURL: String = "https://github.com/FiloSottile/age/releases/download/v1.2.1/age-v1.2.1-darwin-arm64.tar.gz"
    ) {
        self.settingsSchemaVersion = settingsSchemaVersion
        self.mihomoPath = mihomoPath
        self.coreSource = coreSource
        self.activeProfileID = activeProfileID
        self.profileStoragePath = profileStoragePath
        self.controllerHost = controllerHost
        self.controllerPort = controllerPort
        self.mixedPort = mixedPort
        self.socksPort = socksPort
        self.allowLAN = allowLAN
        self.tunEnabled = tunEnabled
        self.logLevel = logLevel
        self.autoStartCore = autoStartCore
        self.closeConnectionsOnPolicyChange = closeConnectionsOnPolicyChange
        self.restartCoreOnCrash = restartCoreOnCrash
        self.maxCrashRestarts = maxCrashRestarts
        self.autoRefreshProfiles = autoRefreshProfiles
        self.profileRefreshIntervalHours = profileRefreshIntervalHours
        self.lightweightMode = lightweightMode
        self.restoreSystemProxyOnQuit = restoreSystemProxyOnQuit
        self.delayTestURL = delayTestURL
        self.delayTestTimeoutMS = delayTestTimeoutMS
        self.launchAtLogin = launchAtLogin
        self.restoreTunOnStop = restoreTunOnStop
        self.profileRefreshMaxConcurrent = profileRefreshMaxConcurrent
        self.delayTestConcurrency = delayTestConcurrency
        self.logRetentionDays = logRetentionDays
        self.logMaxFileSizeMB = logMaxFileSizeMB
        self.managedCoreEnabled = managedCoreEnabled ?? (coreSource == .managed)
        self.managedCoreDownloadURL = managedCoreDownloadURL
        self.launchDaemonEnabled = launchDaemonEnabled
        self.autoSetSystemDNS = autoSetSystemDNS
        self.systemDNSServers = systemDNSServers
        self.externalUIEnabled = externalUIEnabled
        self.externalUIName = externalUIName
        self.externalUIDownloadURL = externalUIDownloadURL
        self.remoteAPIEnabled = remoteAPIEnabled
        self.remoteAPIBindAddress = remoteAPIBindAddress
        self.controllerSecret = controllerSecret
        self.yamlOverrideEnabled = yamlOverrideEnabled
        self.jsOverrideEnabled = jsOverrideEnabled
        self.snifferEnabled = snifferEnabled
        self.snifferPorts = snifferPorts
        self.snifferForceDomains = snifferForceDomains
        self.snifferSkipDomains = snifferSkipDomains
        self.dnsEnhancedMode = dnsEnhancedMode
        self.dnsNameservers = dnsNameservers
        self.dnsFallbacks = dnsFallbacks
        self.geoIPURL = geoIPURL
        self.geoSiteURL = geoSiteURL
        self.backupWebDAVURL = backupWebDAVURL
        self.backupWebDAVUsername = backupWebDAVUsername
        self.backupWebDAVPassword = backupWebDAVPassword
        self.gistToken = gistToken
        self.gistID = gistID
        self.softwareUpdateManifestURL = softwareUpdateManifestURL
        self.profileEncryptionEnabled = profileEncryptionEnabled
        self.ageBinaryPath = ageBinaryPath
        self.ageKeygenPath = ageKeygenPath
        self.ageIdentityPath = ageIdentityPath
        self.ageRecipient = ageRecipient
        self.ageDownloadURL = ageDownloadURL
    }

    private enum CodingKeys: String, CodingKey {
        case settingsSchemaVersion
        case mihomoPath
        case coreSource
        case activeProfileID
        case profileStoragePath
        case controllerHost
        case controllerPort
        case mixedPort
        case socksPort
        case allowLAN
        case tunEnabled
        case logLevel
        case autoStartCore
        case closeConnectionsOnPolicyChange
        case restartCoreOnCrash
        case maxCrashRestarts
        case autoRefreshProfiles
        case profileRefreshIntervalHours
        case lightweightMode
        case restoreSystemProxyOnQuit
        case delayTestURL
        case delayTestTimeoutMS
        case launchAtLogin
        case restoreTunOnStop
        case profileRefreshMaxConcurrent
        case delayTestConcurrency
        case logRetentionDays
        case logMaxFileSizeMB
        case managedCoreEnabled
        case managedCoreDownloadURL
        case launchDaemonEnabled
        case autoSetSystemDNS
        case systemDNSServers
        case externalUIEnabled
        case externalUIName
        case externalUIDownloadURL
        case remoteAPIEnabled
        case remoteAPIBindAddress
        case controllerSecret
        case yamlOverrideEnabled
        case jsOverrideEnabled
        case snifferEnabled
        case snifferPorts
        case snifferForceDomains
        case snifferSkipDomains
        case dnsEnhancedMode
        case dnsNameservers
        case dnsFallbacks
        case geoIPURL
        case geoSiteURL
        case backupWebDAVURL
        case backupWebDAVUsername
        case backupWebDAVPassword
        case gistToken
        case gistID
        case softwareUpdateManifestURL
        case profileEncryptionEnabled
        case ageBinaryPath
        case ageKeygenPath
        case ageIdentityPath
        case ageRecipient
        case ageDownloadURL
    }

    init(from decoder: Decoder) throws {
        let fallback = AppSettings.default
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settingsSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .settingsSchemaVersion) ?? 1
        mihomoPath = try container.decodeIfPresent(String.self, forKey: .mihomoPath) ?? fallback.mihomoPath
        let legacyManagedCoreEnabled = try container.decodeIfPresent(Bool.self, forKey: .managedCoreEnabled)
        coreSource = try container.decodeIfPresent(CoreSource.self, forKey: .coreSource)
            ?? AppSettings.migratedCoreSource(legacyManagedCoreEnabled: legacyManagedCoreEnabled, mihomoPath: mihomoPath)
        activeProfileID = try container.decodeIfPresent(UUID.self, forKey: .activeProfileID) ?? fallback.activeProfileID
        profileStoragePath = try container.decodeIfPresent(String.self, forKey: .profileStoragePath) ?? fallback.profileStoragePath
        controllerHost = try container.decodeIfPresent(String.self, forKey: .controllerHost) ?? fallback.controllerHost
        controllerPort = try container.decodeIfPresent(Int.self, forKey: .controllerPort) ?? fallback.controllerPort
        mixedPort = try container.decodeIfPresent(Int.self, forKey: .mixedPort) ?? fallback.mixedPort
        socksPort = try container.decodeIfPresent(Int.self, forKey: .socksPort) ?? fallback.socksPort
        allowLAN = try container.decodeIfPresent(Bool.self, forKey: .allowLAN) ?? fallback.allowLAN
        tunEnabled = try container.decodeIfPresent(Bool.self, forKey: .tunEnabled) ?? fallback.tunEnabled
        logLevel = try container.decodeIfPresent(String.self, forKey: .logLevel) ?? fallback.logLevel
        autoStartCore = try container.decodeIfPresent(Bool.self, forKey: .autoStartCore) ?? fallback.autoStartCore
        closeConnectionsOnPolicyChange = try container.decodeIfPresent(Bool.self, forKey: .closeConnectionsOnPolicyChange) ?? fallback.closeConnectionsOnPolicyChange
        restartCoreOnCrash = try container.decodeIfPresent(Bool.self, forKey: .restartCoreOnCrash) ?? fallback.restartCoreOnCrash
        maxCrashRestarts = try container.decodeIfPresent(Int.self, forKey: .maxCrashRestarts) ?? fallback.maxCrashRestarts
        autoRefreshProfiles = try container.decodeIfPresent(Bool.self, forKey: .autoRefreshProfiles) ?? fallback.autoRefreshProfiles
        profileRefreshIntervalHours = try container.decodeIfPresent(Int.self, forKey: .profileRefreshIntervalHours) ?? fallback.profileRefreshIntervalHours
        lightweightMode = try container.decodeIfPresent(Bool.self, forKey: .lightweightMode) ?? fallback.lightweightMode
        restoreSystemProxyOnQuit = try container.decodeIfPresent(Bool.self, forKey: .restoreSystemProxyOnQuit) ?? fallback.restoreSystemProxyOnQuit
        delayTestURL = try container.decodeIfPresent(String.self, forKey: .delayTestURL) ?? fallback.delayTestURL
        delayTestTimeoutMS = try container.decodeIfPresent(Int.self, forKey: .delayTestTimeoutMS) ?? fallback.delayTestTimeoutMS
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? fallback.launchAtLogin
        restoreTunOnStop = try container.decodeIfPresent(Bool.self, forKey: .restoreTunOnStop) ?? fallback.restoreTunOnStop
        profileRefreshMaxConcurrent = try container.decodeIfPresent(Int.self, forKey: .profileRefreshMaxConcurrent) ?? fallback.profileRefreshMaxConcurrent
        delayTestConcurrency = try container.decodeIfPresent(Int.self, forKey: .delayTestConcurrency) ?? fallback.delayTestConcurrency
        logRetentionDays = try container.decodeIfPresent(Int.self, forKey: .logRetentionDays) ?? fallback.logRetentionDays
        logMaxFileSizeMB = try container.decodeIfPresent(Int.self, forKey: .logMaxFileSizeMB) ?? fallback.logMaxFileSizeMB
        managedCoreEnabled = legacyManagedCoreEnabled ?? (coreSource == .managed)
        managedCoreDownloadURL = try container.decodeIfPresent(String.self, forKey: .managedCoreDownloadURL) ?? fallback.managedCoreDownloadURL
        launchDaemonEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchDaemonEnabled) ?? fallback.launchDaemonEnabled
        autoSetSystemDNS = try container.decodeIfPresent(Bool.self, forKey: .autoSetSystemDNS) ?? fallback.autoSetSystemDNS
        systemDNSServers = try container.decodeIfPresent([String].self, forKey: .systemDNSServers) ?? fallback.systemDNSServers
        externalUIEnabled = try container.decodeIfPresent(Bool.self, forKey: .externalUIEnabled) ?? fallback.externalUIEnabled
        externalUIName = try container.decodeIfPresent(String.self, forKey: .externalUIName) ?? fallback.externalUIName
        externalUIDownloadURL = try container.decodeIfPresent(String.self, forKey: .externalUIDownloadURL) ?? fallback.externalUIDownloadURL
        remoteAPIEnabled = try container.decodeIfPresent(Bool.self, forKey: .remoteAPIEnabled) ?? fallback.remoteAPIEnabled
        remoteAPIBindAddress = try container.decodeIfPresent(String.self, forKey: .remoteAPIBindAddress) ?? fallback.remoteAPIBindAddress
        controllerSecret = try container.decodeIfPresent(String.self, forKey: .controllerSecret) ?? fallback.controllerSecret
        yamlOverrideEnabled = try container.decodeIfPresent(Bool.self, forKey: .yamlOverrideEnabled) ?? fallback.yamlOverrideEnabled
        jsOverrideEnabled = try container.decodeIfPresent(Bool.self, forKey: .jsOverrideEnabled) ?? fallback.jsOverrideEnabled
        snifferEnabled = try container.decodeIfPresent(Bool.self, forKey: .snifferEnabled) ?? fallback.snifferEnabled
        snifferPorts = try container.decodeIfPresent(String.self, forKey: .snifferPorts) ?? fallback.snifferPorts
        snifferForceDomains = try container.decodeIfPresent(String.self, forKey: .snifferForceDomains) ?? fallback.snifferForceDomains
        snifferSkipDomains = try container.decodeIfPresent(String.self, forKey: .snifferSkipDomains) ?? fallback.snifferSkipDomains
        dnsEnhancedMode = try container.decodeIfPresent(String.self, forKey: .dnsEnhancedMode) ?? fallback.dnsEnhancedMode
        dnsNameservers = try container.decodeIfPresent([String].self, forKey: .dnsNameservers) ?? fallback.dnsNameservers
        dnsFallbacks = try container.decodeIfPresent([String].self, forKey: .dnsFallbacks) ?? fallback.dnsFallbacks
        geoIPURL = try container.decodeIfPresent(String.self, forKey: .geoIPURL) ?? fallback.geoIPURL
        geoSiteURL = try container.decodeIfPresent(String.self, forKey: .geoSiteURL) ?? fallback.geoSiteURL
        backupWebDAVURL = try container.decodeIfPresent(String.self, forKey: .backupWebDAVURL) ?? fallback.backupWebDAVURL
        backupWebDAVUsername = try container.decodeIfPresent(String.self, forKey: .backupWebDAVUsername) ?? fallback.backupWebDAVUsername
        backupWebDAVPassword = try container.decodeIfPresent(String.self, forKey: .backupWebDAVPassword) ?? fallback.backupWebDAVPassword
        gistToken = try container.decodeIfPresent(String.self, forKey: .gistToken) ?? fallback.gistToken
        gistID = try container.decodeIfPresent(String.self, forKey: .gistID) ?? fallback.gistID
        softwareUpdateManifestURL = try container.decodeIfPresent(String.self, forKey: .softwareUpdateManifestURL) ?? fallback.softwareUpdateManifestURL
        profileEncryptionEnabled = try container.decodeIfPresent(Bool.self, forKey: .profileEncryptionEnabled) ?? fallback.profileEncryptionEnabled
        ageBinaryPath = try container.decodeIfPresent(String.self, forKey: .ageBinaryPath) ?? fallback.ageBinaryPath
        ageKeygenPath = try container.decodeIfPresent(String.self, forKey: .ageKeygenPath) ?? fallback.ageKeygenPath
        ageIdentityPath = try container.decodeIfPresent(String.self, forKey: .ageIdentityPath) ?? fallback.ageIdentityPath
        ageRecipient = try container.decodeIfPresent(String.self, forKey: .ageRecipient) ?? fallback.ageRecipient
        ageDownloadURL = try container.decodeIfPresent(String.self, forKey: .ageDownloadURL) ?? fallback.ageDownloadURL
    }

    private static func migratedCoreSource(legacyManagedCoreEnabled: Bool?, mihomoPath: String) -> CoreSource {
        if legacyManagedCoreEnabled == true {
            return .managed
        }
        return mihomoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .managed : .local
    }
}

enum ConfigFragmentKind: String, Codable, CaseIterable, Hashable {
    case yaml
    case javascript

    var title: String {
        switch self {
        case .yaml: return "YAML"
        case .javascript: return "JavaScript"
        }
    }
}

struct ConfigFragment: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: ConfigFragmentKind
    var enabled: Bool
    var content: String
    var updatedAt = Date()
}

struct RuleItem: Identifiable, Hashable {
    var id: String { "\(index)-\(content)" }
    var index: Int
    var content: String
    var disabled: Bool
    var hitCount: Int = 0
}

struct ProviderItem: Identifiable, Hashable {
    var id: String { "\(kind)-\(name)" }
    var kind: String
    var name: String
    var detail: String
    var providerType: String = ""
    var remoteURL: String?
    var path: String?
    var interval: Int?
    var ruleCount: Int = 0
    var hitCount: Int = 0
    var memberNames: [String] = []
}

struct ProviderUpdateRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var providerName: String
    var providerKind: String
    var action: String
    var succeeded: Bool
    var targetPath: String
    var message: String
    var backupPath: String?
    var restoredFromPath: String?
}

struct ProfileStats: Hashable {
    var lineCount: Int = 0
    var fileSize: Int = 0
    var policyGroupCount: Int = 0
    var proxyCount: Int = 0
    var ruleCount: Int = 0
    var proxyProviderCount: Int = 0
    var ruleProviderCount: Int = 0
    var errorMessage: String?
}

enum ProfileQualitySeverity: String, Hashable {
    case info
    case warning
    case error

    var title: String {
        switch self {
        case .info: return "提示"
        case .warning: return "警告"
        case .error: return "错误"
        }
    }
}

struct ProfileQualityIssue: Identifiable, Hashable {
    var id = UUID()
    var severity: ProfileQualitySeverity
    var title: String
    var detail: String
}

struct RuntimeInspectorItem: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var value: String
    var detail: String
}

struct RuntimeConfigSourceItem: Identifiable, Hashable {
    var id: String { path }
    var path: String
    var source: String
    var value: String
    var detail: String
    var isAppManaged: Bool
}

struct ConfigDiffLayer: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var changed: Bool
    var summary: String
}

struct ProfileQualityReport: Hashable {
    var score: Int
    var headline: String
    var issues: [ProfileQualityIssue]
    var runtimeItems: [RuntimeInspectorItem]
    var sourceItems: [RuntimeConfigSourceItem]
    var diffLayers: [ConfigDiffLayer]
    var migrationLog: [String]
    var generatedConfig: String
}

extension ProfileQualityReport {
    static let empty = ProfileQualityReport(
        score: 0,
        headline: "未选择配置",
        issues: [],
        runtimeItems: [],
        sourceItems: [],
        diffLayers: [],
        migrationLog: [],
        generatedConfig: ""
    )
}

struct EditablePolicyGroup: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var type: String
    var proxies: [String]
    var uses: [String]
}

struct EditableProfileRule: Identifiable, Hashable {
    var id: String { "\(index)-\(content)" }
    var index: Int
    var type: String
    var payload: String
    var target: String
    var options: [String]

    var content: String {
        if payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ([type, target] + options).joined(separator: ",")
        }
        return ([type, payload, target] + options).joined(separator: ",")
    }
}

struct ProfileStructureSnapshot: Hashable {
    var groups: [EditablePolicyGroup]
    var rules: [EditableProfileRule]
    var proxyNames: [String]
}

struct ProxyNode: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var type: String
    var delay: Int?
}

struct ProxyGroup: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var type: String
    var now: String
    var all: [ProxyNode]
    var icon: String?
}

struct PolicyTableRow: Identifiable, Hashable {
    var group: ProxyGroup
    var node: ProxyNode

    var id: String { "\(group.name)\u{1f}\(node.name)" }
}

struct ConnectionItem: Identifiable, Hashable {
    var id: String
    var host: String
    var process: String
    var network: String
    var rule: String
    var ruleType: String = ""
    var rulePayload: String = ""
    var chain: String
    var upload: Int64
    var download: Int64
    var start: Date?
}

struct TrafficSample: Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var uploadRate: Int64
    var downloadRate: Int64
}

struct LogEntry: Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var level: String
    var message: String
}

enum ProfileRefreshJobState: String, Hashable {
    case pending
    case running
    case succeeded
    case failed

    var title: String {
        switch self {
        case .pending: return "等待"
        case .running: return "运行中"
        case .succeeded: return "成功"
        case .failed: return "失败"
        }
    }
}

struct ProfileRefreshJob: Identifiable, Hashable {
    var id = UUID()
    var profileID: UUID
    var profileName: String
    var state: ProfileRefreshJobState
    var message: String
    var startedAt: Date?
    var finishedAt: Date?
}

enum DiagnosticState: String, Hashable {
    case ok
    case warning
    case failed
}

struct DiagnosticResult: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var detail: String
    var state: DiagnosticState
}
