import XCTest
@testable import Mihomo

@MainActor
final class RuntimeActivityStoreTests: XCTestCase {
    func testTrafficUpdateThrottlesIdenticalSamplesWithinInterval() {
        let store = RuntimeActivityStore()

        store.updateTraffic(uploadRate: 1024, downloadRate: 2048, sampleInterval: 1.0)
        store.updateTraffic(uploadRate: 1024, downloadRate: 2048, sampleInterval: 1.0)
        store.updateTraffic(uploadRate: 1024, downloadRate: 2048, sampleInterval: 1.0)

        XCTAssertEqual(store.uploadRate, 1024)
        XCTAssertEqual(store.downloadRate, 2048)
        XCTAssertEqual(store.trafficSamples.count, 1)
    }

    func testTrafficUpdateKeepsLatestSampleWhenRateChanges() {
        let store = RuntimeActivityStore()

        store.updateTraffic(uploadRate: 100, downloadRate: 200, sampleInterval: 1.0)
        store.updateTraffic(uploadRate: 300, downloadRate: 400, sampleInterval: 1.0)

        XCTAssertEqual(store.uploadRate, 300)
        XCTAssertEqual(store.downloadRate, 400)
        XCTAssertEqual(store.trafficSamples.count, 2)
        XCTAssertEqual(store.trafficSamples.last?.uploadRate, 300)
        XCTAssertEqual(store.trafficSamples.last?.downloadRate, 400)
    }

    func testReplaceConnectionsSkipsUnchangedSnapshot() {
        let store = RuntimeActivityStore()
        let item = ConnectionItem(
            id: "1",
            host: "example.com",
            process: "Safari",
            network: "tcp",
            rule: "MATCH",
            chain: "DIRECT",
            upload: 10,
            download: 20
        )

        store.replaceConnections([item])
        store.replaceConnections([item])

        XCTAssertEqual(store.connections.count, 1)
        XCTAssertEqual(store.uniqueTargetCount, 1)
        XCTAssertEqual(store.totalDownloadBytes, 20)
    }

    func testReplaceConnectionsThrottlesByteOnlyUpdates() {
        let store = RuntimeActivityStore()
        let first = ConnectionItem(
            id: "1",
            host: "example.com",
            process: "Safari",
            network: "tcp",
            rule: "MATCH",
            chain: "DIRECT",
            upload: 10,
            download: 20
        )
        let second = ConnectionItem(
            id: "1",
            host: "example.com",
            process: "Safari",
            network: "tcp",
            rule: "MATCH",
            chain: "DIRECT",
            upload: 30,
            download: 40
        )

        store.replaceConnections([first])
        store.replaceConnections([second])

        XCTAssertEqual(store.connections.first?.upload, 10)
        XCTAssertEqual(store.totalUploadBytes, 30)
        XCTAssertEqual(store.totalDownloadBytes, 40)
        XCTAssertFalse(store.connectionStructureChanged(from: [first], to: [second]))
        XCTAssertTrue(store.connectionStructureChanged(from: [first], to: [
            ConnectionItem(
                id: "2",
                host: "example.com",
                process: "Safari",
                network: "tcp",
                rule: "MATCH",
                chain: "PROXY",
                upload: 0,
                download: 0
            )
        ]))
    }
}

@MainActor
final class RuntimeActivityStoreActiveSetTests: XCTestCase {
    func testActiveConnectionLookupIsO1SetBased() {
        let store = RuntimeActivityStore()
        let item = ConnectionItem(
            id: "abc",
            host: "example.com",
            process: "Safari",
            network: "tcp",
            rule: "MATCH",
            chain: "DIRECT",
            upload: 1,
            download: 2
        )
        store.replaceConnections([item])
        XCTAssertTrue(store.isActiveConnectionID("abc"))
        XCTAssertFalse(store.isActiveConnectionID("missing"))
        store.replaceConnections([])
        XCTAssertFalse(store.isActiveConnectionID("abc"))
    }
}
