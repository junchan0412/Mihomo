import Foundation
import MihomoShared

extension AppStore {
    func refreshConfigArtifacts() {
        guard let activeProfile else {
            publishIfChanged(\.rules, [])
            publishIfChanged(\.providers, [])
            publishIfChanged(\.offlineProxyGroups, [])
            publishIfChanged(\.configPreview, "")
            publishIfChanged(\.configDiff, "")
            spotlightIndexer.index(profiles: profiles, providers: providers)
            return
        }

        do {
            let original = try profileStore.loadProfileContent(activeProfile, settings: settings)
            let snapshot = try ProfileYAMLStructureEditor().snapshot(content: original)
            publishIfChanged(\.rules, configFragmentStore.parseRules(profileContent: original, disabledRules: disabledRules))
            publishIfChanged(\.providers, configFragmentStore.parseProviders(profileContent: original))
            publishIfChanged(\.offlineProxyGroups, makeOfflineProxyGroups(from: snapshot))
            let candidate = try profileStore.generateRuntimeConfigCandidate(
                profile: activeProfile,
                settings: settings,
                fragments: configFragments,
                disabledRules: disabledRules
            )
            let preview = try String(contentsOf: candidate, encoding: .utf8)
            publishIfChanged(\.configPreview, preview)
            publishIfChanged(\.configDiff, configFragmentStore.makeDiff(original: original, generated: preview))
            updateRuleProviderHitStatistics()
            spotlightIndexer.index(profiles: profiles, providers: providers)
            advancedStatus = "配置预览已更新：\(Formatters.shortDate.string(from: Date()))"
        } catch {
            advancedStatus = "配置预览失败：\(error.localizedDescription)"
            appendLog("error", advancedStatus)
        }
    }

    func focusRule(for connection: ConnectionItem) {
        let query = ruleHitKey(type: connection.ruleType, payload: connection.rulePayload)
        ruleFocusQuery = query.isEmpty ? connection.rule : query
        selectedSection = .rules
        appendLog("info", "从连接跳转到规则：\(ruleFocusQuery)")
    }

    func toggleRuleDisabled(_ rule: RuleItem, undoManager: UndoManager? = nil) {
        setRulesDisabled([rule], disabled: disabledRules.contains(rule.content) == false, undoManager: undoManager)
    }

    func setRulesDisabled(_ rules: [RuleItem], disabled: Bool, undoManager: UndoManager? = nil) {
        guard rules.isEmpty == false else { return }
        let previous = disabledRules
        for rule in rules {
            if disabled {
                disabledRules.insert(rule.content)
            } else {
                disabledRules.remove(rule.content)
            }
        }
        do {
            try configFragmentStore.saveDisabledRules(disabledRules)
            refreshConfigArtifacts()
            appendLog("info", "已\(disabled ? "禁用" : "启用") \(rules.count) 条规则")
            if let undoManager {
                registerDisabledRulesUndo(
                    previous: previous,
                    inverse: disabledRules,
                    actionName: disabled ? "禁用规则" : "启用规则",
                    undoManager: undoManager
                )
            }
        } catch {
            disabledRules = previous
            appendLog("error", "保存禁用规则失败：\(error.localizedDescription)")
        }
    }

    func upsertActiveProfileRule(originalIndex: Int?, rule: EditableProfileRule, undoManager: UndoManager? = nil) async {
        guard let activeProfile,
              let profileIndex = profiles.firstIndex(where: { $0.id == activeProfile.id })
        else {
            appendLog("error", "没有可编辑的当前配置")
            return
        }

        do {
            let content = try profileStore.loadProfileContent(activeProfile, settings: settings)
            let updatedContent = try ProfileYAMLStructureEditor().upsertRule(
                content: content,
                originalIndex: originalIndex,
                rule: rule
            )
            let before = ProfileConfigMutationSnapshot(content: content, disabledRules: disabledRules)
            let after = ProfileConfigMutationSnapshot(content: updatedContent, disabledRules: disabledRules)
            try saveProfileMutation(profileIndex: profileIndex, profile: activeProfile, snapshot: after)
            registerProfileMutationUndo(
                profileID: activeProfile.id,
                snapshot: before,
                inverse: after,
                actionName: originalIndex == nil ? "添加规则" : "编辑规则",
                undoManager: undoManager
            )
            appendLog("info", originalIndex == nil ? "已添加规则" : "已保存规则 \(originalIndex ?? rule.index)")
        } catch {
            appendLog("error", "规则保存失败：\(error.localizedDescription)")
        }
    }

    func deleteActiveProfileRule(index: Int, undoManager: UndoManager? = nil) async {
        await deleteActiveProfileRules(indices: [index], undoManager: undoManager)
    }

    func deleteActiveProfileRules(indices: [Int], undoManager: UndoManager? = nil) async {
        guard let activeProfile,
              let profileIndex = profiles.firstIndex(where: { $0.id == activeProfile.id })
        else {
            appendLog("error", "没有可编辑的当前配置")
            return
        }

        do {
            let content = try profileStore.loadProfileContent(activeProfile, settings: settings)
            let uniqueIndices = Array(Set(indices)).sorted(by: >)
            var updatedContent = content
            var updatedDisabledRules = disabledRules
            for index in uniqueIndices {
                if let removedRule = rules.first(where: { $0.index == index }) {
                    updatedDisabledRules.remove(removedRule.content)
                }
                updatedContent = try ProfileYAMLStructureEditor().deleteRule(content: updatedContent, index: index)
            }

            let before = ProfileConfigMutationSnapshot(content: content, disabledRules: disabledRules)
            let after = ProfileConfigMutationSnapshot(content: updatedContent, disabledRules: updatedDisabledRules)
            try saveProfileMutation(profileIndex: profileIndex, profile: activeProfile, snapshot: after)
            registerProfileMutationUndo(
                profileID: activeProfile.id,
                snapshot: before,
                inverse: after,
                actionName: uniqueIndices.count == 1 ? "删除规则" : "删除多个规则",
                undoManager: undoManager
            )
            appendLog("info", "已删除 \(uniqueIndices.count) 条规则")
        } catch {
            appendLog("error", "规则删除失败：\(error.localizedDescription)")
        }
    }

    func resetRuleHitStatistics() {
        ruleHitBaselines = ruleHitTotals
        updateRuleProviderHitStatistics()
        appendLog("info", "规则使用计数已重置")
    }

    func addConfigFragment(name: String, kind: ConfigFragmentKind, content: String, undoManager: UndoManager? = nil) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.isEmpty == false else { return }
        var fragment = ConfigFragment(
            name: trimmedName.isEmpty ? (kind == .yaml ? "YAML 片段" : "JS 片段") : trimmedName,
            kind: kind,
            enabled: true,
            content: content
        )
        fragment.updatedAt = Date()
        addConfigFragment(fragment, undoManager: undoManager)
    }

    func addConfigFragment(_ fragment: ConfigFragment, undoManager: UndoManager? = nil) {
        var updated = fragment
        updated.updatedAt = Date()
        commitConfigFragments(
            configFragments + [updated],
            actionName: "添加覆写",
            undoManager: undoManager
        )
    }

    func updateConfigFragment(_ fragment: ConfigFragment, undoManager: UndoManager? = nil) {
        guard let index = configFragments.firstIndex(where: { $0.id == fragment.id }) else { return }
        var updated = fragment
        updated.updatedAt = Date()
        var next = configFragments
        next[index] = updated
        commitConfigFragments(next, actionName: "编辑覆写", undoManager: undoManager)
    }

    func deleteConfigFragment(_ fragment: ConfigFragment, undoManager: UndoManager? = nil) {
        deleteConfigFragments([fragment], undoManager: undoManager)
    }

    func deleteConfigFragments(_ fragments: [ConfigFragment], undoManager: UndoManager? = nil) {
        let identifiers = Set(fragments.map(\.id))
        guard identifiers.isEmpty == false else { return }
        let next = configFragments.filter { identifiers.contains($0.id) == false }
        commitConfigFragments(
            next,
            actionName: identifiers.count == 1 ? "删除覆写" : "删除多个覆写",
            undoManager: undoManager
        )
    }

    func updateRuleProviderHitStatistics() {
        ingestNewConnectionHits()

        let updatedRules = rules.map { rule in
            var updated = rule
            let key = ruleHitKey(content: rule.content)
            let resetBaseline = ruleHitBaselines[key, default: 0]
            updated.hitCount = max(0, ruleHitTotals[key, default: 0] - resetBaseline)
            return updated
        }
        publishIfChanged(\.rules, updatedRules)

        let updatedProviders = providers.map { provider in
            var updated = provider
            updated.hitCount = providerHitTotals[provider.id, default: 0]
            return updated
        }
        publishIfChanged(\.providers, updatedProviders)
    }

    private func commitConfigFragments(
        _ next: [ConfigFragment],
        actionName: String,
        undoManager: UndoManager?
    ) {
        let previous = configFragments
        configFragments = next
        do {
            try configFragmentStore.saveFragments(configFragments)
            refreshConfigArtifacts()
            appendLog("info", "覆写片段已保存")
            if let undoManager {
                registerConfigFragmentsUndo(
                    snapshot: previous,
                    inverse: next,
                    actionName: actionName,
                    undoManager: undoManager
                )
            }
        } catch {
            configFragments = previous
            appendLog("error", "覆写片段保存失败：\(error.localizedDescription)")
        }
    }

    private func registerConfigFragmentsUndo(
        snapshot: [ConfigFragment],
        inverse: [ConfigFragment],
        actionName: String,
        undoManager: UndoManager
    ) {
        undoManager.registerUndo(withTarget: self) { target in
            target.applyConfigFragmentsSnapshot(
                snapshot,
                inverse: inverse,
                actionName: actionName,
                undoManager: undoManager
            )
        }
        undoManager.setActionName(actionName)
    }

    private func applyConfigFragmentsSnapshot(
        _ snapshot: [ConfigFragment],
        inverse: [ConfigFragment],
        actionName: String,
        undoManager: UndoManager
    ) {
        do {
            configFragments = snapshot
            try configFragmentStore.saveFragments(configFragments)
            refreshConfigArtifacts()
            registerConfigFragmentsUndo(
                snapshot: inverse,
                inverse: snapshot,
                actionName: actionName,
                undoManager: undoManager
            )
            appendLog("info", "已执行撤销/重做：\(actionName)")
        } catch {
            appendLog("error", "覆写撤销/重做失败：\(error.localizedDescription)")
        }
    }

    private func saveProfileMutation(
        profileIndex: Int,
        profile: ProfileItem,
        snapshot: ProfileConfigMutationSnapshot
    ) throws {
        let updatedProfile = try profileStore.saveProfileContent(profile, content: snapshot.content, settings: settings)
        profiles[profileIndex] = updatedProfile
        disabledRules = snapshot.disabledRules
        try configFragmentStore.saveDisabledRules(disabledRules)
        try profileStore.saveProfiles(profiles)
        refreshConfigArtifacts()
    }

    private func registerProfileMutationUndo(
        profileID: UUID,
        snapshot: ProfileConfigMutationSnapshot,
        inverse: ProfileConfigMutationSnapshot,
        actionName: String,
        undoManager: UndoManager?
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            Task {
                await target.applyProfileMutation(
                    profileID: profileID,
                    snapshot: snapshot,
                    inverse: inverse,
                    actionName: actionName,
                    undoManager: undoManager
                )
            }
        }
        undoManager.setActionName(actionName)
    }

    private func applyProfileMutation(
        profileID: UUID,
        snapshot: ProfileConfigMutationSnapshot,
        inverse: ProfileConfigMutationSnapshot,
        actionName: String,
        undoManager: UndoManager
    ) async {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let profile = profiles[profileIndex]
        do {
            try saveProfileMutation(profileIndex: profileIndex, profile: profile, snapshot: snapshot)
            registerProfileMutationUndo(
                profileID: profileID,
                snapshot: inverse,
                inverse: snapshot,
                actionName: actionName,
                undoManager: undoManager
            )
            appendLog("info", "已执行撤销/重做：\(actionName)")
        } catch {
            appendLog("error", "撤销/重做失败：\(error.localizedDescription)")
        }
    }

    private func registerDisabledRulesUndo(
        previous: Set<String>,
        inverse: Set<String>,
        actionName: String,
        undoManager: UndoManager
    ) {
        undoManager.registerUndo(withTarget: self) { target in
            target.applyDisabledRulesSnapshot(
                previous,
                inverse: inverse,
                actionName: actionName,
                undoManager: undoManager
            )
        }
        undoManager.setActionName(actionName)
    }

    private func applyDisabledRulesSnapshot(
        _ snapshot: Set<String>,
        inverse: Set<String>,
        actionName: String,
        undoManager: UndoManager
    ) {
        do {
            disabledRules = snapshot
            try configFragmentStore.saveDisabledRules(disabledRules)
            refreshConfigArtifacts()
            registerDisabledRulesUndo(
                previous: inverse,
                inverse: snapshot,
                actionName: actionName,
                undoManager: undoManager
            )
        } catch {
            appendLog("error", "规则状态撤销/重做失败：\(error.localizedDescription)")
        }
    }

    private func ingestNewConnectionHits() {
        let providerMembers = Dictionary(uniqueKeysWithValues: providers.map { provider in
            (provider.id, Set(provider.memberNames))
        })

        for connection in connections {
            let identity = connectionHitIdentity(connection)
            guard observedConnectionHitIDs.insert(identity).inserted else { continue }

            let key = ruleHitKey(type: connection.ruleType, payload: connection.rulePayload)
            if key.isEmpty == false {
                ruleHitTotals[key, default: 0] += 1
            }

            for provider in providers {
                if provider.kind == "Rule" {
                    if connection.ruleType.caseInsensitiveCompare("RULE-SET") == .orderedSame,
                       connection.rulePayload == provider.name {
                        providerHitTotals[provider.id, default: 0] += 1
                    }
                } else if let members = providerMembers[provider.id], members.isEmpty == false {
                    let chain = connection.chain.components(separatedBy: " -> ")
                    if chain.contains(where: { members.contains($0) }) {
                        providerHitTotals[provider.id, default: 0] += 1
                    }
                }
            }
        }

        if observedConnectionHitIDs.count > 50_000 {
            observedConnectionHitIDs = Set(connections.map(connectionHitIdentity))
        }
    }

    private func connectionHitIdentity(_ connection: ConnectionItem) -> String {
        if let start = connection.start {
            return "\(connection.id)@\(start.timeIntervalSince1970)"
        }
        return connection.id
    }

    private func ruleHitKey(content: String) -> String {
        let parts = content.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.isEmpty == false else { return "" }
        if parts[0].uppercased() == "MATCH" {
            return "MATCH"
        }
        if parts.count >= 2 {
            return ruleHitKey(type: parts[0], payload: parts[1])
        }
        return parts[0].uppercased()
    }

    private func ruleHitKey(type: String, payload: String) -> String {
        let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedType.isEmpty == false else { return "" }
        return normalizedPayload.isEmpty ? normalizedType : "\(normalizedType),\(normalizedPayload)"
    }
}

private struct ProfileConfigMutationSnapshot {
    var content: String
    var disabledRules: Set<String>
}
