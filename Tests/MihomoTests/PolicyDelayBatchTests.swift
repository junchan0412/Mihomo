import Combine
import XCTest
@testable import Mihomo

@MainActor
final class PolicyDelayBatchTests: XCTestCase {
    func testApplyDelaysUpdatesEveryMatchingNodeInASinglePublish() {
        let store = AppStore()
        store.proxyGroups = [
            group(name: "Auto", nodes: ["node-a", "node-b"]),
            group(name: "Manual", nodes: ["node-a", "node-c"])
        ]
        var publishCount = 0
        let cancellable = store.objectWillChange.sink { publishCount += 1 }

        store.applyDelays(["node-a": 120, "node-c": 240])

        // One pass over all groups, one objectWillChange — not one per node and not the extra
        // emission the old `proxyGroups = proxyGroups` self-assignment produced.
        XCTAssertEqual(publishCount, 1)
        XCTAssertEqual(delay(store, group: "Auto", node: "node-a"), 120)
        XCTAssertEqual(delay(store, group: "Manual", node: "node-a"), 120)
        XCTAssertEqual(delay(store, group: "Manual", node: "node-c"), 240)
        XCTAssertNil(delay(store, group: "Auto", node: "node-b"))
        withExtendedLifetime(cancellable) {}
    }

    func testApplyDelaysSkipsPublishWhenNothingChanged() {
        let store = AppStore()
        store.proxyGroups = [group(name: "Auto", nodes: ["node-a"])]
        store.applyDelays(["node-a": 120])

        var publishCount = 0
        let cancellable = store.objectWillChange.sink { publishCount += 1 }

        store.applyDelays(["node-a": 120])
        store.applyDelays([:])
        store.applyDelays(["missing-node": 500])

        XCTAssertEqual(publishCount, 0)
        XCTAssertEqual(delay(store, group: "Auto", node: "node-a"), 120)
        withExtendedLifetime(cancellable) {}
    }

    private func group(name: String, nodes: [String]) -> ProxyGroup {
        ProxyGroup(
            name: name,
            type: "select",
            now: nodes.first ?? "",
            all: nodes.map { ProxyNode(name: $0, type: "ss", delay: nil) },
            icon: nil
        )
    }

    private func delay(_ store: AppStore, group: String, node: String) -> Int? {
        store.proxyGroups
            .first { $0.name == group }?
            .all
            .first { $0.name == node }?
            .delay
    }
}
