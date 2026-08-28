import Foundation

extension AppStore {
    func refreshController() async {
        await refreshController(includeMetadata: true, includeConnections: true, includeTakeover: true)
    }

    func refreshController(
        includeMetadata: Bool,
        includeConnections: Bool,
        includeTakeover: Bool
    ) async {
        let client = controllerClient()

        // Each request is awaited independently. Sharing one do/catch meant a single failing
        // `/version` discarded the connection snapshot fetched in the same cycle, freezing the
        // activity table until the next successful full pass.
        async let versionResult = includeMetadata ? Result { try await client.version() } : nil
        async let modeResult = includeMetadata ? Result { try await client.configMode() } : nil
        async let groupsResult = includeMetadata ? Result { try await client.proxyGroups() } : nil
        async let connectionResult = includeConnections ? Result { try await client.connections() } : nil

        var reachable = false
        var failed = false

        if let versionResult = await versionResult {
            switch versionResult {
            case .success(let version):
                reachable = true
                publishIfChanged(\.coreVersion, version)
            case .failure:
                failed = true
            }
        }
        if let modeResult = await modeResult {
            switch modeResult {
            case .success(let mode):
                reachable = true
                publishIfChanged(\.currentMode, mode)
            case .failure:
                failed = true
            }
        }
        if let groupsResult = await groupsResult {
            switch groupsResult {
            case .success(let loadedGroups):
                reachable = true
                await preloadPolicyGroupIcons(for: loadedGroups)
                publishIfChanged(\.proxyGroups, loadedGroups)
            case .failure:
                failed = true
            }
        }
        if let connectionResult = await connectionResult {
            switch connectionResult {
            case .success(let (items, up, down)):
                reachable = true
                let structureChanged = activityStore.connectionStructureChanged(from: connections, to: items)
                activityStore.replaceConnections(items)
                if structureChanged {
                    updateRuleProviderHitStatistics()
                }
                updateTrafficRates(uploadTotal: up, downloadTotal: down)
            case .failure:
                failed = true
            }
        }

        if isCoreRunning {
            if reachable {
                crashRestartCount = 0
                consecutiveControllerFailures = 0
                publishIfChanged(\.coreStatus, "运行中")
            } else if failed {
                publishIfChanged(\.coreStatus, "控制器不可用")
                noteControllerUnreachable()
            }
        }
        if includeTakeover {
            refreshNetworkTakeoverStates()
            await reconcileSystemProxyGuard()
        }
    }

    /// Loopback controller failures are the only signal we get that a helper-managed core died.
    /// One blip is not proof, so only a short run of consecutive failures counts as an exit.
    private func noteControllerUnreachable() {
        guard isExpectedCoreExit == false, shutdownRequested == false else { return }
        consecutiveControllerFailures &+= 1
        guard consecutiveControllerFailures >= Self.controllerFailureExitThreshold else { return }
        handleCoreExit(reason: "控制通道连续 \(consecutiveControllerFailures) 次不可达")
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

    func closeConnections(_ ids: [String]) async {
        let uniqueIDs = Array(Set(ids))
        guard uniqueIDs.isEmpty == false else { return }

        let client = controllerClient()
        let results = await BoundedConcurrentWork.map(uniqueIDs, maxConcurrent: 4) { id in
            do {
                try await client.closeConnection(id: id)
                return (id, nil as String?)
            } catch {
                return (id, error.localizedDescription)
            }
        }

        let succeededIDs = results.compactMap { id, errorMessage in
            errorMessage == nil ? id : nil
        }
        let failures = results.compactMap { id, errorMessage in
            errorMessage.map { "\(id)：\($0)" }
        }
        connections.removeAll { succeededIDs.contains($0.id) }

        if failures.isEmpty {
            appendLog("info", "已关闭 \(succeededIDs.count) 个连接")
        } else {
            appendLog(
                "error",
                "批量关闭连接完成：成功 \(succeededIDs.count)，失败 \(failures.count)；\(failures.joined(separator: "；"))"
            )
        }
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            var cycle = 0
            while !Task.isCancelled {
                guard let self else { return }
                let connectionStreamHealthy = self.isControllerConnectionStreamHealthy
                let includeConnections = connectionStreamHealthy == false
                // Metadata (mode/groups/version) is lower priority than live connections.
                let includeMetadata = cycle % (self.isControllerStreamHealthy ? 3 : 1) == 0
                await self.refreshController(
                    includeMetadata: includeMetadata,
                    includeConnections: includeConnections,
                    includeTakeover: includeMetadata
                )
                cycle &+= 1
                let interval = includeConnections
                    ? self.controllerPollingIntervalNanoseconds
                    : self.controllerMetadataRefreshIntervalNanoseconds
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }
}
