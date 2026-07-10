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
            let message = try await softwareUpdateManager.installUpdate(manifest, manifestURL: manifestURL)
            softwareUpdateStatus = "\(message) 正在重启..."
            appendLog("info", message)
            try? await Task.sleep(nanoseconds: 500_000_000)
            NSApp.terminate(nil)
        } catch {
            softwareUpdateStatus = "更新安装失败：\(error.localizedDescription)"
            appendLog("error", softwareUpdateStatus)
        }
    }
}
