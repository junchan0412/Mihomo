import Foundation

extension AppStore {
    func revisions(kind: ConfigRevisionKind, subjectID: String) -> [ConfigRevision] {
        configRevisions.filter { $0.kind == kind && $0.subjectID == subjectID }
    }

    func revisionContent(_ revision: ConfigRevision) -> String? {
        do {
            return try configRevisionStore.readSnapshot(revision, settings: settings)
        } catch {
            appendLog("error", "读取版本快照失败：\(error.localizedDescription)")
            return nil
        }
    }

    func captureProfileRevision(_ profile: ProfileItem, content: String, actionName: String) {
        captureRevision(kind: .profile, subjectID: profile.id.uuidString, subjectName: profile.name, content: content, actionName: actionName)
    }

    func captureConfigFragmentsRevision(_ fragments: [ConfigFragment], actionName: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(fragments), let content = String(data: data, encoding: .utf8) else { return }
        captureRevision(kind: .overrides, subjectID: "all", subjectName: "全部覆写", content: content, actionName: actionName)
    }

    func restoreProfileRevision(_ revision: ConfigRevision) async -> Bool {
        guard revision.kind == .profile,
              let profileID = UUID(uuidString: revision.subjectID),
              let index = profiles.firstIndex(where: { $0.id == profileID }),
              let content = revisionContent(revision)
        else { return false }
        do {
            let profile = profiles[index]
            captureProfileRevision(profile, content: try profileStore.loadProfileContent(profile, settings: settings), actionName: "恢复前快照")
            let updated = try profileStore.saveProfileContent(profile, content: content, settings: settings)
            profiles[index] = updated
            try profileStore.saveProfiles(profiles)
            if settings.activeProfileID == updated.id { try synchronizeAppSettings(from: updated) }
            refreshConfigArtifacts()
            appendLog("info", "已恢复 \(updated.name) 的版本快照")
            return true
        } catch {
            appendLog("error", "恢复 Profile 版本失败：\(error.localizedDescription)")
            return false
        }
    }

    func restoreConfigFragmentsRevision(_ revision: ConfigRevision) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard revision.kind == .overrides,
              let content = revisionContent(revision),
              let fragments = try? decoder.decode([ConfigFragment].self, from: Data(content.utf8))
        else { return false }
        return commitConfigFragments(fragments, actionName: "恢复覆写版本", undoManager: nil)
    }

    private func captureRevision(kind: ConfigRevisionKind, subjectID: String, subjectName: String, content: String, actionName: String) {
        if let latest = revisions(kind: kind, subjectID: subjectID).first,
           (try? configRevisionStore.readSnapshot(latest, settings: settings)) == content { return }
        let revision = ConfigRevision(
            id: UUID(), kind: kind, subjectID: subjectID, subjectName: subjectName,
            actionName: actionName, createdAt: Date(), fileName: "\(UUID().uuidString).snapshot"
        )
        do {
            try configRevisionStore.writeSnapshot(content, revision: revision, settings: settings)
            let next = [revision] + configRevisions
            let retained = Array(next.prefix(80))
            for removed in next.dropFirst(80) { configRevisionStore.removeSnapshot(removed) }
            try configRevisionStore.saveIndex(retained)
            configRevisions = retained
        } catch {
            appendLog("warning", "保存版本快照失败：\(error.localizedDescription)")
        }
    }
}
