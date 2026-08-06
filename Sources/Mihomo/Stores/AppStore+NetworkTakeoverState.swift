import Foundation

extension AppStore {
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

        var current: SystemProxySnapshot?
        var readError: String?
        do {
            current = try systemProxy.captureSnapshot()
        } catch {
            readError = error.localizedDescription
        }
        publishIfChanged(\.lastSystemProxySnapshot, systemProxy.loadSnapshot())
        publishIfChanged(\.lastSystemDNSSnapshot, systemProxy.loadDNSSnapshot())
        publishIfChanged(\.lastTunRecoverySnapshot, tunRecovery.loadSnapshot())

        publishIfChanged(\.networkTakeoverStates, [
            systemProxyTakeoverState(current: current, readError: readError, checkedAt: now),
            systemDNSTakeoverState(current: current, readError: readError, checkedAt: now),
            tunTakeoverState(checkedAt: now)
        ])
    }

    func reconcileSystemProxyGuard() async {
        guard settings.systemProxyGuardEnabled,
              systemProxyEnabled,
              isCoreRunning,
              systemProxyGuardTask == nil,
              Date().timeIntervalSince(lastSystemProxyGuardAttemptAt) >= 15
        else { return }

        guard let current = try? systemProxy.captureSnapshot(),
              SystemProxyManager.matchReport(snapshot: current, mixedPort: settings.mixedPort, socksPort: settings.socksPort).isFullyMatched == false
        else { return }

        lastSystemProxyGuardAttemptAt = Date()
        systemProxyGuardTask = Task { [weak self] in
            guard let self else { return }
            defer { systemProxyGuardTask = nil }
            do {
                let result = try await helperClient.setSystemProxy(host: "127.0.0.1", mixedPort: settings.mixedPort, socksPort: settings.socksPort)
                recordNetworkOperation(.systemProxy, result: result)
                appendLog("warning", "检测到系统代理被外部修改，已按守护策略恢复 Mihomo 代理。")
                refreshNetworkTakeoverStates(force: true)
            } catch {
                appendLog("error", "系统代理守护恢复失败：\(error.localizedDescription)")
            }
        }
    }

    func recordNetworkOperation(_ kind: NetworkTakeoverKind, result: HelperOperationResult) {
        let steps = result.payload["transactionSteps"]?.replacingOccurrences(of: "\n", with: " / ") ?? ""
        let suggestion = result.payload["rollbackSuggestion"].map { "；建议：\($0)" } ?? ""
        let detail = steps.isEmpty ? result.message : "\(result.message)（\(steps)）"
        lastNetworkOperations[kind] = detail + suggestion
    }

    private func systemProxyTakeoverState(
        current: SystemProxySnapshot?,
        readError: String?,
        checkedAt: Date
    ) -> NetworkTakeoverState {
        let services = current?.services ?? []
        let report = current.map { SystemProxyManager.matchReport(snapshot: $0, mixedPort: settings.mixedPort, socksPort: settings.socksPort) }
        let desired = systemProxyEnabled ? "期望开启：127.0.0.1:\(settings.mixedPort)" : "期望关闭"
        let actual: String
        if let readError {
            actual = "无法检查网络服务：\(readError)"
        } else if services.isEmpty {
            actual = "读取成功，但系统未返回网络服务"
        } else if report?.matchedServices == 0 {
            actual = "未检测到 Mihomo 系统代理"
        } else {
            actual = "\(report?.matchedServices ?? 0)/\(services.count) 个服务指向 Mihomo"
        }
        let health: NetworkTakeoverHealth
        if readError != nil {
            health = .unknown
        } else if systemProxyEnabled {
            health = report?.isFullyMatched == true ? .ok : .warning
        } else {
            health = report?.matchedServices == 0 ? .inactive : .warning
        }
        return NetworkTakeoverState(
            kind: .systemProxy,
            desiredState: desired,
            actualState: actual,
            lastOperation: lastNetworkOperations[.systemProxy] ?? "无 Helper 操作记录",
            recoveryAction: lastSystemProxySnapshot == nil ? "关闭残留代理" : "恢复代理快照",
            health: services.isEmpty && readError == nil ? .unknown : health,
            lastCheckedAt: checkedAt
        )
    }

    private func systemDNSTakeoverState(
        current: SystemProxySnapshot?,
        readError: String?,
        checkedAt: Date
    ) -> NetworkTakeoverState {
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
        if let readError {
            actual = "无法检查网络服务：\(readError)"
        } else if services.isEmpty {
            actual = "读取成功，但系统未返回网络服务"
        } else if settings.autoSetSystemDNS && isCoreRunning {
            actual = matched.isEmpty ? "未检测到 App 临时 DNS" : "\(matched.count)/\(services.count) 个服务使用 App DNS"
        } else if dnsSnapshot != nil {
            actual = "存在待恢复 DNS 快照"
        } else {
            actual = "系统 DNS 由用户或系统管理"
        }
        let health: NetworkTakeoverHealth
        if readError != nil {
            health = .unknown
        } else if settings.autoSetSystemDNS && isCoreRunning {
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
            health: services.isEmpty && readError == nil ? .unknown : health,
            lastCheckedAt: checkedAt
        )
    }

    private func tunTakeoverState(checkedAt: Date) -> NetworkTakeoverState {
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
            health: health,
            lastCheckedAt: checkedAt
        )
    }
}
