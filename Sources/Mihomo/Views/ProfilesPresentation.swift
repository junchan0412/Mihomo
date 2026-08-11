import Foundation

struct ProfilesPresentationSnapshot {
    let visibleProfiles: [ProfileItem]
    let selectedProfiles: [ProfileItem]
    let selectedProfile: ProfileItem?
    let tableHeight: CGFloat
    let columns: [AppKitTableColumn<ProfileItem>]

    init(
        profiles: [ProfileItem],
        selectedIDs: Set<UUID>,
        searchText: String,
        activeProfileID: UUID?
    ) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var visibleProfiles: [ProfileItem] = []
        var selectedProfiles: [ProfileItem] = []
        visibleProfiles.reserveCapacity(profiles.count)
        selectedProfiles.reserveCapacity(min(selectedIDs.count, profiles.count))

        for profile in profiles {
            if selectedIDs.contains(profile.id) {
                selectedProfiles.append(profile)
            }
            if query.isEmpty || Self.matches(profile, query: query) {
                visibleProfiles.append(profile)
            }
        }

        self.visibleProfiles = visibleProfiles
        self.selectedProfiles = selectedProfiles
        selectedProfile = selectedProfiles.count == 1 ? selectedProfiles[0] : nil
        tableHeight = Self.tableHeight(for: visibleProfiles.count)
        columns = Self.columns(activeProfileID: activeProfileID)
    }

    private static func matches(_ profile: ProfileItem, query: String) -> Bool {
        profile.name.localizedCaseInsensitiveContains(query)
            || profile.location.localizedCaseInsensitiveContains(query)
            || profile.fileName.localizedCaseInsensitiveContains(query)
    }

    private static func tableHeight(for visibleCount: Int) -> CGFloat {
        let visibleRows = max(visibleCount, 1)
        let naturalHeight = 16 + CGFloat(visibleRows) * 78
        return min(max(naturalHeight, 210), 420)
    }

    private static func columns(activeProfileID: UUID?) -> [AppKitTableColumn<ProfileItem>] {
        [
            .init(title: "状态", width: 72) { profile in
                profile.id == activeProfileID ? "启用" : "-"
            },
            .init(title: "名称", width: 180) { $0.name },
            .init(title: "类型", width: 80) { $0.source == .remote ? "远程" : "本地" },
            .init(title: "来源", width: 220) { profile in
                profile.isRemote
                    ? URLDisplayText.redactingSensitiveComponents(profile.location)
                    : profile.fileName
            },
            .init(title: "更新", width: 140) { Formatters.shortDate.string(from: $0.updatedAt) }
        ]
    }
}
