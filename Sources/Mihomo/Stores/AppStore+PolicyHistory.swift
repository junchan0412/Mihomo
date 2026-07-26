import Foundation

extension AppStore {
    func delayHistory(for group: ProxyGroup, limit: Int = 8) -> [PolicyDelayHistoryEntry] {
        let proxyNames = Set(group.all.map(\.name))
        return policyDelayHistory
            .filter { proxyNames.contains($0.proxyName) }
            .prefix(max(1, limit))
            .map { $0 }
    }

    func latestDelayHistory(for proxyName: String) -> PolicyDelayHistoryEntry? {
        policyDelayHistory.first { $0.proxyName == proxyName }
    }

    func recordDelayResult(proxyName: String, delay: Int?, failureReason: String? = nil, skippedReason: String? = nil) {
        let groups = proxyGroups
            .filter { $0.all.contains(where: { $0.name == proxyName }) }
            .map(\.name)
        let entry = PolicyDelayHistoryEntry(
            proxyName: proxyName,
            groupNames: groups,
            delay: delay,
            failureReason: failureReason,
            skippedReason: skippedReason
        )
        policyDelayHistory.insert(entry, at: 0)
        policyDelayHistory = Array(policyDelayHistory.prefix(240))
        persistPolicyInteractionHistory()
    }

    func recordProxySelection(groupName: String, proxyName: String) {
        recentProxySelections.removeAll { $0.groupName == groupName && $0.proxyName == proxyName }
        recentProxySelections.insert(RecentProxySelection(groupName: groupName, proxyName: proxyName), at: 0)
        recentProxySelections = Array(recentProxySelections.prefix(12))
        persistPolicyInteractionHistory()
    }

    func toggleFavoritePolicyGroup(_ groupName: String) {
        if favoritePolicyGroupNames.contains(groupName) {
            favoritePolicyGroupNames.remove(groupName)
        } else {
            favoritePolicyGroupNames.insert(groupName)
        }
        persistPolicyInteractionHistory()
    }

    func loadPolicyInteractionHistory() {
        guard let data = try? Data(contentsOf: AppPaths.policyInteractionHistoryFile),
              let history = try? JSONDecoder().decode(PolicyInteractionHistory.self, from: data)
        else { return }
        policyDelayHistory = history.delayEntries.sorted { $0.recordedAt > $1.recordedAt }
        recentProxySelections = history.recentSelections.sorted { $0.selectedAt > $1.selectedAt }
        favoritePolicyGroupNames = Set(history.favoriteGroupNames)
    }

    private func persistPolicyInteractionHistory() {
        let history = PolicyInteractionHistory(
            delayEntries: policyDelayHistory,
            recentSelections: recentProxySelections,
            favoriteGroupNames: favoritePolicyGroupNames.sorted()
        )
        do {
            try AppPaths.ensureBaseDirectories()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(history).write(to: AppPaths.policyInteractionHistoryFile, options: .atomic)
        } catch {
            appendLog("warning", "保存策略交互历史失败：\(error.localizedDescription)")
        }
    }
}
