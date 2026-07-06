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

    private func jsonData(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }
}
