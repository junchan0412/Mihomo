import Foundation

extension AppStore {
    var controllerPollingIntervalNanoseconds: UInt64 {
        guard let controllerConnectionStreamLastEventAt,
              Date().timeIntervalSince(controllerConnectionStreamLastEventAt) < 8
        else {
            return 1_000_000_000
        }
        return 5_000_000_000
    }

    var controllerMetadataRefreshIntervalNanoseconds: UInt64 {
        guard let controllerEventStreamLastEventAt,
              Date().timeIntervalSince(controllerEventStreamLastEventAt) < 8
        else {
            return 2_000_000_000
        }
        return 12_000_000_000
    }

    var isControllerStreamHealthy: Bool {
        guard let controllerEventStreamLastEventAt else { return false }
        return Date().timeIntervalSince(controllerEventStreamLastEventAt) < 8
    }

    func updateTrafficRates(uploadTotal: Int64, downloadTotal: Int64) {
        let now = Date()
        guard let lastAt = lastTrafficSampleAt,
              let lastUpload = lastUploadTotal,
              let lastDownload = lastDownloadTotal
        else {
            lastTrafficSampleAt = now
            lastUploadTotal = uploadTotal
            lastDownloadTotal = downloadTotal
            activityStore.updateTraffic(uploadRate: 0, downloadRate: 0)
            return
        }

        let interval = max(now.timeIntervalSince(lastAt), 0.1)
        let nextUploadRate = max(0, Int64(Double(uploadTotal - lastUpload) / interval))
        let nextDownloadRate = max(0, Int64(Double(downloadTotal - lastDownload) / interval))
        activityStore.updateTraffic(uploadRate: nextUploadRate, downloadRate: nextDownloadRate)
        lastTrafficSampleAt = now
        lastUploadTotal = uploadTotal
        lastDownloadTotal = downloadTotal
    }

    func startControllerEventStreams() {
        guard controllerTrafficStreamTask == nil,
              controllerLogStreamTask == nil,
              controllerConnectionStreamTask == nil
        else {
            return
        }

        let client = controllerEventStreamClient()
        let logLevel = settings.logLevel
        controllerEventStreamLastEventAt = nil
        controllerConnectionStreamLastEventAt = nil
        controllerEventStreamStatus = "连接中"

        controllerTrafficStreamTask = Task { [weak self] in
            await self?.runControllerEventStream(
                label: "流量",
                makeStream: client.trafficEvents,
                hasReceivedEvent: { [weak self] in self?.controllerEventStreamLastEventAt != nil }
            )
        }
        controllerLogStreamTask = Task { [weak self] in
            await self?.runControllerEventStream(
                label: "日志",
                makeStream: { client.logEvents(level: logLevel) },
                hasReceivedEvent: { [weak self] in self?.controllerEventStreamLastEventAt != nil }
            )
        }
        controllerConnectionStreamTask = Task { [weak self] in
            await self?.runControllerEventStream(
                label: "连接",
                makeStream: client.connectionEvents,
                hasReceivedEvent: { [weak self] in self?.controllerConnectionStreamLastEventAt != nil }
            )
        }
    }

    func stopControllerEventStreams(status: String) {
        controllerTrafficStreamTask?.cancel()
        controllerLogStreamTask?.cancel()
        controllerConnectionStreamTask?.cancel()
        controllerTrafficStreamTask = nil
        controllerLogStreamTask = nil
        controllerConnectionStreamTask = nil
        controllerEventStreamLastEventAt = nil
        controllerConnectionStreamLastEventAt = nil
        controllerEventStreamStatus = status
    }

    private func controllerEventStreamClient() -> MihomoControllerEventStream {
        MihomoControllerEventStream(
            host: settings.localControlHost,
            port: settings.controllerPort,
            secret: settings.controllerSecret
        )
    }

    private func runControllerEventStream(
        label: String,
        makeStream: @escaping () -> AsyncThrowingStream<ControllerStreamEvent, Error>,
        hasReceivedEvent: @escaping () -> Bool
    ) async {
        var recoveryState = ControllerEventStreamRecoveryState()
        while !Task.isCancelled && isCoreRunning {
            var backoffSeconds: UInt64 = 2
            do {
                for try await event in makeStream() {
                    recoveryState.recordEvent()
                    handleControllerStreamEvent(event)
                }
            } catch {
                guard !Task.isCancelled else { return }
                let decision = recoveryState.recordFailure(hasReceivedEvent: hasReceivedEvent())
                controllerEventStreamStatus = decision.status
                backoffSeconds = decision.backoffSeconds
                if decision.shouldLogWarning {
                    appendLog("warning", "\(label) WebSocket 事件流不可用，保留轮询：\(error.localizedDescription)")
                }
            }

            guard !Task.isCancelled && isCoreRunning else { return }
            try? await Task.sleep(nanoseconds: backoffSeconds * 1_000_000_000)
        }
    }

    private func handleControllerStreamEvent(_ event: ControllerStreamEvent) {
        controllerEventStreamLastEventAt = Date()
        if controllerEventStreamStatus != "实时" {
            controllerEventStreamStatus = "实时"
        }

        switch event {
        case .traffic(let uploadRate, let downloadRate):
            activityStore.updateTraffic(uploadRate: uploadRate, downloadRate: downloadRate)
        case .log(let level, let message):
            appendLog(level, message)
        case .connections(let items, let uploadTotal, let downloadTotal):
            controllerConnectionStreamLastEventAt = Date()
            let structureChanged = activityStore.connectionStructureChanged(from: connections, to: items)
            activityStore.replaceConnections(items)
            if structureChanged {
                updateRuleProviderHitStatistics()
            }
            updateTrafficRates(uploadTotal: uploadTotal, downloadTotal: downloadTotal)
        }
    }
}
