import AppKit
import Foundation

extension AppStore {
    var currentAppVersion: String {
        softwareUpdateManager.currentVersion
    }

    var softwareUpdateSourceDescription: String {
        "GitHub Releases"
    }

    var softwareUpdateSourceURL: URL {
        SoftwareUpdateManager.githubReleasesPage
    }

    var currentAppBuild: String {
        softwareUpdateManager.currentBuild
    }

    func checkForSoftwareUpdate() async {
        do {
            softwareUpdateStatus = "正在检查 GitHub Releases..."
            let result = try await softwareUpdateManager.checkForUpdate()
            if result.isNewer {
                availableUpdate = result.manifest
                availableUpdateManifestURL = result.manifestURL
                let build = result.manifest.build.map { " (\($0))" } ?? ""
                softwareUpdateStatus = "发现新版本 \(result.manifest.version)\(build)，当前 \(result.currentVersion) (\(result.currentBuild))"
            } else {
                availableUpdate = nil
                availableUpdateManifestURL = nil
                softwareUpdateStatus = "已是最新版本：\(result.currentVersion) (\(result.currentBuild))"
            }
            appendLog("info", softwareUpdateStatus)
        } catch {
            softwareUpdateStatus = "更新检查失败：\(error.localizedDescription)"
            appendLog("error", softwareUpdateStatus)
        }
    }

    func installSoftwareUpdate() async {
        var helperWasPrepared = false
        var preparedPackage: PreparedUpdatePackage?
        do {
            let manifest: AppUpdateManifest
            let manifestURL: URL
            if let availableUpdate {
                manifest = availableUpdate
                if let availableUpdateManifestURL {
                    manifestURL = availableUpdateManifestURL
                } else {
                    let result = try await softwareUpdateManager.checkForUpdate()
                    manifestURL = result.manifestURL
                }
            } else {
                let result = try await softwareUpdateManager.checkForUpdate()
                guard result.isNewer else {
                    softwareUpdateStatus = "已是最新：\(result.currentVersion) (\(result.currentBuild))"
                    return
                }
                manifest = result.manifest
                manifestURL = result.manifestURL
                availableUpdate = manifest
                availableUpdateManifestURL = manifestURL
            }

            softwareUpdateStatus = "正在下载 \(manifest.version)"
            let prepared = try await softwareUpdateManager.prepareUpdate(manifest, manifestURL: manifestURL)
            preparedPackage = prepared
            if isCoreRunning
                || systemProxyEnabled
                || systemProxy.loadSnapshot() != nil
                || systemProxy.loadDNSSnapshot() != nil
                || tunRecovery.loadSnapshot() != nil {
                softwareUpdateStatus = "正在安全停止核心并恢复网络"
                try await prepareNetworkForSoftwareUpdate()
            }
            softwareUpdateStatus = "正在切换 Helper 到更新模式"
            helperWasPrepared = try await prepareHelperForSoftwareUpdate(targetVersion: manifest.version)
            let message = try softwareUpdateManager.launchPreparedUpdate(prepared, version: manifest.version)
            preparedPackage = nil
            softwareUpdateStatus = "\(message) 正在重启..."
            appendLog("info", message)
            try? await Task.sleep(nanoseconds: 500_000_000)
            NSApp.terminate(nil)
        } catch {
            if let preparedPackage {
                softwareUpdateManager.discardPreparedUpdate(preparedPackage)
            }
            if helperWasPrepared {
                await restoreHelperAfterFailedSoftwareUpdate()
            }
            softwareUpdateStatus = "更新安装失败：\(error.localizedDescription)"
            appendLog("error", softwareUpdateStatus)
        }
    }

    private func softwareUpdateError(_ message: String) -> NSError {
        NSError(domain: "Mihomo.SoftwareUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func prepareNetworkForSoftwareUpdate() async throws {
        _ = try await helperClient.version()
        let restoreDNS = systemProxy.loadDNSSnapshot() != nil
        let restoreTun = tunRecovery.loadSnapshot() != nil
        let stopResult = try await helperClient.stopCore(restoreDNS: restoreDNS, restoreTun: restoreTun)
        isCoreRunning = false
        coreStatus = "已停止"
        stopControllerEventStreams(status: "轮询")
        appendLog("info", "更新前已停止核心并恢复 DNS/TUN：\(stopResult.message)")

        if systemProxyEnabled || systemProxy.loadSnapshot() != nil {
            let proxyResult = try await helperClient.restoreSystemProxy()
            systemProxyEnabled = false
            appendLog("info", "更新前已恢复系统代理：\(proxyResult.message)")
        }

        lastSystemProxySnapshot = systemProxy.loadSnapshot()
        lastSystemDNSSnapshot = systemProxy.loadDNSSnapshot()
        lastTunRecoverySnapshot = tunRecovery.loadSnapshot()
        refreshNetworkTakeoverStates(force: true)
        guard lastSystemProxySnapshot == nil,
              lastSystemDNSSnapshot == nil,
              lastTunRecoverySnapshot == nil,
              systemProxyEnabled == false else {
            throw softwareUpdateError("网络快照仍未恢复，已取消更新；请先在诊断页完成代理、DNS 与 TUN 恢复。")
        }
    }
}
