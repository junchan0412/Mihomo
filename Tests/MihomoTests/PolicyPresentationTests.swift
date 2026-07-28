import XCTest
@testable import Mihomo

final class PolicyPresentationTests: XCTestCase {
    func testPresentationPrefersLiveGroupsAndKeepsOnlyProxyProviders() {
        let live = group(name: "Live", nodes: [node(name: "Live Node", delay: 20)])
        let offline = group(name: "Offline", nodes: [node(name: "Offline Node", delay: 30)])
        let providers = [
            ProviderItem(kind: "Proxy", name: "Nodes", detail: ""),
            ProviderItem(kind: "Rule", name: "Rules", detail: "")
        ]

        let snapshot = makeSnapshot(liveGroups: [live], offlineGroups: [offline], providers: providers)

        XCTAssertEqual(snapshot.displayGroups.map(\.name), ["Live"])
        XCTAssertEqual(snapshot.visibleGroups.map(\.name), ["Live"])
        XCTAssertEqual(snapshot.proxyProviders.map(\.name), ["Nodes"])
        XCTAssertFalse(snapshot.isOffline)
    }

    func testPresentationRemovesGroupsWithoutNodesAfterAvailabilityFilter() {
        let mixed = group(
            name: "Mixed",
            nodes: [
                node(name: "Fast", delay: 80),
                node(name: "Unavailable", delay: nil, available: false)
            ]
        )
        let unavailableOnly = group(
            name: "Unavailable Only",
            nodes: [node(name: "Dead", delay: nil, available: false)]
        )
        let hidden = group(name: "Hidden", nodes: [node(name: "Secret", delay: 40)], hidden: true)

        let snapshot = makeSnapshot(
            offlineGroups: [mixed, unavailableOnly, hidden],
            hideUnavailableNodes: true
        )

        XCTAssertEqual(snapshot.visibleGroups.map(\.name), ["Mixed"])
        XCTAssertEqual(snapshot.rows(for: mixed).map(\.node.name), ["Fast"])
        XCTAssertEqual(snapshot.visibleNodeCount, 1)
        XCTAssertEqual(snapshot.selectionIDs, ["group:Mixed", "node:Mixed\u{1f}Fast"])
        XCTAssertTrue(snapshot.isOffline)
    }

    func testPresentationSortsGroupsFromCachedSelectedDelayAndNodesByDelay() {
        let slowerSelection = group(
            name: "Alpha",
            now: "Slow",
            nodes: [
                node(name: "Slow", delay: 400),
                node(name: "Fast", delay: 50)
            ]
        )
        let fasterSelection = group(
            name: "Beta",
            now: "Selected",
            nodes: [
                node(name: "Untested", delay: nil),
                node(name: "Selected", delay: 100)
            ]
        )

        let snapshot = makeSnapshot(liveGroups: [slowerSelection, fasterSelection])

        XCTAssertEqual(snapshot.visibleGroups.map(\.name), ["Beta", "Alpha"])
        XCTAssertEqual(snapshot.rows(for: slowerSelection).map(\.node.name), ["Fast", "Slow"])
    }

    func testPresentationSearchShowsMatchingNodesOrAllNodesForGroupMetadata() {
        let selectable = group(
            name: "Manual",
            nodes: [
                node(name: "Tokyo", type: "ss", delay: 50),
                node(name: "Singapore", type: "trojan", delay: 60)
            ]
        )
        let automatic = group(
            name: "Automatic",
            type: "url-test",
            nodes: [
                node(name: "One", delay: 70),
                node(name: "Two", delay: 80)
            ]
        )

        let nodeMatch = makeSnapshot(liveGroups: [selectable, automatic], searchText: "trojan")
        let metadataMatch = makeSnapshot(liveGroups: [selectable, automatic], searchText: "url-test")

        XCTAssertEqual(nodeMatch.visibleGroups.map(\.name), ["Manual"])
        XCTAssertEqual(nodeMatch.rows(for: selectable).map(\.node.name), ["Singapore"])
        XCTAssertEqual(metadataMatch.visibleGroups.map(\.name), ["Automatic"])
        XCTAssertEqual(metadataMatch.rows(for: automatic).map(\.node.name), ["One", "Two"])
    }

    private func makeSnapshot(
        liveGroups: [ProxyGroup] = [],
        offlineGroups: [ProxyGroup] = [],
        providers: [ProviderItem] = [],
        searchText: String = "",
        showHiddenGroups: Bool = false,
        hideUnavailableNodes: Bool = false,
        sortsByDelay: Bool = true,
        delayFilter: PolicyDelayFilter = .all
    ) -> PolicyPresentationSnapshot {
        PolicyPresentation.make(
            liveGroups: liveGroups,
            offlineGroups: offlineGroups,
            providers: providers,
            searchText: searchText,
            showHiddenGroups: showHiddenGroups,
            hideUnavailableNodes: hideUnavailableNodes,
            sortsByDelay: sortsByDelay,
            delayFilter: delayFilter
        )
    }

    private func group(
        name: String,
        type: String = "select",
        now: String = "",
        nodes: [ProxyNode],
        hidden: Bool = false
    ) -> ProxyGroup {
        ProxyGroup(name: name, type: type, now: now, all: nodes, icon: nil, hidden: hidden)
    }

    private func node(
        name: String,
        type: String = "ss",
        delay: Int?,
        available: Bool? = true
    ) -> ProxyNode {
        ProxyNode(name: name, type: type, delay: delay, available: available)
    }
}
