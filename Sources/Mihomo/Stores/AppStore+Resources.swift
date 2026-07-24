import Foundation

extension AppStore {
    func saveNodeProviders(_ updatedProviders: [NodeProvider]) {
        do {
            try persistNodeProviders(updatedProviders, synchronizeProfiles: true)
            appendLog("info", "已保存 \(nodeProviders.count) 个独立节点提供商，并同步关联配置")
        } catch {
            resourceUpdateStatus = "保存节点提供商失败：\(error.localizedDescription)"
            appendLog("error", resourceUpdateStatus)
        }
    }

    func importNodeProviders(from importedProfiles: [ProfileItem]) throws {
        guard importedProfiles.isEmpty == false else { return }
        var updatedProviders = nodeProviders
        var changed = false

        for profile in importedProfiles {
            let content = try profileStore.loadProfileContent(profile, settings: settings)
            for imported in try nodeProviderSynchronizer.nodeProviders(from: content, profileID: profile.id) {
                let normalizedName = imported.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if let index = updatedProviders.firstIndex(where: {
                    $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        .caseInsensitiveCompare(normalizedName) == .orderedSame
                }) {
                    if updatedProviders[index].profileIDs.contains(profile.id) == false {
                        updatedProviders[index].profileIDs.append(profile.id)
                        changed = true
                    }
                } else {
                    var provider = imported
                    provider.group = "从配置导入"
                    provider.tags = ["配置导入"]
                    updatedProviders.append(provider)
                    changed = true
                }
            }
        }

        if changed {
            try persistNodeProviders(updatedProviders, synchronizeProfiles: true)
        }
    }

    private func persistNodeProviders(_ updatedProviders: [NodeProvider], synchronizeProfiles: Bool) throws {
        try nodeProviderStore.save(updatedProviders)
        nodeProviders = updatedProviders.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        if synchronizeProfiles {
            try synchronizeNodeProvidersIntoProfiles()
        }
        profileQualityCache.removeAll()
        refreshConfigArtifacts()
    }

    private func synchronizeNodeProvidersIntoProfiles() throws {
        var updatedProfiles = profiles
        var changed = false
        for index in updatedProfiles.indices {
            let profile = updatedProfiles[index]
            let selected = nodeProviders.filter { $0.applies(to: profile.id) }
            guard selected.isEmpty == false else { continue }
            let original = try profileStore.loadProfileContent(profile, settings: settings)
            let synchronized = try nodeProviderSynchronizer.synchronizing(selected, into: original)
            guard synchronized != original else { continue }
            updatedProfiles[index] = try profileStore.saveProfileContent(profile, content: synchronized, settings: settings)
            changed = true
        }
        if changed {
            profiles = updatedProfiles
            try profileStore.saveProfiles(updatedProfiles)
        }
    }

    func setNodeProvider(_ provider: NodeProvider, enabledFor profile: ProfileItem, isSelected: Bool) {
        guard let index = nodeProviders.firstIndex(where: { $0.id == provider.id }) else { return }
        var updated = nodeProviders
        if isSelected {
            if updated[index].profileIDs.contains(profile.id) == false {
                updated[index].profileIDs.append(profile.id)
            }
        } else {
            updated[index].profileIDs.removeAll { $0 == profile.id }
        }
        saveNodeProviders(updated)
    }

    func refreshNodeProvider(_ provider: NodeProvider) async {
        guard await refreshProviderResource(provider.providerItem) else { return }
        guard let index = nodeProviders.firstIndex(where: { $0.id == provider.id }) else { return }
        var updated = nodeProviders
        updated[index].updatedAt = Date()
        saveNodeProviders(updated)
    }

    func refreshGeoDataStatus() {
        let expected = ["geoip.dat", "geosite.dat", "Country.mmdb", "ASN.mmdb"]
        let existing = expected.filter {
            FileManager.default.fileExists(atPath: AppPaths.geoDirectory.appendingPathComponent($0).path)
        }
        geoUpdateStatus = existing.count == expected.count
            ? "四项 Geo 数据完整"
            : "Geo 数据 \(existing.count)/\(expected.count) 项"
    }

    @discardableResult
    func updateProviderResource(_ provider: ProviderItem) async -> Bool {
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
            return true
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
            return false
        }
    }

    @discardableResult
    func refreshProviderResource(_ provider: ProviderItem) async -> Bool {
        if provider.remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return await updateProviderResource(provider)
        }

        do {
            let result = try ProviderResourceManager().refreshLocal(provider)
            resourceUpdateStatus = "\(provider.name) 已重新载入：\(Formatters.bytes(result.size))"
            recordProviderUpdate(
                provider,
                action: "本地刷新",
                succeeded: true,
                targetPath: result.target.path,
                message: resourceUpdateStatus
            )
            refreshConfigArtifacts()
            return true
        } catch {
            resourceUpdateStatus = "\(provider.name) 重新载入失败：\(error.localizedDescription)"
            appendLog("error", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "本地刷新",
                succeeded: false,
                targetPath: provider.path ?? "-",
                message: error.localizedDescription
            )
            return false
        }
    }

    func providerUpdateHistory(for provider: ProviderItem) -> [ProviderUpdateRecord] {
        providerUpdateHistory.filter {
            providerHistoryKey(kind: $0.providerKind, name: $0.providerName) == providerHistoryKey(for: provider)
        }
    }

    func providerHistoryKey(for provider: ProviderItem) -> String {
        providerHistoryKey(kind: provider.kind, name: provider.name)
    }

    func providerHistoryKey(kind: String, name: String) -> String {
        let normalizedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalizedKind)\u{1F}\(normalizedName)"
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
        let providerItems = providers + nodeProviders.map(\.providerItem)
        let maxConcurrent = max(1, min(settings.resourceUpdateMaxConcurrent, 12))
        var succeeded = 0
        var failed = 0
        var completed = 0

        resourceUpdateStatus = "正在更新 \(providerItems.count) 个本地与远程资源（并发 \(maxConcurrent)）及 Geo 数据..."
        for batchStart in stride(from: 0, to: providerItems.count, by: maxConcurrent) {
            let batchEnd = min(batchStart + maxConcurrent, providerItems.count)
            let batch = Array(providerItems[batchStart..<batchEnd])

            await withTaskGroup(of: ProviderResourceUpdateResult.self) { group in
                for provider in batch {
                    group.addTask {
                        do {
                            if provider.remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                                let result = try await ProviderResourceManager().download(provider)
                                return ProviderResourceUpdateResult(
                                    provider: provider,
                                    action: "批量下载",
                                    targetPath: result.target.path,
                                    backupPath: result.backup?.path,
                                    errorMessage: nil
                                )
                            }
                            let result = try ProviderResourceManager().refreshLocal(provider)
                            return ProviderResourceUpdateResult(
                                provider: provider,
                                action: "本地刷新",
                                targetPath: result.target.path,
                                backupPath: nil,
                                errorMessage: nil
                            )
                        } catch {
                            return ProviderResourceUpdateResult(
                                provider: provider,
                                action: provider.remoteURL == nil ? "本地刷新" : "批量下载",
                                targetPath: provider.path ?? "-",
                                backupPath: nil,
                                errorMessage: error.localizedDescription
                            )
                        }
                    }
                }

                for await result in group {
                    completed += 1
                    if result.errorMessage == nil {
                        succeeded += 1
                        recordProviderUpdate(
                            result.provider,
                            action: result.action,
                            succeeded: true,
                            targetPath: result.targetPath,
                            message: result.backupPath == nil ? "资源刷新成功" : "资源更新成功；已备份上一版：\(result.backupPath ?? "")",
                            backupPath: result.backupPath
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
            resourceUpdateStatus = "当前配置没有 Provider，正在更新 Geo 数据..."
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
            countryMMDBURL: settings.countryMMDBURL,
            asnMMDBURL: settings.asnMMDBURL,
            geoIPSHA256: settings.geoIPSHA256,
            geoSiteSHA256: settings.geoSiteSHA256,
            countryMMDBSHA256: settings.countryMMDBSHA256,
            asnMMDBSHA256: settings.asnMMDBSHA256
        )
        try syncGeoDataToRuntimeDirectory()
        geoUpdateStatus = status
        return status
    }

    func syncGeoDataToRuntimeDirectory() throws {
        try AppPaths.ensureBaseDirectories()
        let pairs: [(source: String, targets: [String])] = [
            ("geoip.dat", ["geoip.dat", "GeoIP.dat"]),
            ("geosite.dat", ["geosite.dat", "GeoSite.dat"]),
            ("Country.mmdb", ["Country.mmdb"]),
            ("ASN.mmdb", ["ASN.mmdb"])
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
        if providerUpdateHistory.count > 500 {
            providerUpdateHistory.removeLast(providerUpdateHistory.count - 500)
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
    var action: String
    var targetPath: String
    var backupPath: String?
    var errorMessage: String?
}
