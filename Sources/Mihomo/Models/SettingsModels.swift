import Foundation

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
    var managedCoreSHA256: String
    var launchDaemonEnabled: Bool
    var autoSetSystemDNS: Bool
    var systemDNSServers: [String]
    var externalUIEnabled: Bool
    var externalUIName: String
    var externalUIDownloadURL: String
    var externalUISHA256: String
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
    var geoIPSHA256: String
    var geoSiteSHA256: String
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
    var ageDownloadSHA256: String

    static let `default` = AppSettings()

    init(
        settingsSchemaVersion: Int = 3,
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
        managedCoreDownloadURL: String = "https://github.com/MetaCubeX/mihomo/releases/download/v1.19.28/mihomo-darwin-arm64-v1.19.28.gz",
        managedCoreSHA256: String = "40cdae2fab4b18df15f40eaa9dc3af70ab3d8be7f77164ae1e5f1af3a2a4fb44",
        launchDaemonEnabled: Bool = false,
        autoSetSystemDNS: Bool = false,
        systemDNSServers: [String] = ["1.1.1.1", "8.8.8.8"],
        externalUIEnabled: Bool = false,
        externalUIName: String = "zashboard",
        externalUIDownloadURL: String = "https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip",
        externalUISHA256: String = "",
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
        geoIPSHA256: String = "",
        geoSiteSHA256: String = "",
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
        ageDownloadURL: String = "https://github.com/FiloSottile/age/releases/download/v1.2.1/age-v1.2.1-darwin-arm64.tar.gz",
        ageDownloadSHA256: String = "cf79875bd5970dc2dac60c87fa50cee1ff1f9a41b0eb273f65e174aff37c367a"
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
        self.managedCoreSHA256 = managedCoreSHA256
        self.launchDaemonEnabled = launchDaemonEnabled
        self.autoSetSystemDNS = autoSetSystemDNS
        self.systemDNSServers = systemDNSServers
        self.externalUIEnabled = externalUIEnabled
        self.externalUIName = externalUIName
        self.externalUIDownloadURL = externalUIDownloadURL
        self.externalUISHA256 = externalUISHA256
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
        self.geoIPSHA256 = geoIPSHA256
        self.geoSiteSHA256 = geoSiteSHA256
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
        self.ageDownloadSHA256 = ageDownloadSHA256
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
        case managedCoreSHA256
        case launchDaemonEnabled
        case autoSetSystemDNS
        case systemDNSServers
        case externalUIEnabled
        case externalUIName
        case externalUIDownloadURL
        case externalUISHA256
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
        case geoIPSHA256
        case geoSiteSHA256
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
        case ageDownloadSHA256
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
        managedCoreSHA256 = try container.decodeIfPresent(String.self, forKey: .managedCoreSHA256) ?? fallback.managedCoreSHA256
        launchDaemonEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchDaemonEnabled) ?? fallback.launchDaemonEnabled
        autoSetSystemDNS = try container.decodeIfPresent(Bool.self, forKey: .autoSetSystemDNS) ?? fallback.autoSetSystemDNS
        systemDNSServers = try container.decodeIfPresent([String].self, forKey: .systemDNSServers) ?? fallback.systemDNSServers
        externalUIEnabled = try container.decodeIfPresent(Bool.self, forKey: .externalUIEnabled) ?? fallback.externalUIEnabled
        externalUIName = try container.decodeIfPresent(String.self, forKey: .externalUIName) ?? fallback.externalUIName
        externalUIDownloadURL = try container.decodeIfPresent(String.self, forKey: .externalUIDownloadURL) ?? fallback.externalUIDownloadURL
        externalUISHA256 = try container.decodeIfPresent(String.self, forKey: .externalUISHA256) ?? fallback.externalUISHA256
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
        geoIPSHA256 = try container.decodeIfPresent(String.self, forKey: .geoIPSHA256) ?? fallback.geoIPSHA256
        geoSiteSHA256 = try container.decodeIfPresent(String.self, forKey: .geoSiteSHA256) ?? fallback.geoSiteSHA256
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
        ageDownloadSHA256 = try container.decodeIfPresent(String.self, forKey: .ageDownloadSHA256) ?? fallback.ageDownloadSHA256
    }

    private static func migratedCoreSource(legacyManagedCoreEnabled: Bool?, mihomoPath: String) -> CoreSource {
        if legacyManagedCoreEnabled == true {
            return .managed
        }
        return mihomoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .managed : .local
    }
}

