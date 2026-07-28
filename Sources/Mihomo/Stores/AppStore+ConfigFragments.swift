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

    @discardableResult
    func commitConfigFragments(
        _ next: [ConfigFragment],
        actionName: String,
        undoManager: UndoManager?
    ) -> Bool {
        let previous = configFragments
        if previous != next {
            captureConfigFragmentsRevision(previous, actionName: actionName)
        }
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
            return true
        } catch {
            configFragments = previous
            appendLog("error", "覆写片段保存失败：\(error.localizedDescription)")
            return false
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
}
