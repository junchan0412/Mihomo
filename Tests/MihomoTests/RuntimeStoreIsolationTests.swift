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
        XCTAssertEqual(activityChanges, 5)
        XCTAssertEqual(store.activityStore.totalTrafficBytes, 0)
        XCTAssertEqual(store.activityStore.uniqueTargetCount, 1)
        withExtendedLifetime([appCancellable, activityCancellable]) {}
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
