import XCTest
@testable import Mihomo

final class BoundedConcurrentWorkTests: XCTestCase {
    func testMapRespectsConcurrencyAndPreservesInputOrder() async {
        let tracker = WorkTracker()
        let inputs = Array(0..<9)

        let results = await BoundedConcurrentWork.map(inputs, maxConcurrent: 3) { value in
            await tracker.run(value)
        }

        let snapshot = await tracker.snapshot()
        XCTAssertEqual(results, inputs.map { $0 * 2 })
        XCTAssertEqual(snapshot.maxActive, 3)
    }

    func testMapClampsNonPositiveConcurrencyToOne() async {
        let tracker = WorkTracker()

        let results = await BoundedConcurrentWork.map([1, 2, 3], maxConcurrent: 0) { value in
            await tracker.run(value)
        }

        let snapshot = await tracker.snapshot()
        XCTAssertEqual(results, [2, 4, 6])
        XCTAssertEqual(snapshot.maxActive, 1)
    }

    func testProviderRefreshEligibilityRejectsItemsWithoutSourceOrPath() {
        let unavailable = ProviderItem(kind: "Rule", name: "Unavailable", detail: "")
        let remote = ProviderItem(kind: "Rule", name: "Remote", detail: "", remoteURL: "https://example.com/rules.yaml")
        let local = ProviderItem(kind: "Rule", name: "Local", detail: "", path: "rules/local.yaml")

        XCTAssertFalse(unavailable.canRefreshResource)
        XCTAssertTrue(remote.canRefreshResource)
        XCTAssertTrue(local.canRefreshResource)
    }

    func testCancellationStopsSchedulingAdditionalWork() async {
        let token = WorkCancellationToken()
        let results = await BoundedConcurrentWork.map(
            Array(0..<6),
            maxConcurrent: 1,
            shouldScheduleNext: { token.isCancelled == false }
        ) { value in
            if value == 1 {
                token.cancel()
            }
            return value
        }

        XCTAssertEqual(results, [0, 1])
    }
}

private actor WorkTracker {
    private var active = 0
    private var maxActive = 0

    func run(_ value: Int) async -> Int {
        active += 1
        maxActive = max(maxActive, active)
        try? await Task.sleep(nanoseconds: 10_000_000)
        active -= 1
        return value * 2
    }

    func snapshot() -> (maxActive: Int, active: Int) {
        (maxActive, active)
    }
}
