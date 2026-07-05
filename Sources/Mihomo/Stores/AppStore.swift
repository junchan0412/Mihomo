import Foundation

@MainActor
final class AppStore {
    var selectedSection: AppSection = .overview { didSet { notify() } }
    var settings = AppSettings.default { didSet { notify() } }
    var profiles: [ProfileItem] = [] { didSet { notify() } }
    var isCoreRunning = false { didSet { notify() } }
    var coreStatus = "Stopped" { didSet { notify() } }
    var coreVersion = "unknown" { didSet { notify() } }
    var currentMode = "rule" { didSet { notify() } }
    var systemProxyEnabled = false { didSet { notify() } }
    var proxyGroups: [ProxyGroup] = [] { didSet { notify() } }
    var connections: [ConnectionItem] = [] { didSet { notify() } }
    var logs: [LogEntry] = [] { didSet { notify() } }
    var diagnostics: [DiagnosticResult] = [] { didSet { notify() } }
    var uploadRate: Int64 = 0 { didSet { notify() } }
    var downloadRate: Int64 = 0 { didSet { notify() } }
    var newRemoteURL = ""
    var newRemoteName = ""

    private let profileStore = ProfileStore()
    private let coreManager = CoreManager()
    private let systemProxy = SystemProxyManager()
    private var pollingTask: Task<Void, Never>?
    private var lastUploadTotal: Int64?
    private var lastDownloadTotal: Int64?
    private var lastTrafficSampleAt: Date?
    private var observers: [UUID: () -> Void] = [:]

    var activeProfile: ProfileItem? {
        profiles.first { $0.id == settings.activeProfileID } ?? profiles.first
    }

    var menuBarTitle: String {
        let state = isCoreRunning ? "On" : "Off"
        return "Mihomo \(state) ↓\(Formatters.rate(downloadRate))"
    }

    @discardableResult
    func observe(_ handler: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    func bootstrap() async {
        do {
            settings = try profileStore.loadSettings()
            profiles = try profileStore.loadProfiles()
            if settings.activeProfileID == nil {
                settings.activeProfileID = profiles.first?.id
                try profileStore.saveSettings(settings)
            }
            appendLog("info", "Loaded \(profiles.count) profile(s)")
            if settings.autoStartCore {
                await startCore()
            }
            startPolling()
            await refreshController()
        } catch {
            appendLog("error", "Bootstrap failed: \(error.localizedDescription)")
        }
    }

    func toggleCore() async {
        isCoreRunning ? await stopCore() : await startCore()
    }

    func startCore() async {
        guard let activeProfile else {
            appendLog("error", "No active profile")
            return
        }
        do {
            let config = try profileStore.generateRuntimeConfig(profile: activeProfile, settings: settings)
            try coreManager.start(
                mihomoPath: settings.mihomoPath,
                configPath: config,
                workDirectory: AppPaths.runtimeDirectory,
                onLog: { [weak self] text in
                    self?.appendLog("core", text.trimmingCharacters(in: .whitespacesAndNewlines))
                },
                onExit: { [weak self] status in
                    self?.isCoreRunning = false
                    self?.coreStatus = "Exited \(status)"
                    self?.appendLog("warning", "Core exited with status \(status)")
                }
            )
            isCoreRunning = true
            coreStatus = "Starting"
            appendLog("info", "Started mihomo with \(config.path)")
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshController()
        } catch {
            coreStatus = "Failed"
            appendLog("error", "Start failed: \(error.localizedDescription)")
        }
    }

    func stopCore() async {
        coreManager.stop()
        isCoreRunning = false
        coreStatus = "Stopped"
        appendLog("info", "Stopped mihomo")
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
                coreStatus = "Running"
            }
        } catch {
            if isCoreRunning {
                coreStatus = "Controller unavailable"
            }
        }
    }

    func setMode(_ mode: String) async {
        do {
            let client = MihomoControllerClient(host: settings.controllerHost, port: settings.controllerPort)
            try await client.setMode(mode)
            currentMode = mode
            appendLog("info", "Changed outbound mode to \(mode)")
        } catch {
            appendLog("error", "Mode change failed: \(error.localizedDescription)")
        }
    }

    func selectProxy(group: String, proxy: String) async {
        do {
            let client = MihomoControllerClient(host: settings.controllerHost, port: settings.controllerPort)
            try await client.selectProxy(group: group, proxy: proxy)
            if settings.closeConnectionsOnPolicyChange {
                try? await client.closeConnections()
            }
            appendLog("info", "Selected \(proxy) for \(group)")
            await refreshController()
        } catch {
            appendLog("error", "Proxy selection failed: \(error.localizedDescription)")
        }
    }

    func testProxyDelay(group: String, proxy: String) async {
        do {
            let client = MihomoControllerClient(host: settings.controllerHost, port: settings.controllerPort)
            let delay = try await client.proxyDelay(proxy: proxy)
            updateDelay(group: group, proxy: proxy, delay: delay)
            appendLog("info", "Delay test \(proxy): \(delay) ms")
        } catch {
            appendLog("error", "Delay test failed for \(proxy): \(error.localizedDescription)")
        }
    }

    func closeAllConnections() async {
        do {
            let client = MihomoControllerClient(host: settings.controllerHost, port: settings.controllerPort)
            try await client.closeConnections()
            connections = []
            appendLog("info", "Closed all controller connections")
        } catch {
            appendLog("error", "Close connections failed: \(error.localizedDescription)")
        }
    }

    func toggleSystemProxy() async {
        do {
            if systemProxyEnabled {
                try systemProxy.disable()
                systemProxyEnabled = false
                appendLog("info", "System proxy disabled")
            } else {
                try systemProxy.enable(host: "127.0.0.1", port: settings.mixedPort, socksPort: settings.socksPort)
                systemProxyEnabled = true
                appendLog("info", "System proxy enabled")
            }
        } catch {
            appendLog("error", "System proxy change failed: \(error.localizedDescription)")
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
            appendLog("info", "Imported remote profile \(item.name)")
        } catch {
            appendLog("error", "Remote import failed: \(error.localizedDescription)")
        }
    }

    func importLocalProfile(url: URL) async {
        do {
            let item = try profileStore.importLocalProfile(fileURL: url)
            profiles.append(item)
            settings.activeProfileID = item.id
            try profileStore.saveProfiles(profiles)
            try profileStore.saveSettings(settings)
            appendLog("info", "Imported local profile \(item.name)")
        } catch {
            appendLog("error", "Local import failed: \(error.localizedDescription)")
        }
    }

    func refreshProfile(_ profile: ProfileItem) async {
        do {
            let updated = try await profileStore.refreshRemoteProfile(profile)
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = updated
                try profileStore.saveProfiles(profiles)
            }
            appendLog("info", "Refreshed profile \(profile.name)")
        } catch {
            appendLog("error", "Profile refresh failed: \(error.localizedDescription)")
        }
    }

    func setActiveProfile(_ profile: ProfileItem) async {
        settings.activeProfileID = profile.id
        do {
            try profileStore.saveSettings(settings)
            appendLog("info", "Activated profile \(profile.name)")
            if isCoreRunning {
                await startCore()
            }
        } catch {
            appendLog("error", "Profile switch failed: \(error.localizedDescription)")
        }
    }

    func saveSettings(_ settings: AppSettings) async {
        do {
            self.settings = settings
            try profileStore.saveSettings(settings)
            appendLog("info", "Settings saved")
        } catch {
            appendLog("error", "Settings save failed: \(error.localizedDescription)")
        }
    }

    func runDiagnostics() async {
        var results: [DiagnosticResult] = []

        if FileManager.default.isExecutableFile(atPath: settings.mihomoPath) {
            results.append(.init(title: "mihomo binary", detail: settings.mihomoPath, state: .ok))
        } else {
            results.append(.init(title: "mihomo binary", detail: "Set an executable path in Settings.", state: .failed))
        }

        if let activeProfile {
            let file = profileStore.profileFile(activeProfile)
            let exists = FileManager.default.fileExists(atPath: file.path)
            results.append(.init(title: "Active profile", detail: exists ? activeProfile.name : "Profile file missing", state: exists ? .ok : .failed))
            do {
                let runtime = try profileStore.generateRuntimeConfig(profile: activeProfile, settings: settings)
                results.append(.init(title: "Runtime config", detail: runtime.path, state: .ok))
            } catch {
                results.append(.init(title: "Runtime config", detail: error.localizedDescription, state: .failed))
            }
        } else {
            results.append(.init(title: "Active profile", detail: "No active profile selected.", state: .failed))
        }

        let services = systemProxy.networkServices()
        results.append(.init(
            title: "Network services",
            detail: services.isEmpty ? "No network services found." : services.joined(separator: ", "),
            state: services.isEmpty ? .warning : .ok
        ))

        do {
            let version = try await MihomoControllerClient(host: settings.controllerHost, port: settings.controllerPort).version()
            results.append(.init(title: "Controller", detail: "Connected, version \(version)", state: .ok))
        } catch {
            results.append(.init(title: "Controller", detail: error.localizedDescription, state: .warning))
        }

        diagnostics = results
        selectedSection = .diagnostics
    }

    func appendLog(_ level: String, _ message: String) {
        guard !message.isEmpty else { return }
        for line in message.split(separator: "\n", omittingEmptySubsequences: true) {
            logs.append(LogEntry(level: level, message: String(line)))
        }
        if logs.count > 600 {
            logs.removeFirst(logs.count - 600)
        }
    }

    private func notify() {
        observers.values.forEach { $0() }
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
            return
        }

        let interval = max(now.timeIntervalSince(lastAt), 0.1)
        uploadRate = max(0, Int64(Double(uploadTotal - lastUpload) / interval))
        downloadRate = max(0, Int64(Double(downloadTotal - lastDownload) / interval))
        lastTrafficSampleAt = now
        lastUploadTotal = uploadTotal
        lastDownloadTotal = downloadTotal
    }

    private func updateDelay(group: String, proxy: String, delay: Int) {
        guard let groupIndex = proxyGroups.firstIndex(where: { $0.name == group }),
              let proxyIndex = proxyGroups[groupIndex].all.firstIndex(where: { $0.name == proxy })
        else { return }
        proxyGroups[groupIndex].all[proxyIndex].delay = delay
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
