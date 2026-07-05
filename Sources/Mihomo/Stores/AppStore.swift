import AppKit
import Combine
import Foundation

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

    private let profileStore = ProfileStore()
    private let coreManager = CoreManager()
    private let systemProxy = SystemProxyManager()
    private var pollingTask: Task<Void, Never>?
    private var profileRefreshTask: Task<Void, Never>?
    private var lastUploadTotal: Int64?
    private var lastDownloadTotal: Int64?
    private var lastTrafficSampleAt: Date?
    private var isExpectedCoreExit = false
    private var shutdownRequested = false
    private var crashRestartCount = 0

    var activeProfile: ProfileItem? {
        profiles.first { $0.id == settings.activeProfileID } ?? profiles.first
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
            if settings.activeProfileID == nil {
                settings.activeProfileID = profiles.first?.id
                try profileStore.saveSettings(settings)
            }
            lastSystemProxySnapshot = systemProxy.loadSnapshot()
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
            if coreManager.isRunning {
                isExpectedCoreExit = true
                coreManager.stop()
                try? await Task.sleep(nanoseconds: 400_000_000)
                isExpectedCoreExit = false
            }

            let candidate = try profileStore.generateRuntimeConfigCandidate(profile: activeProfile, settings: settings)
            let validation = try coreManager.validateConfig(
                mihomoPath: settings.mihomoPath,
                configPath: candidate,
                workDirectory: AppPaths.runtimeDirectory
            )
            lastRuntimeValidation = validation.isEmpty ? "mihomo 配置校验通过" : validation
            try profileStore.promoteRuntimeConfig(candidate: candidate)

            try coreManager.start(
                mihomoPath: settings.mihomoPath,
                configPath: AppPaths.runtimeConfigFile,
                workDirectory: AppPaths.runtimeDirectory,
                onLog: { [weak self] text in
                    self?.appendLog("core", text.trimmingCharacters(in: .whitespacesAndNewlines))
                },
                onExit: { [weak self] status in
                    self?.handleCoreExit(status)
                }
            )

            isCoreRunning = true
            coreStatus = "启动中"
            appendLog("info", "已用 \(AppPaths.runtimeConfigFile.path) 启动 mihomo")
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
        coreManager.stop()
        isCoreRunning = false
        coreStatus = "已停止"
        appendLog("info", "已停止 mihomo")
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
        let client = MihomoControllerClient(host: settings.controllerHost, port: settings.controllerPort)
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
            let client = MihomoControllerClient(host: settings.controllerHost, port: settings.controllerPort)
            try await client.setMode(mode)
            currentMode = mode
            appendLog("info", "出站模式已切换为 \(mode)")
        } catch {
            appendLog("error", "模式切换失败：\(error.localizedDescription)")
        }
    }

    func selectProxy(group: String, proxy: String) async {
        do {
            let client = MihomoControllerClient(host: settings.controllerHost, port: settings.controllerPort)
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
            let client = MihomoControllerClient(host: settings.controllerHost, port: settings.controllerPort)
            let delay = try await client.proxyDelay(proxy: proxy, url: settings.delayTestURL)
            updateDelay(group: group, proxy: proxy, delay: delay)
            appendLog("info", "\(proxy) 延迟：\(delay) ms")
        } catch {
            appendLog("error", "\(proxy) 延迟测试失败：\(error.localizedDescription)")
        }
    }

    func closeAllConnections() async {
        do {
            let client = MihomoControllerClient(host: settings.controllerHost, port: settings.controllerPort)
            try await client.closeConnections()
            connections = []
            appendLog("info", "已关闭所有连接")
        } catch {
            appendLog("error", "关闭连接失败：\(error.localizedDescription)")
        }
    }

    func closeConnection(_ id: String) async {
        do {
            let client = MihomoControllerClient(host: settings.controllerHost, port: settings.controllerPort)
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
                try systemProxy.disable()
                systemProxyEnabled = false
                lastSystemProxySnapshot = nil
                appendLog("info", "系统代理已恢复到原配置")
            } else {
                try systemProxy.enable(host: "127.0.0.1", port: settings.mixedPort, socksPort: settings.socksPort)
                systemProxyEnabled = true
                lastSystemProxySnapshot = systemProxy.loadSnapshot()
                appendLog("info", "系统代理已开启，并保存了原配置快照")
            }
        } catch {
            appendLog("error", "系统代理操作失败：\(error.localizedDescription)")
        }
    }

    func repairSystemProxy() async {
        do {
            try systemProxy.repairFromSnapshot()
            systemProxyEnabled = false
            lastSystemProxySnapshot = nil
            appendLog("info", "已根据快照修复系统代理/DNS 设置")
        } catch {
            appendLog("error", "系统代理修复失败：\(error.localizedDescription)")
        }
    }

    func addRemoteProfile() async {
        let url = newRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        do {
            let item = try await profileStore.importRemoteProfile(
                urlString: url,
                name: newRemoteName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            profiles.append(item)
            settings.activeProfileID = item.id
            try profileStore.saveProfiles(profiles)
            try profileStore.saveSettings(settings)
            newRemoteURL = ""
            newRemoteName = ""
            appendLog("info", "已导入远程订阅 \(item.name)")
        } catch {
            appendLog("error", "远程订阅导入失败：\(error.localizedDescription)")
        }
    }

    func importLocalProfile(url: URL) async {
        do {
            let item = try profileStore.importLocalProfile(fileURL: url)
            profiles.append(item)
            settings.activeProfileID = item.id
            try profileStore.saveProfiles(profiles)
            try profileStore.saveSettings(settings)
            appendLog("info", "已导入本地配置 \(item.name)")
        } catch {
            appendLog("error", "本地配置导入失败：\(error.localizedDescription)")
        }
    }

    func refreshProfile(_ profile: ProfileItem) async {
        do {
            let updated = try await profileStore.refreshRemoteProfile(profile)
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = updated
                try profileStore.saveProfiles(profiles)
            }
            appendLog("info", "已刷新配置 \(profile.name)")
        } catch {
            appendLog("error", "配置刷新失败：\(error.localizedDescription)")
        }
    }

    func refreshAllRemoteProfiles() async {
        let remoteProfiles = profiles.filter(\.isRemote)
        guard remoteProfiles.isEmpty == false else {
            profileAutoRefreshStatus = "没有远程订阅"
            return
        }

        var refreshed = 0
        for profile in remoteProfiles {
            let before = profiles
            await refreshProfile(profile)
            if profiles != before {
                refreshed += 1
            }
        }
        profileAutoRefreshStatus = "上次刷新：\(Formatters.shortDate.string(from: Date()))，成功 \(refreshed)/\(remoteProfiles.count)"
    }

    func setActiveProfile(_ profile: ProfileItem) async {
        settings.activeProfileID = profile.id
        do {
            try profileStore.saveSettings(settings)
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
            return try profileStore.loadProfileContent(profile)
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
            let updated = try profileStore.saveProfileContent(profile, content: content)
            profiles[index] = updated
            try profileStore.saveProfiles(profiles)
            appendLog("info", "已保存配置 \(updated.name)")
        } catch {
            appendLog("error", "保存配置失败：\(error.localizedDescription)")
        }
    }

    func saveSettings(_ settings: AppSettings) async {
        do {
            self.settings = settings
            try profileStore.saveSettings(settings)
            startProfileAutoRefreshIfNeeded()
            if settings.lightweightMode {
                enterLightweightMode()
            }
            appendLog("info", "设置已保存")
        } catch {
            appendLog("error", "设置保存失败：\(error.localizedDescription)")
        }
    }

    func runDiagnostics() async {
        var results: [DiagnosticResult] = []

        if FileManager.default.isExecutableFile(atPath: settings.mihomoPath) {
            results.append(.init(title: "mihomo 可执行文件", detail: settings.mihomoPath, state: .ok))
            if let version = try? Shell.run(settings.mihomoPath, ["-v"]) {
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
                let candidate = try profileStore.generateRuntimeConfigCandidate(profile: activeProfile, settings: settings)
                _ = try coreManager.validateConfig(mihomoPath: settings.mihomoPath, configPath: candidate, workDirectory: AppPaths.runtimeDirectory)
                results.append(.init(title: "运行配置 dry-run", detail: "mihomo -t 校验通过：\(candidate.path)", state: .ok))
            } catch {
                results.append(.init(title: "运行配置 dry-run", detail: error.localizedDescription, state: .failed))
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

        if settings.tunEnabled {
            results.append(.init(
                title: "TUN 模式",
                detail: "已写入 mihomo runtime overlay。第三 MVP 会诊断权限与保留系统代理/DNS 回滚点；完整路由回滚仍需要后续 Helper。",
                state: .warning
            ))
        } else {
            results.append(.init(title: "TUN 模式", detail: "未启用。", state: .ok))
        }

        do {
            let client = MihomoControllerClient(host: settings.controllerHost, port: settings.controllerPort)
            let version = try await client.version()
            let mode = try await client.configMode()
            results.append(.init(title: "Controller", detail: "已连接，版本 \(version)，模式 \(mode)", state: .ok))
        } catch {
            results.append(.init(title: "Controller", detail: error.localizedDescription, state: isCoreRunning ? .failed : .warning))
        }

        results.append(.init(
            title: "日志文件",
            detail: FileManager.default.fileExists(atPath: AppPaths.appLogFile.path) ? AppPaths.appLogFile.path : "日志文件将在下一条日志写入时创建。",
            state: .ok
        ))

        results.append(.init(
            title: "订阅自动刷新",
            detail: settings.autoRefreshProfiles ? profileAutoRefreshStatus : "未启用。",
            state: settings.autoRefreshProfiles ? .ok : .warning
        ))

        diagnostics = results
        selectedSection = .diagnostics
    }

    func appendLog(_ level: String, _ message: String) {
        guard !message.isEmpty else { return }
        for line in message.split(separator: "\n", omittingEmptySubsequences: true) {
            let entry = LogEntry(level: level, message: String(line))
            logs.append(entry)
            persistLog(entry)
        }
        if logs.count > 1_200 {
            logs.removeFirst(logs.count - 1_200)
        }
    }

    func enterLightweightMode() {
        NSApp.hide(nil)
        appendLog("info", "已进入轻量模式，主窗口隐藏，菜单栏保留。")
    }

    func shutdown() async {
        shutdownRequested = true
        profileRefreshTask?.cancel()
        if settings.restoreSystemProxyOnQuit, systemProxyEnabled {
            try? systemProxy.disable()
        }
        coreManager.stop()
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
        let data = Data(line.utf8)
        if FileManager.default.fileExists(atPath: AppPaths.appLogFile.path) == false {
            FileManager.default.createFile(atPath: AppPaths.appLogFile.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: AppPaths.appLogFile) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        handle.write(data)
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
