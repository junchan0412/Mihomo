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
        let urls = normalizedDelayTestURLs
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
                let delay = try await Self.measureDirectDelay(urls: urls, timeout: timeout)
                updateDelay(proxy: proxy, delay: delay)
                delayTestStatus = "\(proxy)：\(delay) ms（直连）"
                delayTestFailureSummary = ""
                appendLog("info", "\(proxy) 延迟：\(delay) ms（直连测速）")
                return
            }

            let client = controllerClient()
            for url in urls {
                do {
                    let delay = try await client.proxyDelay(proxy: proxy, url: url, timeout: timeout)
                    updateDelay(proxy: proxy, delay: delay)
                    delayTestStatus = "\(proxy)：\(delay) ms"
                    delayTestFailureSummary = ""
                    appendLog("info", "\(proxy) 延迟：\(delay) ms（\(url)）")
                    return
                } catch {
                    failures.append(error.localizedDescription)
                }
            }
            let message = failures.map(friendlyDelayError).joined(separator: "，")
            throw NSError(domain: "DelayTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        } catch {
            delayTestStatus = "\(proxy) 延迟测试失败：\(friendlyDelayError(error.localizedDescription))"
            delayTestFailureSummary = friendlyDelayError(error.localizedDescription)
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
        proxyGroups = proxyGroups
    }

    private func updateDelay(proxy: String, delay: Int) {
        for groupIndex in proxyGroups.indices {
            for proxyIndex in proxyGroups[groupIndex].all.indices where proxyGroups[groupIndex].all[proxyIndex].name == proxy {
                proxyGroups[groupIndex].all[proxyIndex].delay = delay
            }
        }
        proxyGroups = proxyGroups
    }

    private func testPolicyRowsDelay(_ rows: [PolicyTableRow], label: String) async {
        guard rows.isEmpty == false else {
            delayTestStatus = "没有可测速节点"
            return
        }

        let targets = uniqueDelayTargets(from: rows)
        let maxConcurrent = max(1, settings.delayTestConcurrency)
        var pendingTargets = targets
        var runningTasks: [Task<ProxyDelayResult, Never>] = []
        var completed = 0
        var succeeded = 0
        var failed = 0
        var skipped = 0
        var failureReasons: [String: Int] = [:]
        delayTestFailureSummary = ""
        delayTestStatus = "\(label) 测速开始，节点 \(targets.count)，并发 \(maxConcurrent)"

        while pendingTargets.isEmpty == false || runningTasks.isEmpty == false {
            while runningTasks.count < maxConcurrent, pendingTargets.isEmpty == false {
                let target = pendingTargets.removeFirst()
                let host = settings.controllerHost
                let port = settings.controllerPort
                let secret = settings.controllerSecret
                let urls = normalizedDelayTestURLs
                let timeout = normalizedDelayTestTimeout
                runningTasks.append(Task {
                    if Self.isRejectProxy(type: target.type, name: target.proxy) {
                        return ProxyDelayResult(proxy: target.proxy, delay: nil, errorMessage: nil, skippedMessage: "REJECT 不可测速")
                    }
                    if Self.isDirectProxy(type: target.type, name: target.proxy) {
                        do {
                            let delay = try await Self.measureDirectDelay(urls: urls, timeout: timeout)
                            return ProxyDelayResult(proxy: target.proxy, delay: delay, errorMessage: nil, skippedMessage: nil)
                        } catch {
                            return ProxyDelayResult(proxy: target.proxy, delay: nil, errorMessage: error.localizedDescription, skippedMessage: nil)
                        }
                    }
                    let client = MihomoControllerClient(host: host, port: port, secret: secret)
                    var failures: [String] = []
                    for url in urls {
                        do {
                            let delay = try await client.proxyDelay(proxy: target.proxy, url: url, timeout: timeout)
                            return ProxyDelayResult(proxy: target.proxy, delay: delay, errorMessage: nil, skippedMessage: nil)
                        } catch {
                            failures.append(error.localizedDescription)
                        }
                    }
                    return ProxyDelayResult(proxy: target.proxy, delay: nil, errorMessage: failures.joined(separator: "，"), skippedMessage: nil)
                })
            }

            guard runningTasks.isEmpty == false else { break }
            let result = await runningTasks.removeFirst().value
            completed += 1
            if let delay = result.delay {
                succeeded += 1
                updateDelay(proxy: result.proxy, delay: delay)
            } else if result.skippedMessage != nil {
                skipped += 1
            } else {
                failed += 1
                let reason = friendlyDelayError(result.errorMessage ?? "未知错误")
                failureReasons[reason, default: 0] += 1
            }
            let summary = delayFailureSummary(failureReasons)
            delayTestFailureSummary = summary
            delayTestStatus = "\(label)：\(completed)/\(targets.count)，成功 \(succeeded)，失败 \(failed)，跳过 \(skipped)"
        }

        if failed > 0 {
            appendLog("warning", "\(label) 测速失败原因：\(delayFailureSummary(failureReasons))")
        }
        appendLog("info", "\(label) 测速完成：成功 \(succeeded)，失败 \(failed)，跳过 \(skipped)")
    }

    private var normalizedDelayTestURL: String {
        let value = settings.delayTestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? AppSettings.default.delayTestURL : value
    }

    private var normalizedDelayTestURLs: [String] {
        var seen: Set<String> = []
        var urls: [String] = []
        for url in [normalizedDelayTestURL, AppSettings.default.delayTestURL, "https://www.gstatic.com/generate_204"] {
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false, seen.insert(trimmed).inserted else { continue }
            urls.append(trimmed)
        }
        return urls
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

    nonisolated private static func isDirectProxy(type: String, name: String) -> Bool {
        type.localizedCaseInsensitiveCompare("direct") == .orderedSame
            || name.localizedCaseInsensitiveCompare("direct") == .orderedSame
    }

    nonisolated private static func isRejectProxy(type: String, name: String) -> Bool {
        type.localizedCaseInsensitiveCompare("reject") == .orderedSame
            || name.localizedCaseInsensitiveCompare("reject") == .orderedSame
    }

    nonisolated private static func measureDirectDelay(urls: [String], timeout: Int) async throws -> Int {
        var failures: [String] = []
        for urlString in urls {
            guard let url = URL(string: urlString) else {
                failures.append("测速 URL 无效")
                continue
            }

            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                request.timeoutInterval = TimeInterval(timeout) / 1000

                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = TimeInterval(timeout) / 1000
                configuration.timeoutIntervalForResource = TimeInterval(timeout) / 1000
                configuration.waitsForConnectivity = false
                configuration.connectionProxyDictionary = [
                    kCFNetworkProxiesHTTPEnable as String: false,
                    kCFNetworkProxiesHTTPSEnable as String: false,
                    kCFNetworkProxiesSOCKSEnable as String: false
                ]

                let session = URLSession(configuration: configuration)
                defer { session.finishTasksAndInvalidate() }
                let startedAt = Date()
                _ = try await session.data(for: request)
                return max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
            } catch {
                failures.append(error.localizedDescription)
            }
        }

        throw NSError(domain: "DirectDelay", code: 1, userInfo: [
            NSLocalizedDescriptionKey: failures.isEmpty ? "DIRECT 直连测速失败" : failures.joined(separator: "，")
        ])
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
            return "Controller 密钥错误"
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

private struct ProxyDelayResult {
    var proxy: String
    var delay: Int?
    var errorMessage: String?
    var skippedMessage: String?
}

private struct ProxyDelayTarget {
    var proxy: String
    var type: String
}
