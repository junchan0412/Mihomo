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
        do {
            async let versionTask: String? = includeMetadata ? client.version() : nil
            async let modeTask: String? = includeMetadata ? client.configMode() : nil
            async let groupsTask: [ProxyGroup]? = includeMetadata ? client.proxyGroups() : nil
            async let connectionTask: ([ConnectionItem], Int64, Int64)? = includeConnections ? client.connections() : nil

            if includeMetadata {
                if let version = try await versionTask {
                    publishIfChanged(\.coreVersion, version)
                }
                if let mode = try await modeTask {
                    publishIfChanged(\.currentMode, mode)
                }
                if let loadedGroups = try await groupsTask {
                    await preloadPolicyGroupIcons(for: loadedGroups)
                    publishIfChanged(\.proxyGroups, loadedGroups)
                }
            }

            if includeConnections, let (items, up, down) = try await connectionTask {
                let structureChanged = activityStore.connectionStructureChanged(from: connections, to: items)
                activityStore.replaceConnections(items)
                if structureChanged {
                    updateRuleProviderHitStatistics()
                }
                updateTrafficRates(uploadTotal: up, downloadTotal: down)
            }

            if isCoreRunning {
                crashRestartCount = 0
                publishIfChanged(\.coreStatus, "运行中")
            }
            if includeTakeover {
                refreshNetworkTakeoverStates()
                await reconcileSystemProxyGuard()
            }
        } catch {
            if isCoreRunning {
                publishIfChanged(\.coreStatus, "控制器不可用")
            }
            if includeTakeover {
                refreshNetworkTakeoverStates()
                await reconcileSystemProxyGuard()
            }
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
                let streamHealthy = self.isControllerStreamHealthy
                let includeConnections = streamHealthy == false
                // Metadata (mode/groups/version) is lower priority than live connections.
                let includeMetadata = cycle % (streamHealthy ? 3 : 1) == 0
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
