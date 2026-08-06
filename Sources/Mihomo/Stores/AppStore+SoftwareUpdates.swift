import AppKit
import Foundation

extension AppStore {
    var currentAppVersion: String {
        softwareUpdateManager.currentVersion
    }

    var softwareUpdateSourceDescription: String {
        settings.softwareUpdateManifestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "GitHub Releases"
            : "自定义更新镜像（失败时回退 GitHub Releases）"
    }

    var softwareUpdateSourceURL: URL {
        SoftwareUpdateManager.githubReleasesPage
    }

    var currentAppBuild: String {
        softwareUpdateManager.currentBuild
    }

    func startSoftwareUpdateCheck() {
        guard softwareUpdatePhase.isInProgress == false, preparedSoftwareUpdate == nil else { return }
        softwareUpdateTask = Task { [weak self] in
            await self?.checkForSoftwareUpdate()
            self?.softwareUpdateTask = nil
        }
    }

    func checkForSoftwareUpdate() async {
        guard softwareUpdatePhase.isInProgress == false, preparedSoftwareUpdate == nil else { return }
        softwareUpdatePhase = .checking
        defer {
            if softwareUpdatePhase == .checking {
                softwareUpdatePhase = .idle
            }
        }
        do {
            softwareUpdateStatus = "正在检查 GitHub Releases..."
            let result = try await softwareUpdateManager.checkForUpdate(
                manifestURLs: SoftwareUpdateManager.manifestCandidates(customURLString: settings.softwareUpdateManifestURL)
            )
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
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                softwareUpdatePhase = .cancelled
                softwareUpdateStatus = "已取消检查更新"
                appendLog("info", softwareUpdateStatus)
            } else {
                softwareUpdatePhase = .failed
                softwareUpdateStatus = "更新检查失败：\(error.localizedDescription)"
                appendLog("error", softwareUpdateStatus)
            }
        }
    }

    func startSoftwareUpdateDownload() {
        guard softwareUpdatePhase.isInProgress == false, preparedSoftwareUpdate == nil else { return }
        softwareUpdateTask = Task { [weak self] in
            await self?.downloadSoftwareUpdate()
        }
    }

    func performSoftwareUpdateAction() {
        if softwareUpdatePhase == .readyToRestart {
            Task { await restartForPreparedSoftwareUpdate() }
        } else {
            startSoftwareUpdateDownload()
        }
    }

    func cancelSoftwareUpdate() {
        guard softwareUpdatePhase.isCancellable else { return }
        softwareUpdateTask?.cancel()
    }

    func discardPreparedSoftwareUpdate() {
        guard let preparedSoftwareUpdate else { return }
        softwareUpdateManager.discardPreparedUpdate(preparedSoftwareUpdate)
        self.preparedSoftwareUpdate = nil
        softwareUpdatePhase = .cancelled
        softwareUpdateStatus = "已取消已下载的更新"
    }

    func restartForPreparedSoftwareUpdate() async {
        var helperWasPrepared = false
        do {
            guard softwareUpdatePhase == .readyToRestart,
                  let preparedSoftwareUpdate,
                  let update = availableUpdate else { return }
            softwareUpdatePhase = .preparingNetwork
            if isCoreRunning
                || systemProxyEnabled
                || systemProxy.loadSnapshot() != nil
                || systemProxy.loadDNSSnapshot() != nil
                || tunRecovery.loadSnapshot() != nil {
                softwareUpdateStatus = "正在安全停止核心并恢复网络"
                try await prepareNetworkForSoftwareUpdate()
            }
            softwareUpdatePhase = .preparingHelper
            softwareUpdateStatus = "正在切换 Helper 到更新模式"
            helperWasPrepared = try await prepareHelperForSoftwareUpdate(targetVersion: update.version)
            softwareUpdatePhase = .installing
            let message = try softwareUpdateManager.launchPreparedUpdate(preparedSoftwareUpdate, version: update.version)
            self.preparedSoftwareUpdate = nil
            softwareUpdateStatus = "\(message) 正在重启..."
            appendLog("info", message)
            try? await Task.sleep(nanoseconds: 500_000_000)
            NSApp.terminate(nil)
        } catch {
            if helperWasPrepared {
                await restoreHelperAfterFailedSoftwareUpdate()
            }
            if let preparedSoftwareUpdate {
                softwareUpdateManager.discardPreparedUpdate(preparedSoftwareUpdate)
                self.preparedSoftwareUpdate = nil
            }
            softwareUpdatePhase = .failed
            softwareUpdateStatus = "更新安装失败：\(error.localizedDescription)"
            appendLog("error", softwareUpdateStatus)
        }
    }

    private func downloadSoftwareUpdate() async {
        defer { softwareUpdateTask = nil }
        var preparedPackage: PreparedUpdatePackage?
        do {
            let manifest: AppUpdateManifest
            let manifestURL: URL
            if let availableUpdate {
                manifest = availableUpdate
                if let availableUpdateManifestURL {
                    manifestURL = availableUpdateManifestURL
                } else {
                    softwareUpdatePhase = .checking
                    let result = try await softwareUpdateManager.checkForUpdate(
                        manifestURLs: SoftwareUpdateManager.manifestCandidates(customURLString: settings.softwareUpdateManifestURL)
                    )
                    manifestURL = result.manifestURL
                }
            } else {
                softwareUpdatePhase = .checking
                let result = try await softwareUpdateManager.checkForUpdate(
                    manifestURLs: SoftwareUpdateManager.manifestCandidates(customURLString: settings.softwareUpdateManifestURL)
                )
                guard result.isNewer else {
                    softwareUpdateStatus = "已是最新：\(result.currentVersion) (\(result.currentBuild))"
                    softwareUpdatePhase = .idle
                    return
                }
                manifest = result.manifest
                manifestURL = result.manifestURL
                availableUpdate = manifest
                availableUpdateManifestURL = manifestURL
            }

            softwareUpdatePhase = .downloading(.init(bytesReceived: 0, totalBytes: nil, bytesPerSecond: 0))
            softwareUpdateStatus = "正在下载 \(manifest.version)"
            let prepared = try await softwareUpdateManager.prepareUpdate(
                manifest,
                manifestURL: manifestURL,
                onDownloadProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard case .downloading = self?.softwareUpdatePhase else { return }
                        self?.softwareUpdatePhase = .downloading(progress)
                    }
                },
                onVerificationStarted: { [weak self] in
                    Task { @MainActor [weak self] in
                        guard case .downloading = self?.softwareUpdatePhase else { return }
                        self?.softwareUpdatePhase = .verifying
                        self?.softwareUpdateStatus = "正在验证 \(manifest.version)"
                    }
                }
            )
            try Task.checkCancellation()
            preparedPackage = prepared
            preparedSoftwareUpdate = prepared
            softwareUpdatePhase = .readyToRestart
            softwareUpdateStatus = "\(manifest.version) 已下载并验证，可重新启动以完成安装"
            appendLog("info", softwareUpdateStatus)
        } catch {
            if let preparedPackage {
                softwareUpdateManager.discardPreparedUpdate(preparedPackage)
            }
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                softwareUpdatePhase = .cancelled
                softwareUpdateStatus = "已取消下载更新"
                appendLog("info", softwareUpdateStatus)
            } else {
                softwareUpdatePhase = .failed
                softwareUpdateStatus = "更新下载失败：\(error.localizedDescription)"
                appendLog("error", softwareUpdateStatus)
            }
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
