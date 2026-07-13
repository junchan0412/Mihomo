import Foundation

extension AppStore {
    func synchronizeAppSettings(from profile: ProfileItem, persistSettings: Bool = true) throws {
        let content = try profileStore.loadProfileContent(profile, settings: settings)
        var synchronized = try profileSettingsSynchronizer.applyingProfile(content, to: settings)
        synchronized.activeProfileID = profile.id
        synchronized.snifferManagedByApp = true
        settings = synchronized
        if persistSettings {
            try profileStore.saveSettings(synchronized)
        }
    }

    func synchronizeActiveProfileSettings(
        from previous: AppSettings,
        to updated: AppSettings,
        persistProfileList: Bool = true
    ) throws -> Bool {
        guard let activeProfile,
              let profileIndex = profiles.firstIndex(where: { $0.id == activeProfile.id })
        else { return false }

        let content = try profileStore.loadProfileContent(activeProfile, settings: previous)
        let synchronized = try profileSettingsSynchronizer.syncingAppChanges(
            from: previous,
            to: updated,
            in: content
        )
        guard synchronized != content else { return false }

        profiles[profileIndex] = try profileStore.saveProfileContent(
            activeProfile,
            content: synchronized,
            settings: previous
        )
        if persistProfileList {
            try profileStore.saveProfiles(profiles)
        }
        return true
    }
}
