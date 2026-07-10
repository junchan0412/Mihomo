import Foundation

extension AppStore {
    func refreshProvidersFromController() async {
        do {
            providers = try await controllerClient().providers()
            updateRuleProviderHitStatistics()
            advancedStatus = "已从 Controller 读取 \(providers.count) 个 Provider"
        } catch {
            appendLog("warning", "Controller Provider 读取失败，保留本地解析结果：\(error.localizedDescription)")
            refreshConfigArtifacts()
        }
    }

    func updateProvider(_ provider: ProviderItem) async {
        do {
            try await controllerClient().updateProvider(provider)
            appendLog("info", "已请求更新 \(provider.kind) Provider：\(provider.name)")
            recordProviderUpdate(
                provider,
                action: "Controller",
                succeeded: true,
                targetPath: "-",
                message: "Controller 已接受更新请求"
            )
            await refreshProvidersFromController()
        } catch {
            appendLog("error", "Provider 更新失败：\(error.localizedDescription)")
            recordProviderUpdate(
                provider,
                action: "Controller",
                succeeded: false,
                targetPath: "-",
                message: error.localizedDescription
            )
        }
    }

    func updateProviderResource(_ provider: ProviderItem) async {
        do {
            let result = try await ProviderResourceManager().download(provider)
            let backupSuffix = result.backup.map { "；已备份上一版：\($0.path)" } ?? ""
            resourceUpdateStatus = "\(provider.name) 已更新：\(result.target.path)\(backupSuffix)"
            appendLog("info", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "下载",
                succeeded: true,
                targetPath: result.target.path,
                message: resourceUpdateStatus,
                backupPath: result.backup?.path
            )
            refreshConfigArtifacts()
        } catch {
            resourceUpdateStatus = "\(provider.name) 更新失败：\(error.localizedDescription)"
            appendLog("error", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "下载",
                succeeded: false,
                targetPath: provider.path ?? "-",
                message: error.localizedDescription
            )
        }
    }

    func providerUpdateHistory(for provider: ProviderItem) -> [ProviderUpdateRecord] {
        providerUpdateHistory.filter {
            $0.providerKind == provider.kind && $0.providerName == provider.name
        }
    }

    func latestProviderRollbackRecord(for provider: ProviderItem) -> ProviderUpdateRecord? {
        providerUpdateHistory(for: provider).first { record in
            guard let path = record.backupPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  path.isEmpty == false
            else {
                return false
            }
            return FileManager.default.fileExists(atPath: path)
        }
    }

    func rollbackProviderResource(_ provider: ProviderItem) async {
        guard let record = latestProviderRollbackRecord(for: provider),
              let backupPath = record.backupPath
        else {
            resourceUpdateStatus = "\(provider.name) 没有可用的 Provider 备份。"
            appendLog("warning", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "回滚",
                succeeded: false,
                targetPath: provider.path ?? "-",
                message: resourceUpdateStatus
            )
            return
        }

        do {
            let result = try ProviderResourceManager().rollback(provider, from: URL(fileURLWithPath: backupPath))
            resourceUpdateStatus = "\(provider.name) 已回滚：\(result.restoredFrom.path)"
            appendLog("info", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "回滚",
                succeeded: true,
                targetPath: result.target.path,
                message: resourceUpdateStatus,
                backupPath: result.replacedBackup?.path,
                restoredFromPath: result.restoredFrom.path
            )
            refreshConfigArtifacts()
        } catch {
            resourceUpdateStatus = "\(provider.name) 回滚失败：\(error.localizedDescription)"
            appendLog("error", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "回滚",
                succeeded: false,
                targetPath: provider.path ?? "-",
                message: error.localizedDescription,
                restoredFromPath: backupPath
            )
        }
    }

    func updateAllExternalResources() async {
        refreshConfigArtifacts()
        let providerItems = providers.filter {
            $0.remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        let maxConcurrent = max(1, min(settings.profileRefreshMaxConcurrent, 8))
        var succeeded = 0
        var failed = 0
        var completed = 0

        resourceUpdateStatus = "正在并发更新 \(providerItems.count) 个 Provider（并发 \(maxConcurrent)）与 Geo 数据..."
        for batchStart in stride(from: 0, to: providerItems.count, by: maxConcurrent) {
            let batchEnd = min(batchStart + maxConcurrent, providerItems.count)
            let batch = Array(providerItems[batchStart..<batchEnd])

            await withTaskGroup(of: ProviderResourceUpdateResult.self) { group in
                for provider in batch {
                    group.addTask {
                        do {
                            let result = try await ProviderResourceManager().download(provider)
                            return ProviderResourceUpdateResult(provider: provider, download: result, errorMessage: nil)
                        } catch {
                            return ProviderResourceUpdateResult(provider: provider, download: nil, errorMessage: error.localizedDescription)
                        }
                    }
                }

                for await result in group {
                    completed += 1
                    if let download = result.download {
                        succeeded += 1
                        recordProviderUpdate(
                            result.provider,
                            action: "批量下载",
                            succeeded: true,
                            targetPath: download.target.path,
                            message: download.backup == nil ? "批量更新成功" : "批量更新成功；已备份上一版：\(download.backup?.path ?? "")",
                            backupPath: download.backup?.path
                        )
                    } else {
                        failed += 1
                        let message = result.errorMessage ?? "未知错误"
                        appendLog("error", "\(result.provider.name) 更新失败：\(message)")
                        recordProviderUpdate(
                            result.provider,
                            action: "批量下载",
                            succeeded: false,
                            targetPath: result.provider.path ?? "-",
                            message: message
                        )
                    }
                    resourceUpdateStatus = "Provider 更新 \(completed)/\(providerItems.count)，成功 \(succeeded)，失败 \(failed)..."
                }
            }
        }

        if providerItems.isEmpty {
            resourceUpdateStatus = "没有需要下载的 Provider，正在更新 Geo 数据..."
        }

        do {
            let geoStatus = try await updateGeoDataInternal()
            resourceUpdateStatus = "Provider 成功 \(succeeded)，失败 \(failed)；\(geoStatus)"
        } catch {
            resourceUpdateStatus = "Provider 成功 \(succeeded)，失败 \(failed)；Geo 更新失败：\(error.localizedDescription)"
            appendLog("error", resourceUpdateStatus)
        }
        refreshConfigArtifacts()
        appendLog(failed == 0 ? "info" : "warning", resourceUpdateStatus)
    }

    func updateGeoDataInternal() async throws -> String {
        let status = try await geoUpdateManager.update(
            geoIPURL: settings.geoIPURL,
            geoSiteURL: settings.geoSiteURL,
            geoIPSHA256: settings.geoIPSHA256,
            geoSiteSHA256: settings.geoSiteSHA256
        )
        try syncGeoDataToRuntimeDirectory()
        geoUpdateStatus = status
        return status
    }

    func syncGeoDataToRuntimeDirectory() throws {
        try AppPaths.ensureBaseDirectories()
        let pairs: [(source: String, targets: [String])] = [
            ("geoip.dat", ["geoip.dat", "GeoIP.dat"]),
            ("geosite.dat", ["geosite.dat", "GeoSite.dat"])
        ]
        for pair in pairs {
            let source = AppPaths.geoDirectory.appendingPathComponent(pair.source)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            for targetName in pair.targets {
                let target = AppPaths.runtimeDirectory.appendingPathComponent(targetName)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: source, to: target)
            }
        }
    }

    func loadProviderUpdateHistory() -> [ProviderUpdateRecord] {
        guard FileManager.default.fileExists(atPath: AppPaths.providerUpdateHistoryFile.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: AppPaths.providerUpdateHistoryFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ProviderUpdateRecord].self, from: data)
        } catch {
            appendLog("warning", "Provider 更新历史读取失败：\(error.localizedDescription)")
            return []
        }
    }

    private func recordProviderUpdate(
        _ provider: ProviderItem,
        action: String,
        succeeded: Bool,
        targetPath: String,
        message: String,
        backupPath: String? = nil,
        restoredFromPath: String? = nil
    ) {
        providerUpdateHistory.insert(.init(
            providerName: provider.name,
            providerKind: provider.kind,
            action: action,
            succeeded: succeeded,
            targetPath: targetPath,
            message: message,
            backupPath: backupPath,
            restoredFromPath: restoredFromPath
        ), at: 0)
        if providerUpdateHistory.count > 80 {
            providerUpdateHistory.removeLast(providerUpdateHistory.count - 80)
        }
        saveProviderUpdateHistory()
    }

    private func saveProviderUpdateHistory() {
        do {
            try AppPaths.ensureBaseDirectories()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(providerUpdateHistory)
            try data.write(to: AppPaths.providerUpdateHistoryFile, options: .atomic)
        } catch {
            appendLog("warning", "Provider 更新历史保存失败：\(error.localizedDescription)")
        }
    }
}

private struct ProviderResourceUpdateResult {
    var provider: ProviderItem
    var download: ProviderResourceDownloadResult?
    var errorMessage: String?
}
