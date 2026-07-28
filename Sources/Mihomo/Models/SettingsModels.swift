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
    var notifyProfileRefreshFailures: Bool
    var lightweightMode: Bool
    var restoreSystemProxyOnQuit: Bool
    var delayTestURL: String
    var directDelayTestURL: String
    var delayTestTimeoutMS: Int
    var launchAtLogin: Bool
    var restoreTunOnStop: Bool
    var profileRefreshMaxConcurrent: Int
    var resourceUpdateMaxConcurrent: Int
    var delayTestConcurrency: Int
    var logRetentionDays: Int
    var logMaxFileSizeMB: Int
    var showMenuBarTrafficRates: Bool
    var managedCoreEnabled: Bool
    var managedCoreDownloadURL: String
    var managedCoreSHA256: String
    var launchDaemonEnabled: Bool
    var dnsEnabled: Bool
    var autoSetSystemDNS: Bool
    var systemProxyGuardEnabled: Bool
    var systemDNSServers: [String]
    var remoteAPIEnabled: Bool
    var remoteAPIBindAddress: String
    var controllerSecret: String
    var yamlOverrideEnabled: Bool
    var jsOverrideEnabled: Bool
    var snifferManagedByApp: Bool
    var snifferEnabled: Bool
    var snifferPorts: String
    var snifferParsePureIP: Bool
    var snifferForceDNSMapping: Bool
    var snifferOverrideDestination: Bool
    var snifferHTTPPorts: String
    var snifferTLSPorts: String
    var snifferQUICPorts: String
    var snifferForceDomains: String
    var snifferSkipDomains: String
    var snifferSkipDestinationAddresses: String
    var snifferSkipSourceAddresses: String
    var dnsEnhancedMode: String
    var dnsNameservers: [String]
    var dnsFallbacks: [String]
    var geoIPURL: String
    var geoSiteURL: String
    var countryMMDBURL: String
    var asnMMDBURL: String
    var geoIPSHA256: String
    var geoSiteSHA256: String
    var countryMMDBSHA256: String
    var asnMMDBSHA256: String
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
        settingsSchemaVersion: Int = 9,
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
        notifyProfileRefreshFailures: Bool = false,
        lightweightMode: Bool = false,
        restoreSystemProxyOnQuit: Bool = true,
        delayTestURL: String = "https://cp.cloudflare.com/generate_204",
        directDelayTestURL: String = "https://www.gstatic.com/generate_204",
        delayTestTimeoutMS: Int = 8000,
        launchAtLogin: Bool = false,
        restoreTunOnStop: Bool = true,
        profileRefreshMaxConcurrent: Int = 2,
        resourceUpdateMaxConcurrent: Int = 4,
        delayTestConcurrency: Int = 6,
        logRetentionDays: Int = 7,
        logMaxFileSizeMB: Int = 8,
        showMenuBarTrafficRates: Bool = true,
        managedCoreEnabled: Bool? = nil,
        managedCoreDownloadURL: String = "https://github.com/MetaCubeX/mihomo/releases/download/v1.19.28/mihomo-darwin-arm64-v1.19.28.gz",
        managedCoreSHA256: String = "40cdae2fab4b18df15f40eaa9dc3af70ab3d8be7f77164ae1e5f1af3a2a4fb44",
        launchDaemonEnabled: Bool = false,
        dnsEnabled: Bool = true,
        autoSetSystemDNS: Bool = false,
        systemProxyGuardEnabled: Bool = true,
        systemDNSServers: [String] = ["1.1.1.1", "8.8.8.8"],
        remoteAPIEnabled: Bool = false,
        remoteAPIBindAddress: String = "127.0.0.1",
        controllerSecret: String = "",
        yamlOverrideEnabled: Bool = true,
        jsOverrideEnabled: Bool = false,
        snifferManagedByApp: Bool = true,
        snifferEnabled: Bool = true,
        snifferPorts: String = "80,443",
        snifferParsePureIP: Bool = true,
        snifferForceDNSMapping: Bool = true,
        snifferOverrideDestination: Bool = false,
        snifferHTTPPorts: String = "80,443",
        snifferTLSPorts: String = "443",
        snifferQUICPorts: String = "",
        snifferForceDomains: String = "",
        snifferSkipDomains: String = "+.push.apple.com",
        snifferSkipDestinationAddresses: String = "",
        snifferSkipSourceAddresses: String = "",
        dnsEnhancedMode: String = "fake-ip",
        dnsNameservers: [String] = ["https://1.1.1.1/dns-query", "https://dns.google/dns-query"],
        dnsFallbacks: [String] = [],
        geoIPURL: String = "https://github.com/MetaCubeX/meta-rules-dat/releases/latest/download/geoip.dat",
        geoSiteURL: String = "https://github.com/MetaCubeX/meta-rules-dat/releases/latest/download/geosite.dat",
        countryMMDBURL: String = "https://github.com/MetaCubeX/meta-rules-dat/releases/latest/download/country.mmdb",
        asnMMDBURL: String = "https://github.com/MetaCubeX/meta-rules-dat/releases/latest/download/GeoLite2-ASN.mmdb",
        geoIPSHA256: String = "",
        geoSiteSHA256: String = "",
        countryMMDBSHA256: String = "",
        asnMMDBSHA256: String = "",
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
        self.notifyProfileRefreshFailures = notifyProfileRefreshFailures
        self.lightweightMode = lightweightMode
        self.restoreSystemProxyOnQuit = restoreSystemProxyOnQuit
        self.delayTestURL = delayTestURL
        self.directDelayTestURL = directDelayTestURL
        self.delayTestTimeoutMS = delayTestTimeoutMS
        self.launchAtLogin = launchAtLogin
        self.restoreTunOnStop = restoreTunOnStop
        self.profileRefreshMaxConcurrent = profileRefreshMaxConcurrent
        self.resourceUpdateMaxConcurrent = resourceUpdateMaxConcurrent
        self.delayTestConcurrency = delayTestConcurrency
        self.logRetentionDays = logRetentionDays
        self.logMaxFileSizeMB = logMaxFileSizeMB
        self.showMenuBarTrafficRates = showMenuBarTrafficRates
        self.managedCoreEnabled = managedCoreEnabled ?? (coreSource == .managed)
        self.managedCoreDownloadURL = managedCoreDownloadURL
        self.managedCoreSHA256 = managedCoreSHA256
        self.launchDaemonEnabled = launchDaemonEnabled
        self.dnsEnabled = dnsEnabled
        self.autoSetSystemDNS = autoSetSystemDNS
        self.systemProxyGuardEnabled = systemProxyGuardEnabled
        self.systemDNSServers = systemDNSServers
        self.remoteAPIEnabled = remoteAPIEnabled
        self.remoteAPIBindAddress = remoteAPIBindAddress
        self.controllerSecret = controllerSecret
        self.yamlOverrideEnabled = yamlOverrideEnabled
        self.jsOverrideEnabled = jsOverrideEnabled
        self.snifferManagedByApp = snifferManagedByApp
        self.snifferEnabled = snifferEnabled
        self.snifferPorts = snifferPorts
        self.snifferParsePureIP = snifferParsePureIP
        self.snifferForceDNSMapping = snifferForceDNSMapping
        self.snifferOverrideDestination = snifferOverrideDestination
        self.snifferHTTPPorts = snifferHTTPPorts
        self.snifferTLSPorts = snifferTLSPorts
        self.snifferQUICPorts = snifferQUICPorts
        self.snifferForceDomains = snifferForceDomains
        self.snifferSkipDomains = snifferSkipDomains
        self.snifferSkipDestinationAddresses = snifferSkipDestinationAddresses
        self.snifferSkipSourceAddresses = snifferSkipSourceAddresses
        self.dnsEnhancedMode = dnsEnhancedMode
        self.dnsNameservers = dnsNameservers
        self.dnsFallbacks = dnsFallbacks
        self.geoIPURL = geoIPURL
        self.geoSiteURL = geoSiteURL
        self.countryMMDBURL = countryMMDBURL
        self.asnMMDBURL = asnMMDBURL
        self.geoIPSHA256 = geoIPSHA256
        self.geoSiteSHA256 = geoSiteSHA256
        self.countryMMDBSHA256 = countryMMDBSHA256
        self.asnMMDBSHA256 = asnMMDBSHA256
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

    enum CodingKeys: String, CodingKey {
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
        case notifyProfileRefreshFailures
        case lightweightMode
        case restoreSystemProxyOnQuit
        case delayTestURL
        case directDelayTestURL
        case delayTestTimeoutMS
        case launchAtLogin
        case restoreTunOnStop
        case profileRefreshMaxConcurrent
        case resourceUpdateMaxConcurrent
        case delayTestConcurrency
        case logRetentionDays
        case logMaxFileSizeMB
        case showMenuBarTrafficRates
        case managedCoreEnabled
        case managedCoreDownloadURL
        case managedCoreSHA256
        case launchDaemonEnabled
        case dnsEnabled
        case autoSetSystemDNS
        case systemProxyGuardEnabled
        case systemDNSServers
        case remoteAPIEnabled
        case remoteAPIBindAddress
        case controllerSecret
        case yamlOverrideEnabled
        case jsOverrideEnabled
        case snifferManagedByApp
        case snifferEnabled
        case snifferPorts
        case snifferParsePureIP
        case snifferForceDNSMapping
        case snifferOverrideDestination
        case snifferHTTPPorts
        case snifferTLSPorts
        case snifferQUICPorts
        case snifferForceDomains
        case snifferSkipDomains
        case snifferSkipDestinationAddresses
        case snifferSkipSourceAddresses
        case dnsEnhancedMode
        case dnsNameservers
        case dnsFallbacks
        case geoIPURL
        case geoSiteURL
        case countryMMDBURL
        case asnMMDBURL
        case geoIPSHA256
        case geoSiteSHA256
        case countryMMDBSHA256
        case asnMMDBSHA256
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

}

extension AppSettings {
    var localControlHost: String { "127.0.0.1" }
}
