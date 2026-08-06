import Foundation

extension AppStore {
    func toggleSystemProxy() async {
        guard beginNetworkOperation(.systemProxy) else { return }
        defer { endNetworkOperation(.systemProxy) }
        do {
            if systemProxyEnabled {
                let result = try await helperClient.restoreSystemProxy()
                systemProxyEnabled = false
                lastSystemProxySnapshot = systemProxy.loadSnapshot()
                recordNetworkOperation(.systemProxy, result: result)
                networkOperationMessages[.systemProxy] = result.message
                appendLog("info", result.message)
            } else {
                guard isCoreRunning else {
                    networkOperationMessages[.systemProxy] = "核心未运行，无法开启系统代理；请先启动核心。"
                    appendLog("warning", "核心未运行，无法开启系统代理；请先启动核心。")
                    return
                }
                let result = try await helperClient.setSystemProxy(host: "127.0.0.1", mixedPort: settings.mixedPort, socksPort: settings.socksPort)
                systemProxyEnabled = true
                lastSystemProxySnapshot = systemProxy.loadSnapshot()
                recordNetworkOperation(.systemProxy, result: result)
                networkOperationMessages[.systemProxy] = result.message
                appendLog("info", result.message)
            }
        } catch {
            networkOperationMessages[.systemProxy] = "系统代理操作失败：\(error.localizedDescription)"
            appendLog("error", "Helper 系统代理操作失败：\(error.localizedDescription)")
        }
        refreshNetworkTakeoverStates(force: true)
    }

    func setTunEnabled(_ enabled: Bool, force: Bool = false) async {
        guard beginNetworkOperation(.tun) else { return }
        defer { endNetworkOperation(.tun) }
        guard settings.tunEnabled != enabled else { return }
        let shouldRestoreTunBeforeDisable = settings.tunEnabled && enabled == false && isCoreRunning && settings.restoreTunOnStop
        if shouldRestoreTunBeforeDisable {
            do {
                let result = try await helperClient.restoreTunSnapshot()
                tunRecoveryStatus = result.message
                recordNetworkOperation(.tun, result: result)
                networkOperationMessages[.tun] = result.message
                appendLog("info", "关闭 TUN 前已恢复路由快照：\(result.message)")
            } catch {
                let message = "关闭 TUN 前恢复路由快照失败：\(error.localizedDescription)"
                pendingTunDisableRecoveryError = force ? nil : message
                networkOperationMessages[.tun] = force
                    ? "\(message)；用户已确认强制继续"
                    : "\(message)；已停止后续操作，请重试恢复或确认强制继续"
                appendLog(force ? "warning" : "error", networkOperationMessages[.tun] ?? message)
                if force == false {
                    refreshNetworkTakeoverStates(force: true)
                    return
                }
            }
        }
        pendingTunDisableRecoveryError = nil
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
        guard beginNetworkOperation(.systemProxy) else { return }
        defer { endNetworkOperation(.systemProxy) }
        do {
            let result = try await helperClient.restoreSystemProxy()
            systemProxyEnabled = false
            lastSystemProxySnapshot = systemProxy.loadSnapshot()
            recordNetworkOperation(.systemProxy, result: result)
            networkOperationMessages[.systemProxy] = result.message
            appendLog("info", result.message)
        } catch {
            networkOperationMessages[.systemProxy] = "系统代理修复失败：\(error.localizedDescription)"
            appendLog("error", "Helper 系统代理修复失败：\(error.localizedDescription)")
        }
        refreshNetworkTakeoverStates(force: true)
    }

    func restoreSystemDNS() async {
        guard beginNetworkOperation(.systemDNS) else { return }
        defer { endNetworkOperation(.systemDNS) }
        do {
            let result = try await helperClient.restoreSystemDNS()
            recordNetworkOperation(.systemDNS, result: result)
            networkOperationMessages[.systemDNS] = result.message
            appendLog("info", result.message)
        } catch {
            networkOperationMessages[.systemDNS] = "系统 DNS 恢复失败：\(error.localizedDescription)"
            appendLog("error", "Helper 系统 DNS 恢复失败：\(error.localizedDescription)")
        }
        refreshNetworkTakeoverStates(force: true)
    }

    func restoreTunRecovery() async {
        guard beginNetworkOperation(.tun) else { return }
        defer { endNetworkOperation(.tun) }
        do {
            let result = try await helperClient.restoreTunSnapshot()
            lastTunRecoverySnapshot = tunRecovery.loadSnapshot()
            tunRecoveryStatus = result.message
            recordNetworkOperation(.tun, result: result)
            networkOperationMessages[.tun] = result.message
            appendLog("info", result.message)
        } catch {
            tunRecoveryStatus = "TUN 回滚失败：\(error.localizedDescription)"
            networkOperationMessages[.tun] = tunRecoveryStatus
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

    func isNetworkOperationRunning(_ kind: NetworkTakeoverKind) -> Bool {
        networkOperationInProgress.contains(kind)
    }

    private func beginNetworkOperation(_ kind: NetworkTakeoverKind) -> Bool {
        guard networkOperationInProgress.contains(kind) == false else {
            networkOperationMessages[kind] = "操作正在进行，请等待当前操作完成。"
            return false
        }
        networkOperationInProgress.insert(kind)
        networkOperationMessages[kind] = "正在执行，请稍候…"
        return true
    }

    private func endNetworkOperation(_ kind: NetworkTakeoverKind) {
        networkOperationInProgress.remove(kind)
        if networkOperationMessages[kind] == "正在执行，请稍候…" {
            networkOperationMessages[kind] = nil
        }
    }
}
