import AppKit
import Foundation

extension AppStore {
    func refreshAllRemoteSubscriptions() async {
        await refreshAllRemoteProfiles()
        await refreshAllRemoteConfigFragments()
    }

    func revealConfigFragmentStorage() {
        try? AppPaths.ensureBaseDirectories()
        if FileManager.default.fileExists(atPath: AppPaths.configFragmentsFile.path) {
            NSWorkspace.shared.activateFileViewerSelecting([AppPaths.configFragmentsFile])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDirectory])
        }
    }

    func reloadConfigFragmentsFromDisk() {
        do {
            configFragments = try configFragmentStore.loadFragments()
            refreshConfigArtifacts()
            appendLog("info", "已重新载入覆写数据")
        } catch {
            appendLog("error", "覆写数据重新载入失败：\(error.localizedDescription)")
        }
    }

    @discardableResult
    func importLocalConfigFragment(
        url: URL,
        name: String? = nil,
        kind: ConfigFragmentKind? = nil,
        undoManager: UndoManager? = nil
    ) async -> Bool {
        do {
            let fragment = try configFragmentStore.importLocalFragment(fileURL: url, name: name, kind: kind)
            let saved = commitConfigFragments(
                configFragments + [fragment],
                actionName: "导入覆写",
                undoManager: undoManager
            )
            if saved {
                configFragmentImportStatus = "已导入 \(fragment.name)"
                appendLog("info", "已导入本地覆写 \(fragment.name)")
            }
            return saved
        } catch {
            configFragmentImportStatus = error.localizedDescription
            appendLog("error", "本地覆写导入失败：\(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func importRemoteConfigFragment(
        urlString: String,
        name: String,
        kind: ConfigFragmentKind,
        undoManager: UndoManager? = nil
    ) async -> Bool {
        do {
            let fragment = try await configFragmentStore.importRemoteFragment(
                urlString: urlString,
                name: name,
                kind: kind
            )
            let saved = commitConfigFragments(
                configFragments + [fragment],
                actionName: "导入远程覆写",
                undoManager: undoManager
            )
            if saved {
                configFragmentImportStatus = "已导入 \(fragment.name)"
                appendLog("info", "已导入远程覆写 \(fragment.name)")
            }
            return saved
        } catch {
            configFragmentImportStatus = error.localizedDescription
            appendLog("error", "远程覆写导入失败：\(error.localizedDescription)")
            return false
        }
    }

    func refreshConfigFragment(_ fragment: ConfigFragment) async {
        guard fragment.isRemote else { return }
        do {
            let updated = try await configFragmentStore.refreshRemoteFragment(fragment)
            guard let index = configFragments.firstIndex(where: { $0.id == fragment.id }) else { return }
            var next = configFragments
            next[index] = updated
            if commitConfigFragments(next, actionName: "刷新覆写", undoManager: nil) {
                configFragmentRefreshStatus = "上次刷新：\(Formatters.shortDate.string(from: Date()))，成功 1/1"
                configFragmentRefreshFailureCount = 0
                appendLog("info", "已刷新覆写 \(fragment.name)")
            }
        } catch {
            configFragmentRefreshFailureCount += 1
            configFragmentRefreshStatus = "刷新失败：\(fragment.name)"
            appendLog("error", "覆写刷新失败 \(fragment.name)：\(error.localizedDescription)")
        }
    }

    func refreshAllRemoteConfigFragments() async {
        let remoteFragments = configFragments.filter(\.isRemote)
        guard remoteFragments.isEmpty == false else {
            configFragmentRefreshStatus = "没有远程覆写"
            configFragmentRefreshFailureCount = 0
            return
        }

        var next = configFragments
        var succeeded = 0
        var failed = 0
        configFragmentRefreshFailureCount = 0
        configFragmentRefreshStatus = "正在刷新 0/\(remoteFragments.count)"

        for (offset, fragment) in remoteFragments.enumerated() {
            do {
                let updated = try await configFragmentStore.refreshRemoteFragment(fragment)
                if let index = next.firstIndex(where: { $0.id == fragment.id }) {
                    next[index] = updated
                }
                succeeded += 1
            } catch {
                failed += 1
                appendLog("error", "覆写刷新失败 \(fragment.name)：\(error.localizedDescription)")
            }
            configFragmentRefreshStatus = "正在刷新 \(offset + 1)/\(remoteFragments.count)，成功 \(succeeded)，失败 \(failed)"
        }

        if succeeded > 0 {
            _ = commitConfigFragments(next, actionName: "刷新远程覆写", undoManager: nil)
        }
        configFragmentRefreshFailureCount = failed
        configFragmentRefreshStatus = "上次刷新：\(Formatters.shortDate.string(from: Date()))，成功 \(succeeded)/\(remoteFragments.count)，失败 \(failed)"
    }

    func setConfigFragments(_ fragments: [ConfigFragment], enabled: Bool, undoManager: UndoManager? = nil) {
        let identifiers = Set(fragments.map(\.id))
        guard identifiers.isEmpty == false else { return }
        let now = Date()
        let next = configFragments.map { fragment -> ConfigFragment in
            guard identifiers.contains(fragment.id) else { return fragment }
            var updated = fragment
            updated.enabled = enabled
            updated.updatedAt = now
            return updated
        }
        commitConfigFragments(
            next,
            actionName: enabled ? "启用覆写" : "停用覆写",
            undoManager: undoManager
        )
    }

    func moveConfigFragment(_ fragment: ConfigFragment, offset: Int, undoManager: UndoManager? = nil) {
        guard let index = configFragments.firstIndex(where: { $0.id == fragment.id }) else { return }
        let destination = index + offset
        guard configFragments.indices.contains(destination) else { return }
        var next = configFragments
        next.swapAt(index, destination)
        commitConfigFragments(next, actionName: offset < 0 ? "上移覆写" : "下移覆写", undoManager: undoManager)
    }
}
