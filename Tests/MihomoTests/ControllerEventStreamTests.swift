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

    func testBuildsControllerWebSocketRequestWithBoundedTimeoutAndAuthorization() throws {
        let stream = MihomoControllerEventStream(
            host: "127.0.0.1",
            port: 9090,
            secret: " controller-token "
        )

        let request = try stream.request(
            path: "logs",
            queryItems: [URLQueryItem(name: "level", value: "warning")]
        )
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "ws")
        XCTAssertEqual(components.host, "127.0.0.1")
        XCTAssertEqual(components.port, 9090)
        XCTAssertEqual(components.path, "/logs")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "level", value: "warning")])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer controller-token")
        XCTAssertEqual(request.timeoutInterval, NetworkRequestKind.controller.requestTimeout)
    }

    func testConnectionStreamUsesRealtimeHalfSecondInterval() throws {
        let request = try MihomoControllerEventStream(host: "127.0.0.1", port: 9090)
            .request(path: "/connections", queryItems: [URLQueryItem(name: "interval", value: "500")])

        XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "500")
    }

    func testInvalidEndpointFailsWithoutCrashing() async {
        let stream = MihomoControllerEventStream(host: "", port: 0).trafficEvents()

        do {
            for try await _ in stream {}
            XCTFail("Expected invalid endpoint error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("地址无效"))
        }
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
