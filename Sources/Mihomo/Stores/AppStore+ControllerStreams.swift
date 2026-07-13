import Foundation

extension AppStore {
    var controllerPollingIntervalNanoseconds: UInt64 {
        guard let controllerEventStreamLastEventAt,
              Date().timeIntervalSince(controllerEventStreamLastEventAt) < 8
        else {
            return 3_000_000_000
        }
        return 8_000_000_000
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
            publishIfChanged(\.uploadRate, 0)
            publishIfChanged(\.downloadRate, 0)
            if connections.isEmpty == false {
                appendTrafficSampleIfNeeded(uploadRate: 0, downloadRate: 0)
            }
            return
        }

        let interval = max(now.timeIntervalSince(lastAt), 0.1)
        let nextUploadRate = max(0, Int64(Double(uploadTotal - lastUpload) / interval))
        let nextDownloadRate = max(0, Int64(Double(downloadTotal - lastDownload) / interval))
        publishIfChanged(\.uploadRate, nextUploadRate)
        publishIfChanged(\.downloadRate, nextDownloadRate)
        lastTrafficSampleAt = now
        lastUploadTotal = uploadTotal
        lastDownloadTotal = downloadTotal
        appendTrafficSampleIfNeeded(uploadRate: nextUploadRate, downloadRate: nextDownloadRate)
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
        controllerEventStreamStatus = "连接中"

        controllerTrafficStreamTask = Task { [weak self] in
            await self?.runControllerEventStream(label: "流量", makeStream: client.trafficEvents)
        }
        controllerLogStreamTask = Task { [weak self] in
            await self?.runControllerEventStream(label: "日志", makeStream: { client.logEvents(level: logLevel) })
        }
        controllerConnectionStreamTask = Task { [weak self] in
            await self?.runControllerEventStream(label: "连接", makeStream: client.connectionEvents)
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
        controllerEventStreamStatus = status
    }

    private func controllerEventStreamClient() -> MihomoControllerEventStream {
        MihomoControllerEventStream(
            host: settings.localControlHost,
            port: settings.controllerPort,
            secret: settings.controllerSecret
        )
    }

    private func appendTrafficSampleIfNeeded(uploadRate: Int64, downloadRate: Int64) {
        if uploadRate == 0,
           downloadRate == 0,
           connections.isEmpty,
           trafficSamples.last?.uploadRate == 0,
           trafficSamples.last?.downloadRate == 0 {
            return
        }

        var updatedSamples = trafficSamples
        updatedSamples.append(TrafficSample(uploadRate: uploadRate, downloadRate: downloadRate))
        if updatedSamples.count > 120 {
            updatedSamples.removeFirst(updatedSamples.count - 120)
        }
        publishIfChanged(\.trafficSamples, updatedSamples)
    }

    private func runControllerEventStream(
        label: String,
        makeStream: @escaping () -> AsyncThrowingStream<ControllerStreamEvent, Error>
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
                let decision = recoveryState.recordFailure(hasReceivedEvent: controllerEventStreamLastEventAt != nil)
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
            publishIfChanged(\.uploadRate, uploadRate)
            publishIfChanged(\.downloadRate, downloadRate)
            appendTrafficSampleIfNeeded(uploadRate: uploadRate, downloadRate: downloadRate)
        case .log(let level, let message):
            appendLog(level, message)
        case .connections(let items, let uploadTotal, let downloadTotal):
            let connectionsChanged = connections != items
            publishIfChanged(\.connections, items)
            if connectionsChanged {
                updateRuleProviderHitStatistics()
            }
            updateTrafficRates(uploadTotal: uploadTotal, downloadTotal: downloadTotal)
        }
    }
}
