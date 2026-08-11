import XCTest
@testable import Mihomo

final class URLDisplayAndFragmentTableTests: XCTestCase {
    func testURLDisplayRemovesCredentialsQueryAndFragment() {
        let display = URLDisplayText.redactingSensitiveComponents(
            "https://user:password@example.com/profile.yaml?token=secret#section"
        )

        XCTAssertEqual(display, "https://example.com/profile.yaml")
    }

    func testURLDisplayPreservesCleanRemoteURL() {
        XCTAssertEqual(
            URLDisplayText.redactingSensitiveComponents("https://example.com/profile.yaml"),
            "https://example.com/profile.yaml"
        )
    }

    func testURLDisplayRedactsOpaqueSubscriptionTokensInPath() {
        XCTAssertEqual(
            URLDisplayText.redactingSensitiveComponents(
                "https://example.com/s/c46d351d6ef3017101ca45f33da3ce79"
            ),
            "https://example.com/s/redacted"
        )
        XCTAssertEqual(
            URLDisplayText.redactingSensitiveComponents(
                "https://example.com/link/1jFrYeyMKAdrzKbS"
            ),
            "https://example.com/link/redacted"
        )
    }

    func testURLDisplayPreservesDescriptiveRepositoryPaths() {
        XCTAssertEqual(
            URLDisplayText.redactingSensitiveComponents(
                "https://raw.githubusercontent.com/Alex0510/onskr/refs/heads/main/output/nodes.txt"
            ),
            "https://raw.githubusercontent.com/Alex0510/onskr/refs/heads/main/output/nodes.txt"
        )
    }

    func testURLDisplayDoesNotEchoInvalidRemoteSource() {
        XCTAssertEqual(
            URLDisplayText.redactingSensitiveComponents("token=secret"),
            "远程 URL（已隐藏参数）"
        )
    }

    func testNodeProviderPresentationRedactsSubscriptionParameters() {
        let provider = NodeProvider(
            name: "Remote",
            url: "https://user:password@example.com/subscribe?token=secret#section"
        )

        XCTAssertEqual(
            NodeProviderPresentation.displayURL(for: provider),
            "https://example.com/subscribe"
        )
    }

    func testFragmentColumnsUseStableSourceOrder() {
        let first = fragment(name: "First")
        let second = fragment(name: "Second")
        let columns = ConfigFragmentTablePresentation.columns(for: [first, second])

        XCTAssertEqual(columns.map(\.title), ["顺序", "状态", "名称", "类型", "来源", "范围", "更新"])
        XCTAssertEqual(columns[0].value(second), "2")
        XCTAssertEqual(columns[0].value(fragment(name: "Unknown")), "-")
    }

    func testFragmentColumnsRedactRemoteSourceAndDescribeScope() {
        let profileID = UUID()
        let remote = ConfigFragment(
            name: "Remote",
            kind: .yaml,
            enabled: true,
            content: "rules: []",
            appliesGlobally: false,
            profileIDs: [profileID],
            source: .remote,
            location: "https://example.com/override.yaml?token=secret"
        )
        let columns = ConfigFragmentTablePresentation.columns(for: [remote])

        XCTAssertEqual(columns[4].value(remote), "https://example.com/override.yaml")
        XCTAssertEqual(columns[5].value(remote), "1 个配置")
    }

    func testFragmentListPresentationFiltersAndSelectsInOneSnapshot() {
        let local = fragment(name: "Local")
        let remote = ConfigFragment(
            name: "Remote",
            kind: .javascript,
            enabled: false,
            content: "function transform(config) { return config }",
            source: .remote,
            location: "https://example.com/override.js"
        )

        let presentation = ConfigFragmentListPresentation.make(
            fragments: [local, remote],
            selectedIDs: [remote.id],
            searchText: "TRANSFORM"
        )

        XCTAssertEqual(presentation.visibleFragments.map(\.id), [remote.id])
        XCTAssertEqual(presentation.selectedFragments.map(\.id), [remote.id])
        XCTAssertEqual(presentation.selectedFragment?.id, remote.id)
        XCTAssertEqual(presentation.enableActionTitle, "启用")
        XCTAssertEqual(presentation.enableActionSystemImage, "checkmark.circle")
        XCTAssertEqual(presentation.tableHeight, 210)
        XCTAssertEqual(presentation.index(of: remote), 1)
    }

    func testFragmentListPresentationClampsHeightAndRequiresSingleSelection() {
        let fragments = (0..<12).map { fragment(name: "Fragment \($0)") }
        let presentation = ConfigFragmentListPresentation.make(
            fragments: fragments,
            selectedIDs: Set(fragments.prefix(2).map(\.id)),
            searchText: ""
        )

        XCTAssertEqual(presentation.visibleFragments.count, 12)
        XCTAssertEqual(presentation.selectedFragments.count, 2)
        XCTAssertNil(presentation.selectedFragment)
        XCTAssertEqual(presentation.enableActionTitle, "停用")
        XCTAssertEqual(presentation.tableHeight, 420)
    }

    private func fragment(name: String) -> ConfigFragment {
        ConfigFragment(name: name, kind: .yaml, enabled: true, content: "rules: []")
    }
}
