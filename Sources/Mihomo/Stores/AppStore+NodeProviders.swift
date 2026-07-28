import Foundation

extension AppStore {
    func importNodeProviders(from importedProfiles: [ProfileItem]) throws {
        guard importedProfiles.isEmpty == false else { return }
        var updatedProviders = NodeProvider.canonicalized(nodeProviders)

        for profile in importedProfiles {
            let content = try profileStore.loadProfileContent(profile, settings: settings)
            for imported in try nodeProviderSynchronizer.nodeProviders(from: content, profileID: profile.id) {
                var provider = imported
                provider.group = "从配置导入"
                provider.tags = ["配置导入"]
                updatedProviders.append(provider)
                updatedProviders = NodeProvider.canonicalized(updatedProviders)
            }
        }

        if updatedProviders != nodeProviders {
            try persistNodeProviders(updatedProviders)
        }
    }

    func previewNodeProviderChange(_ updatedProviders: [NodeProvider], title: String) throws -> NodeProviderChangePreview {
        let proposedProviders = NodeProvider.canonicalized(updatedProviders)
        try nodeProviderStore.validate(proposedProviders)
        var patches: [NodeProviderProfilePatch] = []
        var changes: [NodeProviderProfileChange] = []
        var conflicts: [NodeProviderConflict] = []

        for profile in profiles {
            let selected = proposedProviders.filter { $0.applies(to: profile.id) }
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
            proposedProviders: sortedNodeProviders(proposedProviders),
            profilePatches: patches,
            changes: changes,
            conflicts: conflicts,
            providerDelta: proposedProviders.count - nodeProviders.count,
            providersChanged: proposedProviders != nodeProviders,
            deduplicatedProviderCount: max(0, updatedProviders.count - proposedProviders.count)
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

}
