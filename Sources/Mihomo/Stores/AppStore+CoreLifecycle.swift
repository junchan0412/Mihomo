import Foundation

extension AppStore {
    func toggleCore() async {
        isCoreRunning ? await stopCore() : await startCore()
    }

    func startCore() async {
        guard let activeProfile else {
            appendLog("error", "没有可用配置")
            return
        }

        do {
            try await ensureHelperReadyForCoreStart()

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
            try syncGeoDataToRuntimeDirectory()
            let result = try await runWithGeoDataRetry {
                try await helperClient.prepareAndStartCore(
                    mihomoPath: mihomoPath,
                    configPath: AppPaths.runtimeConfigFile,
                    workDirectory: AppPaths.runtimeDirectory,
                    logPath: AppPaths.coreLogFile,
                    autoSetDNS: settings.autoSetSystemDNS,
                    dnsServers: settings.systemDNSServers,
                    captureTun: settings.tunEnabled
                )
            }
            if let validation = result.payload["validation"], validation.isEmpty == false {
                lastRuntimeValidation = validation
            } else {
                lastRuntimeValidation = "mihomo 配置校验通过"
            }
            if settings.autoSetSystemDNS {
                appendLog("info", "Helper 已临时设置系统 DNS：\(settings.systemDNSServers.joined(separator: "、"))")
                recordNetworkOperation(.systemDNS, result: result)
            }
            if settings.tunEnabled {
                lastTunRecoverySnapshot = tunRecovery.loadSnapshot()
                if let tunDetail = result.payload["tunDetail"], tunDetail.isEmpty == false {
                    tunRecoveryStatus = tunDetail
                } else {
                    tunRecoveryStatus = "Helper 已捕获 TUN 回滚快照"
                }
                appendLog("info", tunRecoveryStatus)
                recordNetworkOperation(.tun, result: result)
            }

            isCoreRunning = true
            coreStatus = "启动中"
            startControllerEventStreams()
            appendLog("info", "\(result.message)：\(AppPaths.runtimeConfigFile.path)")
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshController()
        } catch {
            coreStatus = "启动失败"
            try? profileStore.restoreRuntimeBackup()
            appendLog("error", "启动失败：\(error.localizedDescription)")
        }
        refreshNetworkTakeoverStates(force: true)
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
            stopControllerEventStreams(status: "轮询")
            lastSystemProxySnapshot = systemProxy.loadSnapshot()
            lastTunRecoverySnapshot = tunRecovery.loadSnapshot()
            if settings.tunEnabled && settings.restoreTunOnStop {
                tunRecoveryStatus = result.message
                recordNetworkOperation(.tun, result: result)
            } else if settings.autoSetSystemDNS {
                recordNetworkOperation(.systemDNS, result: result)
            }
            appendLog("info", result.message)
        } catch {
            isCoreRunning = false
            coreStatus = "停止失败"
            stopControllerEventStreams(status: "轮询")
            appendLog("error", "Helper 停止核心失败：\(error.localizedDescription)")
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        isExpectedCoreExit = false
        refreshNetworkTakeoverStates(force: true)
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
            publishIfChanged(\.coreVersion, try await version)
            publishIfChanged(\.currentMode, try await mode)
            let loadedGroups = try await groups
            await preloadPolicyGroupIcons(for: loadedGroups)
            publishIfChanged(\.proxyGroups, loadedGroups)
            let (items, up, down) = try await connectionResult
            let connectionsChanged = connections != items
            publishIfChanged(\.connections, items)
            if connectionsChanged {
                updateRuleProviderHitStatistics()
            }
            updateTrafficRates(uploadTotal: up, downloadTotal: down)
            if isCoreRunning {
                crashRestartCount = 0
                publishIfChanged(\.coreStatus, "运行中")
            }
            refreshNetworkTakeoverStates()
        } catch {
            if isCoreRunning {
                publishIfChanged(\.coreStatus, "控制器不可用")
            }
            refreshNetworkTakeoverStates()
        }
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
            try syncGeoDataToRuntimeDirectory()
            try profileStore.promoteRuntimeConfig(candidate: candidate)
            let result = try await runWithGeoDataRetry {
                try await helperClient.installCoreLaunchDaemon(
                    corePath: effectiveMihomoPath,
                    configPath: AppPaths.runtimeConfigFile,
                    workDirectory: AppPaths.runtimeDirectory,
                    logPath: AppPaths.coreLogFile
                )
            }
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

    func refreshManagedCoreStatus() {
        let managedAvailable = FileManager.default.isExecutableFile(atPath: AppPaths.managedCoreFile.path)
        let bundledPath = ManagedCoreManager.bundledCorePath
        let bundledAvailable = bundledPath.map { FileManager.default.isExecutableFile(atPath: $0) } ?? false
        let managedText = managedAvailable ? "托管已安装：\(AppPaths.managedCoreFile.path)" : "托管未安装"
        let bundledText = bundledAvailable ? "内置可用：\(bundledPath ?? "")" : "内置不可用"
        managedCoreStatus = "\(managedText)；\(bundledText)"
    }

    func shutdown() async {
        shutdownRequested = true
        profileRefreshTask?.cancel()
        profileRefreshTask = nil
        pollingTask?.cancel()
        pollingTask = nil
        stopControllerEventStreams(status: "轮询")
        _ = try? await helperClient.stopCore(
            restoreDNS: settings.autoSetSystemDNS || (settings.restoreSystemProxyOnQuit && systemProxyEnabled),
            restoreTun: settings.tunEnabled && settings.restoreTunOnStop
        )
        await logPersistenceWriter.flush()
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshController()
                let interval = self?.controllerPollingIntervalNanoseconds ?? 3_000_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func ensureHelperReadyForCoreStart() async throws {
        do {
            let result = try await helperClient.version()
            helperStatus = "\(result.message)，\(helperService.statusDescription)"
            return
        } catch {
            helperStatus = "Helper 通信失败，正在重建注册：\(error.localizedDescription)"
            appendLog("warning", helperStatus)
        }

        do {
            do {
                try helperService.unregister()
                appendLog("info", "启动前已移除旧 Helper 注册")
            } catch {
                appendLog("warning", "启动前移除旧 Helper 注册跳过：\(error.localizedDescription)")
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
            try helperService.register()
            helperStatus = helperService.statusDescription
            if helperService.requiresApproval {
                helperService.openLoginItemsSettings()
                throw helperStartupError("Helper 已重新注册，但仍需要在系统设置 > 通用 > 登录项与扩展中允许 Mihomo。")
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            let result = try await helperClient.version()
            helperStatus = "\(result.message)，\(helperService.statusDescription)"
            appendLog("info", "Helper 已恢复通信：\(helperStatus)")
        } catch {
            helperService.openLoginItemsSettings()
            throw helperStartupError("Helper 无法通信，已尝试重建注册：\(error.localizedDescription)")
        }
    }

    private func runWithGeoDataRetry<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            guard isGeoDataFailure(error) else { throw error }
            appendLog("warning", "核心启动遇到 Geo 数据错误，尝试更新 Geo 数据后重试：\(error.localizedDescription)")
            _ = try await updateGeoDataInternal()
            return try await operation()
        }
    }

    private func isGeoDataFailure(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("geosite.dat")
            || message.contains("geoip.dat")
            || message.contains("can't initial geosite")
            || message.contains("can't download geosite")
            || message.contains("geodata")
    }

    private func handleCoreExit(_ status: Int32) {
        if isExpectedCoreExit || shutdownRequested {
            appendLog("info", "核心已按计划退出")
            return
        }

        isCoreRunning = false
        coreStatus = "异常退出 \(status)"
        stopControllerEventStreams(status: "降级")
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

    private func helperStartupError(_ message: String) -> NSError {
        NSError(domain: "MihomoHelperStartup", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
