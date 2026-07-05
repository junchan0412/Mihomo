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
    @Published var lastTunRecoverySnapshot: TunRecoverySnapshot?
    @Published var tunRecoveryStatus = "未捕获 TUN 回滚快照"
    @Published var loginItemStatus = "未检查"
    @Published var profileRefreshQueue: [ProfileRefreshJob] = []
    @Published var profileRefreshFailureCount = 0
    @Published var delayTestStatus = "未运行"
    @Published var logsPaused = false
    @Published var bufferedLogCount = 0
    @Published var configFragments: [ConfigFragment] = []
    @Published var disabledRules: Set<String> = []
    @Published var rules: [RuleItem] = []
    @Published var providers: [ProviderItem] = []
    @Published var configPreview = ""
    @Published var configDiff = ""
    @Published var advancedStatus = "高级功能待命"
    @Published var managedCoreStatus = "未托管"
    @Published var externalUIStatus = "未安装"
    @Published var geoUpdateStatus = "未更新"
    @Published var backupStatus = "未备份"
    @Published var ageStatus = "Profile 加密未启用"
    @Published var launchDaemonStatus = "未安装"
    @Published var helperStatus = "Helper 未检查"
    @Published var softwareUpdateStatus = "未检查"
    @Published var availableUpdate: AppUpdateManifest?

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
    private var lastLogPruneAt: Date?

    var activeProfile: ProfileItem? {
        profiles.first { $0.id == settings.activeProfileID } ?? profiles.first
    }

    var effectiveMihomoPath: String {
        if settings.managedCoreEnabled,
           FileManager.default.isExecutableFile(atPath: AppPaths.managedCoreFile.path) {
            return AppPaths.managedCoreFile.path
        }
        if settings.mihomoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return settings.mihomoPath
        }
        if let bundled = ManagedCoreManager.bundledCorePath,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        return settings.mihomoPath
    }

    var menuBarTitle: String {
        let state = isCoreRunning ? "开" : "关"
        return "Mihomo \(state) ↓\(Formatters.rate(downloadRate))"
    }

    func bootstrap() async {
        do {
            try AppPaths.ensureBaseDirectories()
            settings = try profileStore.loadSettings()
            profiles = try profileStore.loadProfiles()
            configFragments = try configFragmentStore.loadFragments()
            disabledRules = try configFragmentStore.loadDisabledRules()
            if settings.activeProfileID == nil {
                settings.activeProfileID = profiles.first?.id
                try profileStore.saveSettings(settings)
            }
            lastSystemProxySnapshot = systemProxy.loadSnapshot()
            lastTunRecoverySnapshot = tunRecovery.loadSnapshot()
            tunRecoveryStatus = lastTunRecoverySnapshot == nil ? "未捕获 TUN 回滚快照" : "已有 TUN 回滚快照"
            managedCoreStatus = FileManager.default.isExecutableFile(atPath: AppPaths.managedCoreFile.path) ? AppPaths.managedCoreFile.path : (ManagedCoreManager.bundledCorePath ?? "未托管")
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
            let result = try await helperClient.prepareAndStartCore(
                mihomoPath: mihomoPath,
                configPath: AppPaths.runtimeConfigFile,
                workDirectory: AppPaths.runtimeDirectory,
                logPath: AppPaths.coreLogFile,
                autoSetDNS: settings.autoSetSystemDNS,
                dnsServers: settings.systemDNSServers,
                captureTun: settings.tunEnabled
            )
            if let validation = result.payload["validation"], validation.isEmpty == false {
                lastRuntimeValidation = validation
            } else {
                lastRuntimeValidation = "mihomo 配置校验通过"
            }
            if settings.autoSetSystemDNS {
                lastSystemProxySnapshot = systemProxy.loadSnapshot()
                appendLog("info", "Helper 已临时设置系统 DNS：\(settings.systemDNSServers.joined(separator: "、"))")
            }
            if settings.tunEnabled {
                lastTunRecoverySnapshot = tunRecovery.loadSnapshot()
                if let tunDetail = result.payload["tunDetail"], tunDetail.isEmpty == false {
                    tunRecoveryStatus = tunDetail
                } else {
                    tunRecoveryStatus = "Helper 已捕获 TUN 回滚快照"
                }
                appendLog("info", tunRecoveryStatus)
            }

            isCoreRunning = true
            coreStatus = "启动中"
            appendLog("info", "\(result.message)：\(AppPaths.runtimeConfigFile.path)")
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshController()
        } catch {
            coreStatus = "启动失败"
            try? profileStore.restoreRuntimeBackup()
            appendLog("error", "启动失败：\(error.localizedDescription)")
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
            lastSystemProxySnapshot = systemProxy.loadSnapshot()
            lastTunRecoverySnapshot = tunRecovery.loadSnapshot()
            if settings.tunEnabled && settings.restoreTunOnStop {
                tunRecoveryStatus = result.message
            }
            appendLog("info", result.message)
        } catch {
            isCoreRunning = false
            coreStatus = "停止失败"
            appendLog("error", "Helper 停止核心失败：\(error.localizedDescription)")
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        isExpectedCoreExit = false
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
            coreVersion = try await version
            currentMode = try await mode
            proxyGroups = try await groups
            let (items, up, down) = try await connectionResult
            connections = items
            updateRuleProviderHitStatistics()
            updateTrafficRates(uploadTotal: up, downloadTotal: down)
            if isCoreRunning {
                crashRestartCount = 0
                coreStatus = "运行中"
            }
        } catch {
            if isCoreRunning {
                coreStatus = "控制器不可用"
            }
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
        do {
            let client = controllerClient()
            let delay = try await client.proxyDelay(proxy: proxy, url: settings.delayTestURL)
            updateDelay(group: group, proxy: proxy, delay: delay)
            delayTestStatus = "\(proxy)：\(delay) ms"
            appendLog("info", "\(proxy) 延迟：\(delay) ms")
        } catch {
            delayTestStatus = "\(proxy) 延迟测试失败"
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
                appendLog("info", result.message)
            } else {
                let result = try await helperClient.setSystemProxy(host: "127.0.0.1", mixedPort: settings.mixedPort, socksPort: settings.socksPort)
                systemProxyEnabled = true
                lastSystemProxySnapshot = systemProxy.loadSnapshot()
                appendLog("info", result.message)
            }
        } catch {
            appendLog("error", "Helper 系统代理操作失败：\(error.localizedDescription)")
        }
    }

    func repairSystemProxy() async {
        do {
            let result = try await helperClient.restoreSystemProxy()
            systemProxyEnabled = false
            lastSystemProxySnapshot = systemProxy.loadSnapshot()
            appendLog("info", result.message)
        } catch {
            appendLog("error", "Helper 系统代理修复失败：\(error.localizedDescription)")
        }
    }

    func restoreTunRecovery() async {
        do {
            let result = try await helperClient.restoreTunSnapshot()
            lastTunRecoverySnapshot = tunRecovery.loadSnapshot()
            tunRecoveryStatus = result.message
            systemProxyEnabled = false
            lastSystemProxySnapshot = systemProxy.loadSnapshot()
            appendLog("info", result.message)
        } catch {
            tunRecoveryStatus = "TUN 回滚失败：\(error.localizedDescription)"
            appendLog("error", tunRecoveryStatus)
        }
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

    func saveSettings(_ settings: AppSettings) async {
        do {
            let previous = self.settings
            if previous.profileEncryptionEnabled != settings.profileEncryptionEnabled {
                try profileStore.migrateProfileEncryption(profiles, settings: settings)
            }
            self.settings = settings
            try profileStore.saveSettings(settings)
            ageStatus = settings.profileEncryptionEnabled ? "Profile 加密已启用" : "Profile 加密未启用"
            syncLaunchAtLoginSetting(reportSuccess: true)
            startProfileAutoRefreshIfNeeded()
            if settings.lightweightMode {
                enterLightweightMode()
            }
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
            let file = profileStore.profileFile(activeProfile)
            let exists = FileManager.default.fileExists(atPath: file.path)
            results.append(.init(title: "当前配置", detail: exists ? activeProfile.name : "配置文件丢失", state: exists ? .ok : .failed))
            do {
                let candidate = try profileStore.generateRuntimeConfigCandidate(
                    profile: activeProfile,
                    settings: settings,
                    fragments: configFragments,
                    disabledRules: disabledRules
                )
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

        if let snapshot = systemProxy.loadSnapshot() {
            results.append(.init(
                title: "系统代理快照",
                detail: "已保存 \(snapshot.services.count) 个网络服务的原代理/DNS 状态，可一键修复。",
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
                    detail: "已保存 \(snapshot.ipv4Routes.count) 条 IPv4 路由、\(snapshot.ipv6Routes.count) 条 IPv6 路由和 \(snapshot.proxySnapshot.services.count) 个网络服务状态。",
                    state: .ok
                ))
            } else {
                results.append(.init(
                    title: "TUN 回滚快照",
                    detail: "尚未捕获快照。启动 TUN 核心前会自动捕获 DNS、代理和路由状态。",
                    state: .warning
                ))
            }
            results.append(.init(
                title: "TUN 模式",
                detail: "已写入 mihomo runtime overlay。可通过诊断页验证管理员授权，并在停止/退出或手动操作时回滚 DNS/路由。",
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
            title: "托管/内置核心",
            detail: "当前有效路径：\(mihomoPath)\n托管路径：\(AppPaths.managedCoreFile.path)\n内置路径：\(ManagedCoreManager.bundledCorePath ?? "未随包提供")",
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
            helperStatus = "\(helperService.statusDescription)：\(error.localizedDescription)"
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

    func refreshConfigArtifacts() {
        guard let activeProfile else {
            rules = []
            providers = []
            configPreview = ""
            configDiff = ""
            return
        }

        do {
            let original = try profileStore.loadProfileContent(activeProfile, settings: settings)
            rules = configFragmentStore.parseRules(profileContent: original, disabledRules: disabledRules)
            providers = configFragmentStore.parseProviders(profileContent: original)
            let candidate = try profileStore.generateRuntimeConfigCandidate(
                profile: activeProfile,
                settings: settings,
                fragments: configFragments,
                disabledRules: disabledRules
            )
            configPreview = try String(contentsOf: candidate, encoding: .utf8)
            configDiff = configFragmentStore.makeDiff(original: original, generated: configPreview)
            updateRuleProviderHitStatistics()
            advancedStatus = "配置预览已更新：\(Formatters.shortDate.string(from: Date()))"
        } catch {
            advancedStatus = "配置预览失败：\(error.localizedDescription)"
            appendLog("error", advancedStatus)
        }
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
            await refreshProvidersFromController()
        } catch {
            appendLog("error", "Provider 更新失败：\(error.localizedDescription)")
        }
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
            updated.managedCoreEnabled = true
            if updated.mihomoPath.isEmpty {
                updated.mihomoPath = AppPaths.managedCoreFile.path
            }
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
            geoUpdateStatus = try await geoUpdateManager.update(geoIPURL: settings.geoIPURL, geoSiteURL: settings.geoSiteURL)
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
            helperStatus = "\(helperService.statusDescription)：\(error.localizedDescription)"
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
        do {
            helperStatus = "正在重建 Helper 注册"
            try? helperService.unregister()
            try? await Task.sleep(nanoseconds: 400_000_000)
            try helperService.register()
            appendLog("info", "XPC Helper 注册已重建")
            try? await Task.sleep(nanoseconds: 800_000_000)
            await auditHelper()
        } catch {
            helperStatus = "XPC Helper 修复失败：\(error.localizedDescription)"
            appendLog("error", helperStatus)
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
            try profileStore.promoteRuntimeConfig(candidate: candidate)
            let result = try await helperClient.installCoreLaunchDaemon(
                corePath: effectiveMihomoPath,
                configPath: AppPaths.runtimeConfigFile,
                workDirectory: AppPaths.runtimeDirectory,
                logPath: AppPaths.coreLogFile
            )
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
            softwareUpdateStatus = "正在检查更新"
            let result = try await softwareUpdateManager.checkForUpdate(manifestURLString: settings.softwareUpdateManifestURL)
            if result.isNewer {
                availableUpdate = result.manifest
                softwareUpdateStatus = "发现 \(result.manifest.version)，当前 \(result.currentVersion)"
            } else {
                availableUpdate = nil
                softwareUpdateStatus = "已是最新：\(result.currentVersion)"
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
            if let availableUpdate {
                manifest = availableUpdate
            } else {
                let result = try await softwareUpdateManager.checkForUpdate(manifestURLString: settings.softwareUpdateManifestURL)
                guard result.isNewer else {
                    softwareUpdateStatus = "已是最新：\(result.currentVersion)"
                    return
                }
                manifest = result.manifest
            }

            softwareUpdateStatus = "正在下载 \(manifest.version)"
            let message = try await softwareUpdateManager.installUpdate(manifest, manifestURLString: settings.softwareUpdateManifestURL)
            softwareUpdateStatus = message
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
                logs.append(entry)
            }
        }
        if logs.count > 1_200 {
            logs.removeFirst(logs.count - 1_200)
        }
    }

    func setLogsPaused(_ paused: Bool) {
        logsPaused = paused
        if paused == false, bufferedLogs.isEmpty == false {
            logs.append(contentsOf: bufferedLogs)
            if logs.count > 1_200 {
                logs.removeFirst(logs.count - 1_200)
            }
            bufferedLogs.removeAll()
            bufferedLogCount = 0
        }
        appendLog("info", paused ? "日志流已暂停，仍会继续落盘。" : "日志流已继续。")
    }

    func toggleLogPause() {
        setLogsPaused(!logsPaused)
    }

    func enterLightweightMode() {
        NSApp.hide(nil)
        appendLog("info", "已进入轻量模式，主窗口隐藏，菜单栏保留。")
    }

    func shutdown() async {
        shutdownRequested = true
        profileRefreshTask?.cancel()
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

    private func reloadPersistentState() throws {
        settings = try profileStore.loadSettings()
        profiles = try profileStore.loadProfiles()
        configFragments = try configFragmentStore.loadFragments()
        disabledRules = try configFragmentStore.loadDisabledRules()
        refreshConfigArtifacts()
    }

    private func makeBackupPayload() throws -> BackupPayload {
        let contents = Dictionary(uniqueKeysWithValues: try profiles.map { profile in
            (profile.fileName, try profileStore.loadProfileStoredContent(profile))
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
        for profile in profiles {
            if let content = payload.profileContents[profile.fileName] {
                try content.write(to: profileStore.profileFile(profile), atomically: true, encoding: .utf8)
            }
        }
        refreshConfigArtifacts()
    }

    private func updateRuleProviderHitStatistics() {
        let ruleHits = connections.reduce(into: [String: Int]()) { result, connection in
            let key = ruleHitKey(type: connection.ruleType, payload: connection.rulePayload)
            guard key.isEmpty == false else { return }
            result[key, default: 0] += 1
        }

        rules = rules.map { rule in
            var updated = rule
            updated.hitCount = ruleHits[ruleHitKey(content: rule.content), default: 0]
            return updated
        }

        let ruleProviderHits = connections.reduce(into: [String: Int]()) { result, connection in
            guard connection.ruleType.uppercased() == "RULE-SET",
                  connection.rulePayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            else { return }
            result[connection.rulePayload, default: 0] += 1
        }

        providers = providers.map { provider in
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
    }

    private func ruleHitKey(content: String) -> String {
        let parts = content.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.isEmpty == false else { return "" }
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
            uploadRate = 0
            downloadRate = 0
            appendTrafficSample()
            return
        }

        let interval = max(now.timeIntervalSince(lastAt), 0.1)
        uploadRate = max(0, Int64(Double(uploadTotal - lastUpload) / interval))
        downloadRate = max(0, Int64(Double(downloadTotal - lastDownload) / interval))
        lastTrafficSampleAt = now
        lastUploadTotal = uploadTotal
        lastDownloadTotal = downloadTotal
        appendTrafficSample()
    }

    private func appendTrafficSample() {
        trafficSamples.append(TrafficSample(uploadRate: uploadRate, downloadRate: downloadRate))
        if trafficSamples.count > 120 {
            trafficSamples.removeFirst(trafficSamples.count - 120)
        }
    }

    private func updateDelay(group: String, proxy: String, delay: Int) {
        guard let groupIndex = proxyGroups.firstIndex(where: { $0.name == group }),
              let proxyIndex = proxyGroups[groupIndex].all.firstIndex(where: { $0.name == proxy })
        else { return }
        proxyGroups[groupIndex].all[proxyIndex].delay = delay
        proxyGroups = proxyGroups
    }

    private func testPolicyRowsDelay(_ rows: [PolicyTableRow], label: String) async {
        guard rows.isEmpty == false else {
            delayTestStatus = "没有可测速节点"
            return
        }

        let maxConcurrent = max(1, settings.delayTestConcurrency)
        var pendingRows = rows
        var runningTasks: [Task<ProxyDelayResult, Never>] = []
        var completed = 0
        var succeeded = 0
        var failed = 0
        delayTestStatus = "\(label) 测速开始，并发 \(maxConcurrent)"

        while pendingRows.isEmpty == false || runningTasks.isEmpty == false {
            while runningTasks.count < maxConcurrent, pendingRows.isEmpty == false {
                let row = pendingRows.removeFirst()
                let host = settings.controllerHost
                let port = settings.controllerPort
                let secret = settings.controllerSecret
                let url = settings.delayTestURL
                runningTasks.append(Task {
                    let client = MihomoControllerClient(host: host, port: port, secret: secret)
                    do {
                        let delay = try await client.proxyDelay(proxy: row.node.name, url: url)
                        return ProxyDelayResult(group: row.group.name, proxy: row.node.name, delay: delay, errorMessage: nil)
                    } catch {
                        return ProxyDelayResult(group: row.group.name, proxy: row.node.name, delay: nil, errorMessage: error.localizedDescription)
                    }
                })
            }

            guard runningTasks.isEmpty == false else { break }
            let result = await runningTasks.removeFirst().value
            completed += 1
            if let delay = result.delay {
                succeeded += 1
                updateDelay(group: result.group, proxy: result.proxy, delay: delay)
            } else {
                failed += 1
                appendLog("warning", "\(result.proxy) 测速失败：\(result.errorMessage ?? "未知错误")")
            }
            delayTestStatus = "\(label)：\(completed)/\(rows.count)，成功 \(succeeded)，失败 \(failed)"
        }

        appendLog("info", "\(label) 测速完成：成功 \(succeeded)，失败 \(failed)")
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

    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshController()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
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
    var group: String
    var proxy: String
    var delay: Int?
    var errorMessage: String?
}
