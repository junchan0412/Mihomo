import Foundation

extension AppStore {
    func importNodeProviders(from importedProfiles: [ProfileItem]) throws {
        guard importedProfiles.isEmpty == false else { return }
        var updatedProviders = nodeProviders
        var changed = false

        for profile in importedProfiles {
            let content = try profileStore.loadProfileContent(profile, settings: settings)
            for imported in try nodeProviderSynchronizer.nodeProviders(from: content, profileID: profile.id) {
                let sourceIdentity = imported.sourceIdentity
                if let index = updatedProviders.firstIndex(where: {
                    $0.sourceIdentity == sourceIdentity
                }) {
                    let profilesChanged = updatedProviders[index].profileIDs.contains(profile.id) == false
                    let definitionChanged = updatedProviders[index].definition != imported.definition
                    if profilesChanged {
                        updatedProviders[index].profileIDs.append(profile.id)
                    }
                    if definitionChanged {
                        updatedProviders[index].url = imported.url
                        updatedProviders[index].path = imported.path
                        updatedProviders[index].providerType = imported.providerType
                        updatedProviders[index].interval = imported.interval
                    }
                    changed = changed || profilesChanged || definitionChanged
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
            try persistNodeProviders(updatedProviders)
        }
    }

    func previewNodeProviderChange(_ updatedProviders: [NodeProvider], title: String) throws -> NodeProviderChangePreview {
        try nodeProviderStore.validate(updatedProviders)
        var patches: [NodeProviderProfilePatch] = []
        var changes: [NodeProviderProfileChange] = []
        var conflicts: [NodeProviderConflict] = []

        for profile in profiles {
            let selected = updatedProviders.filter { $0.applies(to: profile.id) }
            guard selected.isEmpty == false else { continue }
            let original = try profileStore.loadProfileContent(profile, settings: settings)
            let groups = Dictionary(grouping: selected, by: \.normalizedName)
            let duplicateGroups = groups.values.filter { $0.count > 1 }
            for group in duplicateGroups {
                guard let first = group.first else { continue }
                for duplicate in group.dropFirst() {
                    conflicts.append(NodeProviderConflict(
                        profileID: profile.id,
                        profileName: profile.name,
                        providerName: first.name,
                        incomingProviderID: duplicate.id,
                        incomingSource: sourceTitle(for: duplicate),
                        existingSource: sourceTitle(for: first),
                        differingFields: duplicate.definition.differs(from: first.definition),
                        requiresResolution: true
                    ))
                }
            }
            guard duplicateGroups.isEmpty else { continue }

            for provider in selected {
                guard let existing = try nodeProviderSynchronizer.definition(for: provider.name, in: original) else { continue }
                let differingFields = provider.definition.differs(from: existing)
                guard differingFields.isEmpty == false else { continue }
                conflicts.append(NodeProviderConflict(
                    profileID: profile.id,
                    profileName: profile.name,
                    providerName: provider.name,
                    incomingProviderID: provider.id,
                    incomingSource: sourceTitle(for: provider),
                    existingSource: "Profile 当前定义",
                    differingFields: differingFields,
                    requiresResolution: false
                ))
            }

            let synchronization = try nodeProviderSynchronizer.synchronizationPreview(
                selected,
                into: original,
                profileID: profile.id,
                profileName: profile.name
            )
            guard synchronization.content != original else { continue }
            patches.append(NodeProviderProfilePatch(
                profileID: profile.id,
                profileName: profile.name,
                originalContent: original,
                updatedContent: synchronization.content
            ))
            changes.append(contentsOf: synchronization.changes)
        }

        return NodeProviderChangePreview(
            title: title,
            proposedProviders: sortedNodeProviders(updatedProviders),
            profilePatches: patches,
            changes: changes,
            conflicts: conflicts,
            providerDelta: updatedProviders.count - nodeProviders.count,
            providersChanged: updatedProviders != nodeProviders
        )
    }

    func applyNodeProviderChange(_ preview: NodeProviderChangePreview) throws {
        guard preview.hasBlockingConflicts == false else {
            throw nodeProviderError("请先处理同一 Profile 中同名且定义不同的节点提供商冲突。")
        }
        try nodeProviderStore.validate(preview.proposedProviders)
        for patch in preview.profilePatches {
            guard let profile = profiles.first(where: { $0.id == patch.profileID }) else {
                throw nodeProviderError("配置 \(patch.profileName) 已不存在，请重新预览。")
            }
            let current = try profileStore.loadProfileContent(profile, settings: settings)
            guard current == patch.originalContent else {
                throw nodeProviderError("配置 \(patch.profileName) 已在预览后变更，请重新预览。")
            }
        }

        let snapshot = NodeProviderUndoSnapshot(
            title: preview.title,
            nodeProviders: nodeProviders,
            profiles: profiles,
            profileContents: Dictionary(uniqueKeysWithValues: preview.profilePatches.map { ($0.profileID, $0.originalContent) })
        )
        var updatedProfiles = profiles
        do {
            for patch in preview.profilePatches {
                guard let index = updatedProfiles.firstIndex(where: { $0.id == patch.profileID }) else { continue }
                updatedProfiles[index] = try profileStore.saveProfileContent(
                    updatedProfiles[index],
                    content: patch.updatedContent,
                    settings: settings
                )
            }
            try nodeProviderStore.save(preview.proposedProviders)
            try profileStore.saveProfiles(updatedProfiles)
            nodeProviders = sortedNodeProviders(preview.proposedProviders)
            profiles = updatedProfiles
            nodeProviderUndoSnapshot = snapshot
            nodeProviderUndoTitle = preview.title
            profileQualityCache.removeAll()
            refreshConfigArtifacts()
            appendLog("info", "\(preview.title)已应用：\(preview.changes.count) 处 Profile 变更")
        } catch {
            try? restoreNodeProviderSnapshot(snapshot)
            throw error
        }
    }

    func undoLastNodeProviderChange() {
        guard let snapshot = nodeProviderUndoSnapshot else { return }
        do {
            try restoreNodeProviderSnapshot(snapshot)
            nodeProviderUndoSnapshot = nil
            nodeProviderUndoTitle = nil
            appendLog("info", "已撤销\(snapshot.title)")
        } catch {
            resourceUpdateStatus = "撤销节点提供商变更失败：\(error.localizedDescription)"
            appendLog("error", resourceUpdateStatus)
        }
    }

    private func restoreNodeProviderSnapshot(_ snapshot: NodeProviderUndoSnapshot) throws {
        for profile in snapshot.profiles {
            if let content = snapshot.profileContents[profile.id] {
                _ = try profileStore.saveProfileContent(profile, content: content, settings: settings)
            }
        }
        try nodeProviderStore.save(snapshot.nodeProviders)
        try profileStore.saveProfiles(snapshot.profiles)
        nodeProviders = sortedNodeProviders(snapshot.nodeProviders)
        profiles = snapshot.profiles
        profileQualityCache.removeAll()
        refreshConfigArtifacts()
    }

    private func persistNodeProviders(_ updatedProviders: [NodeProvider]) throws {
        try nodeProviderStore.save(updatedProviders)
        nodeProviders = sortedNodeProviders(updatedProviders)
        profileQualityCache.removeAll()
        refreshConfigArtifacts()
    }

    func proposedNodeProviderSelection(_ provider: NodeProvider, enabledFor profile: ProfileItem, isSelected: Bool) -> [NodeProvider]? {
        guard let index = nodeProviders.firstIndex(where: { $0.id == provider.id }) else { return nil }
        var updated = nodeProviders
        if isSelected {
            if updated[index].profileIDs.contains(profile.id) == false {
                updated[index].profileIDs.append(profile.id)
            }
        } else {
            updated[index].profileIDs.removeAll { $0 == profile.id }
        }
        return updated
    }

    func refreshNodeProvider(_ provider: NodeProvider) async {
        guard await refreshProviderResource(provider.providerItem) else { return }
        guard let index = nodeProviders.firstIndex(where: { $0.id == provider.id }) else { return }
        var updated = nodeProviders
        updated[index].updatedAt = Date()
        do {
            let preview = try previewNodeProviderChange(updated, title: "更新节点提供商")
            try applyNodeProviderChange(preview)
        } catch {
            resourceUpdateStatus = "更新节点提供商失败：\(error.localizedDescription)"
            appendLog("error", resourceUpdateStatus)
        }
    }

    private func sortedNodeProviders(_ providers: [NodeProvider]) -> [NodeProvider] {
        providers.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame
                ? $0.sourceIdentity < $1.sourceIdentity
                : comparison == .orderedAscending
        }
    }

    private func sourceTitle(for provider: NodeProvider) -> String {
        guard let profileID = provider.sourceProfileID else { return "独立节点提供商" }
        return profiles.first(where: { $0.id == profileID }).map { "配置：\($0.name)" } ?? "已删除配置"
    }

    private func nodeProviderError(_ message: String) -> NSError {
        NSError(domain: "Mihomo.NodeProvider", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
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
