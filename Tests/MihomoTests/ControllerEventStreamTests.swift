import XCTest
@testable import Mihomo

final class ControllerEventStreamTests: XCTestCase {
    func testParsesTrafficEvents() throws {
        let data = try jsonData([
            "up": 128,
            "down": "256"
        ])

        XCTAssertEqual(
            MihomoControllerEventStream.parseTrafficEvent(data: data),
            .traffic(uploadRate: 128, downloadRate: 256)
        )
    }

    func testParsesLogEventsAsCoreLogs() throws {
        let data = try jsonData([
            "type": "warning",
            "payload": "dns lookup failed"
        ])

        XCTAssertEqual(
            MihomoControllerEventStream.parseLogEvent(data: data),
            .log(level: "core", message: "[warning] dns lookup failed")
        )
    }

    func testParsesConnectionEvents() throws {
        let data = try jsonData([
            "uploadTotal": 10,
            "downloadTotal": 20,
            "connections": [[
                "id": "c1",
                "metadata": [
                    "host": "example.com",
                    "process": "Safari",
                    "network": "tcp"
                ],
                "rule": "DOMAIN-SUFFIX",
                "rulePayload": "example.com",
                "chains": ["Auto", "node-a"],
                "upload": 1,
                "download": 2
            ]]
        ])

        guard case let .connections(items, uploadTotal, downloadTotal) = MihomoControllerEventStream.parseConnectionEvent(data: data) else {
            return XCTFail("Expected connection event")
        }
        XCTAssertEqual(uploadTotal, 10)
        XCTAssertEqual(downloadTotal, 20)
        XCTAssertEqual(items.first?.host, "example.com")
        XCTAssertEqual(items.first?.rule, "DOMAIN-SUFFIX example.com")
        XCTAssertEqual(items.first?.chain, "Auto -> node-a")
    }

    func testRecoveryStateUsesPollingBeforeFirstLiveEvent() {
        var state = ControllerEventStreamRecoveryState()

        let firstFailure = state.recordFailure(hasReceivedEvent: false)

        XCTAssertEqual(firstFailure.status, "轮询")
        XCTAssertTrue(firstFailure.shouldLogWarning)
        XCTAssertEqual(firstFailure.backoffSeconds, 2)
    }

    func testRecoveryStateResetsAfterLiveEvent() {
        var state = ControllerEventStreamRecoveryState()
        _ = state.recordFailure(hasReceivedEvent: false)
        _ = state.recordFailure(hasReceivedEvent: false)

        state.recordEvent()
        let failureAfterEvent = state.recordFailure(hasReceivedEvent: true)

        XCTAssertEqual(failureAfterEvent.status, "降级")
        XCTAssertTrue(failureAfterEvent.shouldLogWarning)
        XCTAssertEqual(failureAfterEvent.backoffSeconds, 2)
    }

    func testRecoveryStateCapsReconnectBackoff() {
        var state = ControllerEventStreamRecoveryState()
        var lastDecision: ControllerEventStreamFailureDecision?

        for _ in 0..<8 {
            lastDecision = state.recordFailure(hasReceivedEvent: true)
        }

        XCTAssertEqual(lastDecision?.status, "降级")
        XCTAssertEqual(lastDecision?.shouldLogWarning, false)
        XCTAssertEqual(lastDecision?.backoffSeconds, 12)
    }

    private func jsonData(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }
}
