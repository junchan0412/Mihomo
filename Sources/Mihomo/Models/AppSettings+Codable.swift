import Foundation

extension AppSettings {
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
        notifyProfileRefreshFailures = try container.decodeIfPresent(Bool.self, forKey: .notifyProfileRefreshFailures) ?? fallback.notifyProfileRefreshFailures
        lightweightMode = try container.decodeIfPresent(Bool.self, forKey: .lightweightMode) ?? fallback.lightweightMode
        restoreSystemProxyOnQuit = try container.decodeIfPresent(Bool.self, forKey: .restoreSystemProxyOnQuit) ?? fallback.restoreSystemProxyOnQuit
        delayTestURL = try container.decodeIfPresent(String.self, forKey: .delayTestURL) ?? fallback.delayTestURL
        directDelayTestURL = try container.decodeIfPresent(String.self, forKey: .directDelayTestURL) ?? fallback.directDelayTestURL
        delayTestTimeoutMS = try container.decodeIfPresent(Int.self, forKey: .delayTestTimeoutMS) ?? fallback.delayTestTimeoutMS
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? fallback.launchAtLogin
        restoreTunOnStop = try container.decodeIfPresent(Bool.self, forKey: .restoreTunOnStop) ?? fallback.restoreTunOnStop
        profileRefreshMaxConcurrent = try container.decodeIfPresent(Int.self, forKey: .profileRefreshMaxConcurrent) ?? fallback.profileRefreshMaxConcurrent
        resourceUpdateMaxConcurrent = try container.decodeIfPresent(Int.self, forKey: .resourceUpdateMaxConcurrent) ?? fallback.resourceUpdateMaxConcurrent
        delayTestConcurrency = try container.decodeIfPresent(Int.self, forKey: .delayTestConcurrency) ?? fallback.delayTestConcurrency
        logRetentionDays = try container.decodeIfPresent(Int.self, forKey: .logRetentionDays) ?? fallback.logRetentionDays
        logMaxFileSizeMB = try container.decodeIfPresent(Int.self, forKey: .logMaxFileSizeMB) ?? fallback.logMaxFileSizeMB
        showMenuBarTrafficRates = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarTrafficRates) ?? fallback.showMenuBarTrafficRates
        managedCoreEnabled = legacyManagedCoreEnabled ?? (coreSource == .managed)
        managedCoreDownloadURL = try container.decodeIfPresent(String.self, forKey: .managedCoreDownloadURL) ?? fallback.managedCoreDownloadURL
        managedCoreSHA256 = try container.decodeIfPresent(String.self, forKey: .managedCoreSHA256) ?? fallback.managedCoreSHA256
        launchDaemonEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchDaemonEnabled) ?? fallback.launchDaemonEnabled
        dnsEnabled = try container.decodeIfPresent(Bool.self, forKey: .dnsEnabled) ?? fallback.dnsEnabled
        autoSetSystemDNS = try container.decodeIfPresent(Bool.self, forKey: .autoSetSystemDNS) ?? fallback.autoSetSystemDNS
        systemProxyGuardEnabled = try container.decodeIfPresent(Bool.self, forKey: .systemProxyGuardEnabled) ?? fallback.systemProxyGuardEnabled
        systemDNSServers = try container.decodeIfPresent([String].self, forKey: .systemDNSServers) ?? fallback.systemDNSServers
        remoteAPIEnabled = try container.decodeIfPresent(Bool.self, forKey: .remoteAPIEnabled) ?? fallback.remoteAPIEnabled
        remoteAPIBindAddress = try container.decodeIfPresent(String.self, forKey: .remoteAPIBindAddress) ?? fallback.remoteAPIBindAddress
        controllerSecret = try container.decodeIfPresent(String.self, forKey: .controllerSecret) ?? fallback.controllerSecret
        yamlOverrideEnabled = try container.decodeIfPresent(Bool.self, forKey: .yamlOverrideEnabled) ?? fallback.yamlOverrideEnabled
        jsOverrideEnabled = try container.decodeIfPresent(Bool.self, forKey: .jsOverrideEnabled) ?? fallback.jsOverrideEnabled
        snifferManagedByApp = try container.decodeIfPresent(Bool.self, forKey: .snifferManagedByApp) ?? fallback.snifferManagedByApp
        snifferEnabled = try container.decodeIfPresent(Bool.self, forKey: .snifferEnabled) ?? fallback.snifferEnabled
        snifferPorts = try container.decodeIfPresent(String.self, forKey: .snifferPorts) ?? fallback.snifferPorts
        snifferParsePureIP = try container.decodeIfPresent(Bool.self, forKey: .snifferParsePureIP) ?? fallback.snifferParsePureIP
        snifferForceDNSMapping = try container.decodeIfPresent(Bool.self, forKey: .snifferForceDNSMapping) ?? fallback.snifferForceDNSMapping
        snifferOverrideDestination = try container.decodeIfPresent(Bool.self, forKey: .snifferOverrideDestination) ?? fallback.snifferOverrideDestination
        snifferHTTPPorts = try container.decodeIfPresent(String.self, forKey: .snifferHTTPPorts) ?? fallback.snifferHTTPPorts
        snifferTLSPorts = try container.decodeIfPresent(String.self, forKey: .snifferTLSPorts) ?? fallback.snifferTLSPorts
        snifferQUICPorts = try container.decodeIfPresent(String.self, forKey: .snifferQUICPorts) ?? fallback.snifferQUICPorts
        snifferForceDomains = try container.decodeIfPresent(String.self, forKey: .snifferForceDomains) ?? fallback.snifferForceDomains
        snifferSkipDomains = try container.decodeIfPresent(String.self, forKey: .snifferSkipDomains) ?? fallback.snifferSkipDomains
        snifferSkipDestinationAddresses = try container.decodeIfPresent(String.self, forKey: .snifferSkipDestinationAddresses) ?? fallback.snifferSkipDestinationAddresses
        snifferSkipSourceAddresses = try container.decodeIfPresent(String.self, forKey: .snifferSkipSourceAddresses) ?? fallback.snifferSkipSourceAddresses
        dnsEnhancedMode = try container.decodeIfPresent(String.self, forKey: .dnsEnhancedMode) ?? fallback.dnsEnhancedMode
        dnsNameservers = try container.decodeIfPresent([String].self, forKey: .dnsNameservers) ?? fallback.dnsNameservers
        dnsFallbacks = try container.decodeIfPresent([String].self, forKey: .dnsFallbacks) ?? fallback.dnsFallbacks
        geoIPURL = try container.decodeIfPresent(String.self, forKey: .geoIPURL) ?? fallback.geoIPURL
        geoSiteURL = try container.decodeIfPresent(String.self, forKey: .geoSiteURL) ?? fallback.geoSiteURL
        countryMMDBURL = try container.decodeIfPresent(String.self, forKey: .countryMMDBURL) ?? fallback.countryMMDBURL
        asnMMDBURL = try container.decodeIfPresent(String.self, forKey: .asnMMDBURL) ?? fallback.asnMMDBURL
        geoIPSHA256 = try container.decodeIfPresent(String.self, forKey: .geoIPSHA256) ?? fallback.geoIPSHA256
        geoSiteSHA256 = try container.decodeIfPresent(String.self, forKey: .geoSiteSHA256) ?? fallback.geoSiteSHA256
        countryMMDBSHA256 = try container.decodeIfPresent(String.self, forKey: .countryMMDBSHA256) ?? fallback.countryMMDBSHA256
        asnMMDBSHA256 = try container.decodeIfPresent(String.self, forKey: .asnMMDBSHA256) ?? fallback.asnMMDBSHA256
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
