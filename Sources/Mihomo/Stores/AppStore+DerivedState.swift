import Foundation

extension AppStore {
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

    var activeProfile: ProfileItem? {
        profiles.first { $0.id == settings.activeProfileID } ?? profiles.first
    }

    var pendingProfileRefreshPreview: RemoteProfileRefreshPreview? {
        pendingProfileRefreshPreviews.first
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
        if settings.tunEnabled && settings.autoSetSystemDNS {
            return "TUN 已通过 Mihomo DNS Hijacking 接管 DNS；同时开启的 macOS DNS 改写通常没有必要，仅建议用于特殊兼容场景。"
        }
        if systemProxyEnabled && settings.autoSetSystemDNS {
            return "系统代理与系统 DNS 接管同时开启；适合需要 DNS 统一出口的场景，退出前会尝试恢复快照。"
        }
        return nil
    }

    var helperInstallationDescription: String {
        legacyHelperInstaller.isInstalled ? "传统 Helper 已安装" : helperService.statusDescription
    }

    var shouldUseLegacyHelper: Bool {
        legacyHelperInstaller.bundledSMAppServiceIsSupported() == false
    }

    func controllerClient() -> MihomoControllerClient {
        MihomoControllerClient(
            host: settings.localControlHost,
            port: settings.controllerPort,
            secret: settings.controllerSecret
        )
    }

    func publishIfChanged<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<AppStore, Value>,
        _ value: Value
    ) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }
}
