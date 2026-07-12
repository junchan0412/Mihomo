import Combine
import XCTest
@testable import Mihomo

@MainActor
final class RuntimeStoreIsolationTests: XCTestCase {
    func testHighFrequencyActivityDoesNotInvalidateAppStore() {
        let store = AppStore()
        var appChanges = 0
        var activityChanges = 0
        let appCancellable = store.objectWillChange.sink { appChanges += 1 }
        let activityCancellable = store.activityStore.objectWillChange.sink { activityChanges += 1 }

        store.connections = [connection(id: "c1")]
        store.uploadRate = 128
        store.downloadRate = 256
        store.trafficSamples = [TrafficSample(uploadRate: 128, downloadRate: 256)]
        store.controllerEventStreamStatus = "实时"

        XCTAssertEqual(appChanges, 0)
        XCTAssertGreaterThanOrEqual(activityChanges, 5)
        XCTAssertEqual(store.activityStore.totalTrafficBytes, 0)
        XCTAssertEqual(store.activityStore.uniqueTargetCount, 1)
        XCTAssertEqual(store.activityStore.recentConnections.map(\.id), ["c1"])
        withExtendedLifetime([appCancellable, activityCancellable]) {}
    }

    func testRecentConnectionsCanBeClearedWithoutClosingActiveConnections() {
        let store = RuntimeActivityStore()
        store.replaceConnections([connection(id: "active")])

        store.clearRecentConnections()

        XCTAssertTrue(store.recentConnections.isEmpty)
        XCTAssertEqual(store.connections.map(\.id), ["active"])
    }

    func testLogPublishingDoesNotInvalidateAppStore() {
        let store = AppStore()
        var appChanges = 0
        var logChanges = 0
        let appCancellable = store.objectWillChange.sink { appChanges += 1 }
        let logCancellable = store.logStore.objectWillChange.sink { logChanges += 1 }

        store.logs = [LogEntry(level: "info", message: "ready")]
        store.logsPaused = true
        store.bufferedLogCount = 1

        XCTAssertEqual(appChanges, 0)
        XCTAssertEqual(logChanges, 3)
        withExtendedLifetime([appCancellable, logCancellable]) {}
    }

    func testRuleHitCountingIsStableAcrossRefreshAndReset() {
        let store = AppStore()
        store.rules = [RuleItem(index: 0, content: "DOMAIN,example.com,DIRECT", disabled: false)]
        var first = connection(id: "connection-1")
        first.ruleType = "DOMAIN"
        first.rulePayload = "example.com"
        first.start = Date(timeIntervalSince1970: 100)
        store.connections = [first]

        store.updateRuleProviderHitStatistics()
        store.updateRuleProviderHitStatistics()
        XCTAssertEqual(store.rules.first?.hitCount, 1, "重复刷新不得重复统计同一连接")

        var second = connection(id: "connection-2")
        second.ruleType = "DOMAIN"
        second.rulePayload = "example.com"
        second.start = Date(timeIntervalSince1970: 101)
        store.connections = [first, second]
        store.updateRuleProviderHitStatistics()
        XCTAssertEqual(store.rules.first?.hitCount, 2, "新连接应继续累加")

        store.resetRuleHitStatistics()
        XCTAssertEqual(store.rules.first?.hitCount, 0, "重置后显示计数应归零")

        var third = connection(id: "connection-3")
        third.ruleType = "DOMAIN"
        third.rulePayload = "example.com"
        third.start = Date(timeIntervalSince1970: 102)
        store.connections = [first, second, third]
        store.updateRuleProviderHitStatistics()
        XCTAssertEqual(store.rules.first?.hitCount, 1, "重置后的新连接应从零继续累加")
    }

    private func connection(id: String) -> ConnectionItem {
        ConnectionItem(
            id: id,
            host: "example.com",
            process: "Safari",
            network: "tcp",
            rule: "MATCH",
            chain: "DIRECT",
            upload: 0,
            download: 0
        )
    }
}
