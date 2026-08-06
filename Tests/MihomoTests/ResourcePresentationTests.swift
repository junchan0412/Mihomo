import Foundation
import XCTest
@testable import Mihomo

final class ResourcePresentationTests: XCTestCase {
    func testResourceEmptyStateDistinguishesSearchFilterAndMissingData() {
        let search = ResourceEmptyState(searchText: " provider ", showsOnlyUnready: false)
        XCTAssertEqual(search.title, "没有匹配的资源")
        XCTAssertEqual(search.systemImage, "magnifyingglass")
        XCTAssertEqual(search.description, "请尝试其他搜索词。")

        let filtered = ResourceEmptyState(searchText: "", showsOnlyUnready: true)
        XCTAssertEqual(filtered.title, "没有未就绪资源")
        XCTAssertEqual(filtered.systemImage, "shippingbox")
        XCTAssertEqual(filtered.description, "当前本地与远程资源均已就绪。")

        let missing = ResourceEmptyState(searchText: "", showsOnlyUnready: false)
        XCTAssertEqual(missing.title, "没有外部资源")
        XCTAssertEqual(missing.systemImage, "shippingbox")
        XCTAssertEqual(missing.description, "当前配置没有声明 Provider 或本地规则集。")
    }

    func testPresentationBuildsCountsFilterAndSelectionFromOneSnapshot() {
        let ready = provider(kind: "Proxy", name: "Ready", remoteURL: "https://example.com/ready")
        let pending = provider(kind: "Rule", name: "Beta", remoteURL: "https://example.com/beta")
        let missing = provider(kind: "Rule", name: "Missing", path: "/definitely-missing/mihomo-rule.yaml")
        let record = ProviderUpdateRecord(
            providerName: ready.name,
            providerKind: ready.kind,
            action: "下载",
            succeeded: true,
            targetPath: "/tmp/ready.yaml",
            message: "完成"
        )
        let latestRecords = [historyKey(for: ready): record]

        let presentation = ResourceTablePresentation.make(
            providers: [ready, pending, missing],
            latestRecords: latestRecords,
            historyKey: historyKey(for:),
            searchText: "beta",
            showsOnlyUnready: false
        )

        XCTAssertEqual(presentation.proxyCount, 1)
        XCTAssertEqual(presentation.ruleCount, 2)
        XCTAssertEqual(presentation.unreadyCount, 2)
        XCTAssertEqual(presentation.refreshableCount, 3)
        XCTAssertEqual(presentation.visibleRows.map(\.id), [pending.id])
        XCTAssertEqual(
            presentation.selectedRows(for: [ready.id, missing.id]).map(\.id),
            [ready.id, missing.id]
        )
        XCTAssertEqual(presentation.selectedRow(for: [pending.id])?.id, pending.id)
    }

    func testExternalResourceRowCachesFileExistenceForSnapshotLifetime() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mihomo-resource-\(UUID().uuidString).yaml")
        try Data("rules: []".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let local = provider(kind: "Rule", name: "Local", path: fileURL.path)
        let snapshotRow = ExternalResourceRow(provider: local, latestRecord: nil)

        XCTAssertTrue(snapshotRow.isReady)
        try FileManager.default.removeItem(at: fileURL)
        XCTAssertTrue(snapshotRow.isReady)
        XCTAssertFalse(ExternalResourceRow(provider: local, latestRecord: nil).isReady)
    }

    func testRuleWorkspaceFiltersConfigurationResourcesByProviderKind() {
        let proxy = provider(kind: "Proxy", name: "Nodes", remoteURL: "https://example.com/nodes")
        let rule = provider(kind: "Rule", name: "Rules", remoteURL: "https://example.com/rules")

        let presentation = ResourceTablePresentation.make(
            providers: [proxy, rule],
            latestRecords: [:],
            historyKey: historyKey(for:),
            searchText: "",
            showsOnlyUnready: false,
            kindFilter: "Rule"
        )

        XCTAssertEqual(presentation.allRows.map(\.provider.kind), ["Rule"])
        XCTAssertEqual(presentation.proxyCount, 0)
        XCTAssertEqual(presentation.ruleCount, 1)
    }

    func testResourceWorkspaceOrderMatchesResourceCategories() {
        XCTAssertEqual(
            ResourceWorkspace.allCases,
            [.configResources, .nodeProviders, .rules]
        )
        XCTAssertEqual(ResourceWorkspace.configResources.title, "配置资源")
        XCTAssertEqual(ResourceWorkspace.nodeProviders.title, "节点提供商")
        XCTAssertEqual(ResourceWorkspace.rules.title, "规则")
    }

    private func provider(
        kind: String,
        name: String,
        remoteURL: String? = nil,
        path: String? = nil
    ) -> ProviderItem {
        ProviderItem(
            kind: kind,
            name: name,
            detail: name,
            remoteURL: remoteURL,
            path: path
        )
    }

    private func historyKey(for provider: ProviderItem) -> String {
        "\(provider.kind.lowercased())\u{1F}\(provider.name.lowercased())"
    }
}
