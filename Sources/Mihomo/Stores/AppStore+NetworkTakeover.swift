import Foundation

extension AppStore {
    func toggleSystemProxy() async {
        do {
            if systemProxyEnabled {
                let result = try await helperClient.restoreSystemProxy()
                systemProxyEnabled = false
                lastSystemProxySnapshot = systemProxy.loadSnapshot()
                recordNetworkOperation(.systemProxy, result: result)
                appendLog("info", result.message)
            } else {
                if settings.tunEnabled {
                    appendLog("warning", "系统代理与 TUN 互斥：开启系统代理前将关闭 TUN。")
                    await setTunEnabled(false)
                }
                let result = try await helperClient.setSystemProxy(host: "127.0.0.1", mixedPort: settings.mixedPort, socksPort: settings.socksPort)
                systemProxyEnabled = true
                lastSystemProxySnapshot = systemProxy.loadSnapshot()
                recordNetworkOperation(.systemProxy, result: result)
                appendLog("info", result.message)
            }
        } catch {
            appendLog("error", "Helper 系统代理操作失败：\(error.localizedDescription)")
        }
        refreshNetworkTakeoverStates(force: true)
    }

    func setTunEnabled(_ enabled: Bool) async {
        guard settings.tunEnabled != enabled else { return }
        let shouldRestoreTunBeforeDisable = settings.tunEnabled && enabled == false && isCoreRunning && settings.restoreTunOnStop
        if enabled && systemProxyEnabled {
            do {
                appendLog("warning", "TUN 与系统代理互斥：开启 TUN 前将关闭系统代理。")
                let result = try await helperClient.restoreSystemProxy()
                systemProxyEnabled = false
                lastSystemProxySnapshot = systemProxy.loadSnapshot()
                recordNetworkOperation(.systemProxy, result: result)
                appendLog("info", result.message)
            } catch {
                appendLog("error", "关闭系统代理失败，已取消开启 TUN：\(error.localizedDescription)")
                refreshNetworkTakeoverStates(force: true)
                return
            }
        }
        if shouldRestoreTunBeforeDisable {
            do {
                let result = try await helperClient.restoreTunSnapshot()
                tunRecoveryStatus = result.message
                recordNetworkOperation(.tun, result: result)
                appendLog("info", "关闭 TUN 前已恢复路由快照：\(result.message)")
            } catch {
                appendLog("warning", "关闭 TUN 前恢复路由快照失败，将继续重启核心：\(error.localizedDescription)")
            }
        }
        var updated = settings
        updated.tunEnabled = enabled
        await saveSettings(updated)
        if isCoreRunning {
            appendLog("info", "TUN 已\(enabled ? "启用" : "关闭")，正在重启核心使配置生效")
            await restartCore()
        } else {
            appendLog("info", "TUN 已\(enabled ? "启用" : "关闭")，下次启动核心时生效")
        }
        refreshNetworkTakeoverStates(force: true)
    }

    func repairSystemProxy() async {
        do {
            let result = try await helperClient.restoreSystemProxy()
            systemProxyEnabled = false
            lastSystemProxySnapshot = systemProxy.loadSnapshot()
            recordNetworkOperation(.systemProxy, result: result)
            appendLog("info", result.message)
        } catch {
            appendLog("error", "Helper 系统代理修复失败：\(error.localizedDescription)")
        }
        refreshNetworkTakeoverStates(force: true)
    }

    func restoreSystemDNS() async {
        do {
            let result = try await helperClient.restoreSystemDNS()
            recordNetworkOperation(.systemDNS, result: result)
            appendLog("info", result.message)
        } catch {
            appendLog("error", "Helper 系统 DNS 恢复失败：\(error.localizedDescription)")
        }
        refreshNetworkTakeoverStates(force: true)
    }

    func restoreTunRecovery() async {
        do {
            let result = try await helperClient.restoreTunSnapshot()
            lastTunRecoverySnapshot = tunRecovery.loadSnapshot()
            tunRecoveryStatus = result.message
            systemProxyEnabled = false
            lastSystemProxySnapshot = systemProxy.loadSnapshot()
            recordNetworkOperation(.tun, result: result)
            appendLog("info", result.message)
        } catch {
            tunRecoveryStatus = "TUN 回滚失败：\(error.localizedDescription)"
            appendLog("error", tunRecoveryStatus)
        }
        refreshNetworkTakeoverStates(force: true)
    }

    func clearNetworkRecoverySnapshots() {
        do {
            try systemProxy.removeSnapshot(at: AppPaths.systemProxySnapshotFile)
            try systemProxy.removeSnapshot(at: AppPaths.systemDNSSnapshotFile)
            try tunRecovery.clearSnapshot()
            lastSystemProxySnapshot = nil
            lastSystemDNSSnapshot = nil
            lastTunRecoverySnapshot = nil
            tunRecoveryStatus = "已清理 TUN 回滚快照"
            lastNetworkOperations[.systemProxy] = "已清理代理快照"
            lastNetworkOperations[.systemDNS] = "已清理 DNS 快照"
            lastNetworkOperations[.tun] = "已清理 TUN 快照"
            appendLog("info", "已清理网络接管恢复快照")
        } catch {
            appendLog("error", "清理网络快照失败：\(error.localizedDescription)")
        }
        refreshNetworkTakeoverStates(force: true)
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

    func networkTakeoverState(for kind: NetworkTakeoverKind) -> NetworkTakeoverState {
        networkTakeoverStates.first { $0.kind == kind } ?? NetworkTakeoverState(
            kind: kind,
            desiredState: "尚未检查",
            actualState: "尚未检查",
            lastOperation: "无记录",
            recoveryAction: "运行诊断",
            health: .inactive
        )
    }

    var networkSecuritySnapshotItems: [NetworkSecuritySnapshotItem] {
        NetworkSecurityCenter.snapshotItems(
            proxySnapshot: lastSystemProxySnapshot,
            dnsSnapshot: lastSystemDNSSnapshot,
            tunSnapshot: lastTunRecoverySnapshot,
            paths: .init(
                systemProxy: AppPaths.systemProxySnapshotFile.path,
                systemDNS: AppPaths.systemDNSSnapshotFile.path,
                tunRecovery: AppPaths.tunRecoverySnapshotFile.path
            )
        )
    }

    var networkSecurityOverallHealth: NetworkTakeoverHealth {
        NetworkSecurityCenter.overallHealth(for: networkTakeoverStates)
    }

    func refreshNetworkTakeoverStates(force: Bool = false) {
        let now = Date()
        if force == false,
           networkTakeoverStates.isEmpty == false,
           now.timeIntervalSince(lastNetworkTakeoverRefreshAt) < 20 {
            return
        }
        lastNetworkTakeoverRefreshAt = now

        let current = try? systemProxy.captureSnapshot()
        publishIfChanged(\.lastSystemProxySnapshot, systemProxy.loadSnapshot())
        publishIfChanged(\.lastSystemDNSSnapshot, systemProxy.loadDNSSnapshot())
        publishIfChanged(\.lastTunRecoverySnapshot, tunRecovery.loadSnapshot())

        publishIfChanged(\.networkTakeoverStates, [
            systemProxyTakeoverState(current: current),
            systemDNSTakeoverState(current: current),
            tunTakeoverState()
        ])
    }

    func recordNetworkOperation(_ kind: NetworkTakeoverKind, result: HelperOperationResult) {
        let steps = result.payload["transactionSteps"]?.replacingOccurrences(of: "\n", with: " / ") ?? ""
        let suggestion = result.payload["rollbackSuggestion"].map { "；建议：\($0)" } ?? ""
        let detail = steps.isEmpty ? result.message : "\(result.message)（\(steps)）"
        lastNetworkOperations[kind] = detail + suggestion
    }

    private func systemProxyTakeoverState(current: SystemProxySnapshot?) -> NetworkTakeoverState {
        let services = current?.services ?? []
        let matched = services.filter { service in
            let webMatches = service.web.enabled && service.web.server == "127.0.0.1" && service.web.port == settings.mixedPort
            let secureMatches = service.secureWeb.enabled && service.secureWeb.server == "127.0.0.1" && service.secureWeb.port == settings.mixedPort
            let socksMatches = settings.socksPort > 0 && service.socks.enabled && service.socks.server == "127.0.0.1" && service.socks.port == settings.socksPort
            return webMatches || secureMatches || socksMatches
        }
        let desired = systemProxyEnabled ? "期望开启：127.0.0.1:\(settings.mixedPort)" : "期望关闭"
        let actual: String
        if services.isEmpty {
            actual = "未能读取网络服务"
        } else if matched.isEmpty {
            actual = "未检测到 Mihomo 系统代理"
        } else {
            actual = "\(matched.count)/\(services.count) 个服务指向 Mihomo"
        }
        let health: NetworkTakeoverHealth
        if systemProxyEnabled {
            health = matched.isEmpty ? .warning : .ok
        } else {
            health = matched.isEmpty ? .inactive : .warning
        }
        return NetworkTakeoverState(
            kind: .systemProxy,
            desiredState: desired,
            actualState: actual,
            lastOperation: lastNetworkOperations[.systemProxy] ?? "无 Helper 操作记录",
            recoveryAction: lastSystemProxySnapshot == nil ? "关闭残留代理" : "恢复代理快照",
            health: services.isEmpty ? .failed : health
        )
    }

    private func systemDNSTakeoverState(current: SystemProxySnapshot?) -> NetworkTakeoverState {
        let services = current?.services ?? []
        let desiredServers = settings.systemDNSServers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let desired: String
        if settings.autoSetSystemDNS {
            desired = isCoreRunning ? "期望随核心启用：\(desiredServers.joined(separator: ", "))" : "期望下次核心启动时启用"
        } else {
            desired = "期望关闭 App 管理 DNS"
        }
        let matched = services.filter { service in
            guard desiredServers.isEmpty == false else { return false }
            return Set(desiredServers).isSubset(of: Set(service.dnsServers))
        }
        let dnsSnapshot = systemProxy.loadDNSSnapshot()
        let actual: String
        if services.isEmpty {
            actual = "未能读取网络服务"
        } else if settings.autoSetSystemDNS && isCoreRunning {
            actual = matched.isEmpty ? "未检测到 App 临时 DNS" : "\(matched.count)/\(services.count) 个服务使用 App DNS"
        } else if dnsSnapshot != nil {
            actual = "存在待恢复 DNS 快照"
        } else {
            actual = "系统 DNS 由用户或系统管理"
        }
        let health: NetworkTakeoverHealth
        if settings.autoSetSystemDNS && isCoreRunning {
            health = matched.isEmpty ? .warning : .ok
        } else {
            health = dnsSnapshot == nil ? .inactive : .warning
        }
        return NetworkTakeoverState(
            kind: .systemDNS,
            desiredState: desired,
            actualState: actual,
            lastOperation: lastNetworkOperations[.systemDNS] ?? "无 Helper 操作记录",
            recoveryAction: dnsSnapshot == nil ? "无 DNS 快照" : "恢复 DNS 快照",
            health: services.isEmpty ? .failed : health
        )
    }

    private func tunTakeoverState() -> NetworkTakeoverState {
        let snapshot = lastTunRecoverySnapshot
        let routeCount = tunRecovery.currentAddedTunRouteCount()
        let desired: String
        if settings.tunEnabled {
            desired = isCoreRunning ? "期望运行中，并可回滚 DNS/路由" : "期望下次核心启动时启用"
        } else {
            desired = "期望关闭"
        }
        let actual: String
        if let snapshot {
            actual = "已有快照：IPv4 \(snapshot.ipv4Routes.count)，IPv6 \(snapshot.ipv6Routes.count)，新增 utun 路由 \(routeCount)"
        } else if settings.tunEnabled && isCoreRunning {
            actual = "核心运行中，但未发现 TUN 回滚快照"
        } else {
            actual = "未检测到 App TUN 快照"
        }
        let health: NetworkTakeoverHealth
        if settings.tunEnabled && isCoreRunning {
            health = snapshot == nil ? .warning : .ok
        } else {
            health = snapshot == nil ? .inactive : .warning
        }
        return NetworkTakeoverState(
            kind: .tun,
            desiredState: desired,
            actualState: actual,
            lastOperation: lastNetworkOperations[.tun] ?? "无 Helper 操作记录",
            recoveryAction: snapshot == nil ? "无 TUN 快照" : "恢复 TUN 路由与 DNS",
            health: health
        )
    }
}
