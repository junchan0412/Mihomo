import Foundation

extension AppStore {
    func refreshConfigFragments(_ fragments: [ConfigFragment]) async {
        guard beginConfigFragmentRefresh() else { return }
        defer { isConfigFragmentRefreshInProgress = false }

        let remoteFragments = fragments.filter(\.isRemote)
        guard remoteFragments.isEmpty == false else {
            configFragmentRefreshStatus = "没有远程覆写"
            configFragmentRefreshFailureCount = 0
            return
        }

        let maxConcurrent = max(1, min(settings.profileRefreshMaxConcurrent, 12))
        configFragmentRefreshFailureCount = 0
        configFragmentRefreshStatus = "正在刷新 0/\(remoteFragments.count)（并发 \(maxConcurrent)）"
        let results = await BoundedConcurrentWork.map(remoteFragments, maxConcurrent: maxConcurrent) { fragment in
            await Self.refreshResult(for: fragment)
        }

        var updatedByID: [UUID: ConfigFragment] = [:]
        var succeeded = 0
        var failed = 0
        for result in results {
            if let updated = result.updated {
                updatedByID[updated.id] = updated
                succeeded += 1
            } else {
                failed += 1
                appendLog("error", "覆写刷新失败 \(result.fragment.name)：\(result.errorMessage ?? "未知错误")")
            }
        }

        if updatedByID.isEmpty == false {
            let next = configFragments.map { updatedByID[$0.id] ?? $0 }
            _ = commitConfigFragments(next, actionName: "刷新远程覆写", undoManager: nil)
        }
        configFragmentRefreshFailureCount = failed
        configFragmentRefreshStatus = "上次刷新：\(Formatters.shortDate.string(from: Date()))，成功 \(succeeded)/\(remoteFragments.count)，失败 \(failed)"
    }

    func refreshAllRemoteConfigFragments() async {
        await refreshConfigFragments(configFragments)
    }

    private func beginConfigFragmentRefresh() -> Bool {
        guard isConfigFragmentRefreshInProgress == false else {
            appendLog("warning", "覆写刷新正在进行，已忽略重复请求")
            return false
        }
        isConfigFragmentRefreshInProgress = true
        return true
    }

    nonisolated private static func refreshResult(
        for fragment: ConfigFragment
    ) async -> ConfigFragmentRefreshResult {
        do {
            let updated = try await ConfigFragmentStore().refreshRemoteFragment(fragment)
            return ConfigFragmentRefreshResult(fragment: fragment, updated: updated)
        } catch {
            return ConfigFragmentRefreshResult(
                fragment: fragment,
                errorMessage: error.localizedDescription
            )
        }
    }
}

private struct ConfigFragmentRefreshResult: Sendable {
    var fragment: ConfigFragment
    var updated: ConfigFragment? = nil
    var errorMessage: String? = nil
}
