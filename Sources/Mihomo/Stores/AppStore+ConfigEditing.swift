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

    func toggleRuleDisabled(_ rule: RuleItem) {
        if disabledRules.contains(rule.content) {
            disabledRules.remove(rule.content)
        } else {
            disabledRules.insert(rule.content)
        }
        do {
            try configFragmentStore.saveDisabledRules(disabledRules)
            refreshConfigArtifacts()
            appendLog("info", disabledRules.contains(rule.content) ? "已禁用规则 \(rule.index)" : "已启用规则 \(rule.index)")
        } catch {
            appendLog("error", "保存禁用规则失败：\(error.localizedDescription)")
        }
    }

    func upsertActiveProfileRule(originalIndex: Int?, rule: EditableProfileRule) async {
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
            let updatedProfile = try profileStore.saveProfileContent(activeProfile, content: updatedContent, settings: settings)
            profiles[profileIndex] = updatedProfile
            try profileStore.saveProfiles(profiles)
            refreshConfigArtifacts()
            appendLog("info", originalIndex == nil ? "已添加规则" : "已保存规则 \(originalIndex ?? rule.index)")
        } catch {
            appendLog("error", "规则保存失败：\(error.localizedDescription)")
        }
    }

    func deleteActiveProfileRule(index: Int) async {
        guard let activeProfile,
              let profileIndex = profiles.firstIndex(where: { $0.id == activeProfile.id })
        else {
            appendLog("error", "没有可编辑的当前配置")
            return
        }

        do {
            let removedRule = rules.first { $0.index == index }
            let content = try profileStore.loadProfileContent(activeProfile, settings: settings)
            let updatedContent = try ProfileYAMLStructureEditor().deleteRule(content: content, index: index)
            let updatedProfile = try profileStore.saveProfileContent(activeProfile, content: updatedContent, settings: settings)
            profiles[profileIndex] = updatedProfile
            if let removedRule, disabledRules.remove(removedRule.content) != nil {
                try configFragmentStore.saveDisabledRules(disabledRules)
            }
            try profileStore.saveProfiles(profiles)
            refreshConfigArtifacts()
            appendLog("info", "已删除规则 \(index)")
        } catch {
            appendLog("error", "规则删除失败：\(error.localizedDescription)")
        }
    }

    func resetRuleHitStatistics() {
        ruleHitBaselines = currentRuleHitCounts()
        updateRuleProviderHitStatistics()
        appendLog("info", "规则使用计数已重置")
    }

    func addConfigFragment(name: String, kind: ConfigFragmentKind, content: String) {
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
        configFragments.append(fragment)
        saveConfigFragments()
    }

    func updateConfigFragment(_ fragment: ConfigFragment) {
        guard let index = configFragments.firstIndex(where: { $0.id == fragment.id }) else { return }
        var updated = fragment
        updated.updatedAt = Date()
        configFragments[index] = updated
        saveConfigFragments()
    }

    func deleteConfigFragment(_ fragment: ConfigFragment) {
        configFragments.removeAll { $0.id == fragment.id }
        saveConfigFragments()
    }

    func updateRuleProviderHitStatistics() {
        let ruleHits = currentRuleHitCounts()

        let updatedRules = rules.map { rule in
            var updated = rule
            let key = ruleHitKey(content: rule.content)
            let resetBaseline = ruleHitBaselines[key, default: 0]
            updated.hitCount = max(0, ruleHits[key, default: 0] - resetBaseline)
            return updated
        }
        publishIfChanged(\.rules, updatedRules)

        let ruleProviderHits = connections.reduce(into: [String: Int]()) { result, connection in
            guard connection.ruleType.uppercased() == "RULE-SET",
                  connection.rulePayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            else { return }
            result[connection.rulePayload, default: 0] += 1
        }

        let updatedProviders = providers.map { provider in
            var updated = provider
            if provider.kind == "Rule" {
                updated.hitCount = ruleProviderHits[provider.name, default: 0]
            } else if provider.memberNames.isEmpty == false {
                let members = Set(provider.memberNames)
                updated.hitCount = connections.filter { connection in
                    connection.chain
                        .components(separatedBy: " -> ")
                        .contains { members.contains($0) }
                }.count
            }
            return updated
        }
        publishIfChanged(\.providers, updatedProviders)
    }

    private func saveConfigFragments() {
        do {
            try configFragmentStore.saveFragments(configFragments)
            refreshConfigArtifacts()
            appendLog("info", "覆写片段已保存")
        } catch {
            appendLog("error", "覆写片段保存失败：\(error.localizedDescription)")
        }
    }

    private func currentRuleHitCounts() -> [String: Int] {
        connections.reduce(into: [String: Int]()) { result, connection in
            let key = ruleHitKey(type: connection.ruleType, payload: connection.rulePayload)
            guard key.isEmpty == false else { return }
            result[key, default: 0] += 1
        }
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
