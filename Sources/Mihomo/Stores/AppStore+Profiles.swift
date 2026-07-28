import AppKit
import Foundation

extension AppStore {
    func revealProfileStorageDirectory() {
        let directory = profileStorageDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func changeProfileStorageDirectory(to directory: URL) async {
        do {
            let oldSettings = settings
            try profileStore.migrateProfileStorage(profiles: profiles, from: oldSettings, to: directory)
            var updated = settings
            updated.profileStoragePath = directory.standardizedFileURL.path
            settings = updated
            try profileStore.saveSettings(updated)
            refreshConfigArtifacts()
            appendLog("info", "配置存储路径已切换：\(updated.profileStoragePath)")
        } catch {
            appendLog("error", "配置存储路径切换失败：\(error.localizedDescription)")
        }
    }

    func addRemoteProfile() async {
        let url = newRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        do {
            let item = try await profileStore.importRemoteProfile(
                urlString: url,
                name: newRemoteName.trimmingCharacters(in: .whitespacesAndNewlines),
                settings: settings
            )
            profiles.append(item)
            try profileStore.saveProfiles(profiles)
            try importNodeProviders(from: [item])
            try synchronizeAppSettings(from: item)
            newRemoteURL = ""
            newRemoteName = ""
            refreshConfigArtifacts()
            appendLog("info", "已导入远程订阅 \(item.name)")
        } catch {
            appendLog("error", "远程订阅导入失败：\(error.localizedDescription)")
        }
    }

    func importLocalProfile(url: URL) async {
        do {
            let item = try profileStore.importLocalProfile(fileURL: url, settings: settings)
            profiles.append(item)
            try profileStore.saveProfiles(profiles)
            try importNodeProviders(from: [item])
            try synchronizeAppSettings(from: item)
            refreshConfigArtifacts()
            appendLog("info", "已导入本地配置 \(item.name)")
        } catch {
            appendLog("error", "本地配置导入失败：\(error.localizedDescription)")
        }
    }

    func setActiveProfile(_ profile: ProfileItem) async {
        do {
            try synchronizeAppSettings(from: profile)
            refreshConfigArtifacts()
            appendLog("info", "已启用配置 \(profile.name)，配置参数已同步到 App")
            if isCoreRunning {
                await restartCore()
            }
        } catch {
            appendLog("error", "配置切换失败：\(error.localizedDescription)")
        }
    }

    func profileContent(for profile: ProfileItem) -> String {
        do {
            return try profileStore.loadProfileContent(profile, settings: settings)
        } catch {
            appendLog("error", "读取配置失败：\(error.localizedDescription)")
            return ""
        }
    }

    func saveProfileEditor(
        profileID: UUID,
        name: String,
        content: String,
        undoManager: UndoManager? = nil
    ) async {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        do {
            var profile = profiles[index]
            let before = ProfileEditorSnapshot(
                name: profile.name,
                content: try profileStore.loadProfileContent(profile, settings: settings)
            )
            captureProfileRevision(profile, content: before.content, actionName: "编辑配置")
            profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? profile.name : name
            let updated = try profileStore.saveProfileContent(profile, content: content, settings: settings)
            profiles[index] = updated
            try profileStore.saveProfiles(profiles)
            if settings.activeProfileID == updated.id {
                try synchronizeAppSettings(from: updated)
            }
            refreshConfigArtifacts()
            appendLog("info", "已保存配置 \(updated.name)")
            if let undoManager {
                registerProfileEditorUndo(
                    profileID: profileID,
                    snapshot: before,
                    inverse: ProfileEditorSnapshot(name: updated.name, content: content),
                    undoManager: undoManager
                )
            }
        } catch {
            appendLog("error", "保存配置失败：\(error.localizedDescription)")
        }
    }

    private func registerProfileEditorUndo(
        profileID: UUID,
        snapshot: ProfileEditorSnapshot,
        inverse: ProfileEditorSnapshot,
        undoManager: UndoManager
    ) {
        undoManager.registerUndo(withTarget: self) { target in
            Task {
                await target.applyProfileEditorSnapshot(
                    profileID: profileID,
                    snapshot: snapshot,
                    inverse: inverse,
                    undoManager: undoManager
                )
            }
        }
        undoManager.setActionName("编辑配置")
    }

    private func applyProfileEditorSnapshot(
        profileID: UUID,
        snapshot: ProfileEditorSnapshot,
        inverse: ProfileEditorSnapshot,
        undoManager: UndoManager
    ) async {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        do {
            var profile = profiles[index]
            profile.name = snapshot.name
            let updated = try profileStore.saveProfileContent(profile, content: snapshot.content, settings: settings)
            profiles[index] = updated
            try profileStore.saveProfiles(profiles)
            if settings.activeProfileID == updated.id {
                try synchronizeAppSettings(from: updated)
            }
            refreshConfigArtifacts()
            registerProfileEditorUndo(
                profileID: profileID,
                snapshot: inverse,
                inverse: snapshot,
                undoManager: undoManager
            )
            appendLog("info", "已执行配置编辑撤销/重做")
        } catch {
            appendLog("error", "配置编辑撤销/重做失败：\(error.localizedDescription)")
        }
    }

    func deleteProfiles(_ profilesToDelete: [ProfileItem], undoManager: UndoManager? = nil) async {
        let identifiers = Set(profilesToDelete.map(\.id))
        guard identifiers.isEmpty == false, profiles.count - identifiers.count >= 1 else { return }

        do {
            let snapshots = try profiles.enumerated().compactMap { index, profile -> DeletedProfileSnapshot? in
                guard identifiers.contains(profile.id) else { return nil }
                return DeletedProfileSnapshot(
                    profile: profile,
                    content: try profileStore.loadProfileContent(profile, settings: settings),
                    index: index,
                    wasActive: settings.activeProfileID == profile.id
                )
            }

            for snapshot in snapshots {
                let file = profileStore.profileFile(snapshot.profile, settings: settings)
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.removeItem(at: file)
                }
            }

            profiles.removeAll { identifiers.contains($0.id) }
            if let activeProfileID = settings.activeProfileID, identifiers.contains(activeProfileID) {
                settings.activeProfileID = profiles.first?.id
                try profileStore.saveSettings(settings)
            }
            try profileStore.saveProfiles(profiles)
            refreshConfigArtifacts()
            appendLog("info", "已删除 \(snapshots.count) 个配置")

            if let undoManager {
                undoManager.registerUndo(withTarget: self) { target in
                    Task { await target.restoreDeletedProfiles(snapshots, undoManager: undoManager) }
                }
                undoManager.setActionName(snapshots.count == 1 ? "删除配置" : "删除多个配置")
            }
        } catch {
            appendLog("error", "删除配置失败：\(error.localizedDescription)")
        }
    }

    private func restoreDeletedProfiles(_ snapshots: [DeletedProfileSnapshot], undoManager: UndoManager?) async {
        do {
            for snapshot in snapshots.sorted(by: { $0.index < $1.index }) {
                let restored = try profileStore.saveProfileContent(
                    snapshot.profile,
                    content: snapshot.content,
                    settings: settings
                )
                let insertionIndex = min(snapshot.index, profiles.count)
                profiles.insert(restored, at: insertionIndex)
                if snapshot.wasActive {
                    settings.activeProfileID = restored.id
                }
            }
            try profileStore.saveProfiles(profiles)
            try profileStore.saveSettings(settings)
            refreshConfigArtifacts()
            appendLog("info", "已撤销删除 \(snapshots.count) 个配置")

            if let undoManager {
                let restoredProfiles = snapshots.compactMap { snapshot in
                    profiles.first { $0.id == snapshot.profile.id }
                }
                undoManager.registerUndo(withTarget: self) { target in
                    Task { await target.deleteProfiles(restoredProfiles, undoManager: undoManager) }
                }
                undoManager.setActionName(snapshots.count == 1 ? "重新删除配置" : "重新删除多个配置")
            }
        } catch {
            appendLog("error", "恢复配置失败：\(error.localizedDescription)")
        }
    }

}

private struct DeletedProfileSnapshot {
    var profile: ProfileItem
    var content: String
    var index: Int
    var wasActive: Bool
}

private struct ProfileEditorSnapshot {
    var name: String
    var content: String
}

struct ProfileStatsFingerprint: Hashable {
    var fileName: String
    var location: String
    var updatedAt: Date
    var profileStoragePath: String
}

struct ProfileQualityFingerprint: Hashable {
    var profile: ProfileStatsFingerprint
    var settings: AppSettings
    var fragments: [ConfigFragment]
    var disabledRules: Set<String>
    var nodeProviders: [NodeProvider]
    var migrationLog: [String]
}

struct ProfileStatsCacheEntry {
    var fingerprint: ProfileStatsFingerprint
    var stats: ProfileStats
}

struct ProfileQualityCacheEntry {
    var fingerprint: ProfileQualityFingerprint
    var report: ProfileQualityReport
}
