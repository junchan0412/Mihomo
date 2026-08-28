import CFNetwork
import Foundation
import MihomoShared

extension AppStore {
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
            recordProxySelection(groupName: group, proxyName: proxy)
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
        let proxyURLs = normalizedDelayTestURLs
        let directURLs = normalizedDirectDelayTestURLs
        let timeout = normalizedDelayTestTimeout
        let proxyType = proxyNodeType(group: group, proxy: proxy)
        var failures: [String] = []

        if Self.isRejectProxy(type: proxyType, name: proxy) {
            delayTestStatus = "\(proxy) 不支持延迟测试：REJECT 为主动拒绝出站"
            delayTestFailureSummary = ""
            appendLog("info", delayTestStatus)
            return
        }

        do {
            if Self.isDirectProxy(type: proxyType, name: proxy) {
                let delay = try await Self.measureDirectDelay(urls: directURLs, timeout: timeout)
                updateDelay(proxy: proxy, delay: delay)
                recordDelayResult(proxyName: proxy, delay: delay)
                delayTestStatus = "\(proxy)：\(delay) ms（直连）"
                delayTestFailureSummary = ""
                appendLog("info", "\(proxy) 延迟：\(delay) ms（直连测速）")
                return
            }

            let client = controllerClient()
            for url in proxyURLs {
                do {
                    let delay = try await client.proxyDelay(proxy: proxy, url: url, timeout: timeout)
                    updateDelay(proxy: proxy, delay: delay)
                    recordDelayResult(proxyName: proxy, delay: delay)
                    delayTestStatus = "\(proxy)：\(delay) ms"
                    delayTestFailureSummary = ""
                    appendLog("info", "\(proxy) 延迟：\(delay) ms（\(url)）")
                    return
                } catch {
                    failures.append(Self.describeProbeFailure(error))
                }
            }
            let message = failures.map(friendlyDelayError).joined(separator: "，")
            throw NSError(domain: "DelayTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        } catch {
            delayTestStatus = "\(proxy) 延迟测试失败：\(friendlyDelayError(error.localizedDescription))"
            delayTestFailureSummary = friendlyDelayError(error.localizedDescription)
            recordDelayResult(proxyName: proxy, delay: nil, failureReason: delayTestFailureSummary)
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

    private func updateDelay(group: String, proxy: String, delay: Int) {
        guard let groupIndex = proxyGroups.firstIndex(where: { $0.name == group }),
              let proxyIndex = proxyGroups[groupIndex].all.firstIndex(where: { $0.name == proxy })
        else { return }
        proxyGroups[groupIndex].all[proxyIndex].delay = delay
    }

    private func updateDelay(proxy: String, delay: Int) {
        applyDelays([proxy: delay])
    }

    /// Applies a whole batch in one pass and publishes once. Updating `proxyGroups` per result
    /// re-scanned every group for every node and emitted an objectWillChange per assignment, so a
    /// 500-node sweep re-rendered the policy table 500+ times.
    func applyDelays(_ delays: [String: Int]) {
        guard delays.isEmpty == false else { return }
        var updated = proxyGroups
        var didChange = false
        for groupIndex in updated.indices {
            for proxyIndex in updated[groupIndex].all.indices {
                guard let delay = delays[updated[groupIndex].all[proxyIndex].name],
                      updated[groupIndex].all[proxyIndex].delay != delay
                else { continue }
                updated[groupIndex].all[proxyIndex].delay = delay
                didChange = true
            }
        }
        guard didChange else { return }
        proxyGroups = updated
    }

    private func testPolicyRowsDelay(_ rows: [PolicyTableRow], label: String) async {
        guard rows.isEmpty == false else {
            delayTestStatus = "没有可测速节点"
            return
        }

        let targets = uniqueDelayTargets(from: rows)
        let maxConcurrent = max(1, settings.delayTestConcurrency)
        let request = DelayProbeRequest(
            host: settings.localControlHost,
            port: settings.controllerPort,
            secret: settings.controllerSecret,
            urls: normalizedDelayTestURLs,
            directURLs: normalizedDirectDelayTestURLs,
            timeout: normalizedDelayTestTimeout
        )
        var completed = 0
        var succeeded = 0
        var failed = 0
        var skipped = 0
        var wasCancelled = false
        var failureReasons: [String: Int] = [:]
        var pendingDelays: [String: Int] = [:]
        var lastDelayFlushAt = Date.distantPast
        delayTestFailureSummary = ""
        delayTestStatus = "\(label) 测速开始，节点 \(targets.count)，并发 \(maxConcurrent)"

        await withTaskGroup(of: ProxyDelayResult.self) { group in
            var next = 0
            while next < min(maxConcurrent, targets.count) {
                let target = targets[next]
                next += 1
                group.addTask { await Self.measureDelay(for: target, request: request) }
            }

            // `group.next()` yields in completion order. Awaiting the hand-rolled task array in
            // submission order meant one slow node stalled every free slot behind it.
            while let result = await group.next() {
                completed += 1
                if let delay = result.delay {
                    succeeded += 1
                    pendingDelays[result.proxy] = delay
                    recordDelayResult(proxyName: result.proxy, delay: delay)
                } else if let skippedMessage = result.skippedMessage {
                    skipped += 1
                    recordDelayResult(proxyName: result.proxy, delay: nil, skippedReason: skippedMessage)
                } else {
                    failed += 1
                    let reason = friendlyDelayError(result.errorMessage ?? "未知错误")
                    failureReasons[reason, default: 0] += 1
                    recordDelayResult(proxyName: result.proxy, delay: nil, failureReason: reason)
                }

                // Coalesce delay writes: one publish per ~200 ms instead of one per node.
                let now = Date()
                if pendingDelays.isEmpty == false, now.timeIntervalSince(lastDelayFlushAt) >= 0.2 {
                    lastDelayFlushAt = now
                    applyDelays(pendingDelays)
                    pendingDelays.removeAll()
                }
                delayTestFailureSummary = delayFailureSummary(failureReasons)
                delayTestStatus = "\(label)：\(completed)/\(targets.count)，成功 \(succeeded)，失败 \(failed)，跳过 \(skipped)"

                if Task.isCancelled {
                    wasCancelled = true
                    group.cancelAll()
                } else if next < targets.count {
                    let target = targets[next]
                    next += 1
                    group.addTask { await Self.measureDelay(for: target, request: request) }
                }
            }
        }

        applyDelays(pendingDelays)

        if failed > 0 {
            appendLog("warning", "\(label) 测速失败原因：\(delayFailureSummary(failureReasons))")
        }
        if wasCancelled || completed < targets.count {
            delayTestStatus = "\(label) 测速已取消：完成 \(completed)/\(targets.count)"
            appendLog("warning", delayTestStatus)
            return
        }
        appendLog("info", "\(label) 测速完成：成功 \(succeeded)，失败 \(failed)，跳过 \(skipped)")
    }

    private var normalizedDelayTestURLs: [String] {
        DelayTestURLSelection.proxyURLs(settings: settings)
    }

    private var normalizedDirectDelayTestURLs: [String] {
        DelayTestURLSelection.directURLs(settings: settings)
    }

    private var normalizedDelayTestTimeout: Int {
        min(max(settings.delayTestTimeoutMS, 3000), 30000)
    }

    private func uniqueDelayTargets(from rows: [PolicyTableRow]) -> [ProxyDelayTarget] {
        var seen: Set<String> = []
        var targets: [ProxyDelayTarget] = []
        for row in rows where seen.contains(row.node.name) == false {
            seen.insert(row.node.name)
            targets.append(ProxyDelayTarget(proxy: row.node.name, type: row.node.type))
        }
        return targets
    }

    private func proxyNodeType(group: String, proxy: String) -> String {
        proxyGroups
            .first { $0.name == group }?
            .all
            .first { $0.name == proxy }?
            .type ?? proxy
    }

    private func friendlyDelayError(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveContains("timeout") {
            return "超时"
        }
        if trimmed == "An error occurred in the delay test" {
            return "测速 URL 不可达"
        }
        if trimmed.localizedCaseInsensitiveContains("could not resolve host") || trimmed.localizedCaseInsensitiveContains("no such host") {
            return "DNS 解析失败"
        }
        if trimmed.localizedCaseInsensitiveContains("connection refused") {
            return "连接被拒绝"
        }
        if trimmed.localizedCaseInsensitiveContains("unauthorized") || trimmed.localizedCaseInsensitiveContains("401") {
            return "核心控制通道的访问密钥错误"
        }
        return trimmed.isEmpty ? "未知错误" : trimmed
    }

    private func delayFailureSummary(_ reasons: [String: Int]) -> String {
        guard reasons.isEmpty == false else { return "" }
        return reasons
            .sorted {
                if $0.value == $1.value {
                    return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
                }
                return $0.value > $1.value
            }
            .prefix(3)
            .map { "\($0.key) x\($0.value)" }
            .joined(separator: "，")
    }
}
