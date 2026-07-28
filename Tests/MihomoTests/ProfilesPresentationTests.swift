import XCTest
@testable import Mihomo

final class ProfilesPresentationTests: XCTestCase {
    func testSnapshotDerivesFilteringAndSelectionInStableProfileOrder() {
        let local = profile(name: "Local", location: "/profiles/local.yaml")
        let remote = profile(
            name: "Remote",
            source: .remote,
            location: "https://example.com/subscription?token=secret"
        )
        let selectedIDs = Set([remote.id])

        let snapshot = ProfilesPresentationSnapshot(
            profiles: [local, remote],
            selectedIDs: selectedIDs,
            searchText: "subscription",
            activeProfileID: local.id
        )

        XCTAssertEqual(snapshot.visibleProfiles.map(\.id), [remote.id])
        XCTAssertEqual(snapshot.selectedProfiles.map(\.id), [remote.id])
        XCTAssertEqual(snapshot.selectedProfile?.id, remote.id)
        XCTAssertEqual(snapshot.tableHeight, 176)
        XCTAssertEqual(snapshot.columns[0].value(local), "启用")
        XCTAssertEqual(snapshot.columns[0].value(remote), "-")
        XCTAssertEqual(snapshot.columns[3].value(remote), "https://example.com/subscription")
    }

    func testSnapshotHandlesMultipleSelectionAndBoundsTableHeight() {
        let profiles = (0..<12).map { index in
            profile(name: "Profile \(index)", location: "/profiles/\(index).yaml")
        }
        let selectedIDs = Set(profiles.prefix(2).map(\.id))

        let snapshot = ProfilesPresentationSnapshot(
            profiles: profiles,
            selectedIDs: selectedIDs,
            searchText: "",
            activeProfileID: nil
        )

        XCTAssertEqual(snapshot.visibleProfiles.map(\.id), profiles.map(\.id))
        XCTAssertEqual(snapshot.selectedProfiles.map(\.id), profiles.prefix(2).map(\.id))
        XCTAssertNil(snapshot.selectedProfile)
        XCTAssertEqual(snapshot.tableHeight, 280)
    }

    private func profile(
        name: String,
        source: ProfileSource = .local,
        location: String
    ) -> ProfileItem {
        ProfileItem(
            id: UUID(),
            name: name,
            source: source,
            location: location,
            fileName: "\(name).yaml",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
