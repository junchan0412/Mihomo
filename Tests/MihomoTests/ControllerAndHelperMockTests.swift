import XCTest
@testable import Mihomo

final class ControllerAndHelperMockTests: XCTestCase {
    func testMockControllerProxyAndConnectionParsing() {
        let proxyJSON: [String: Any] = [
            "proxies": [
                "GLOBAL": [
                    "type": "Selector",
                    "now": "node-a",
                    "all": ["node-a"]
                ],
                "node-a": [
                    "type": "Shadowsocks",
                    "history": [["delay": 42]]
                ]
            ]
        ]
        let groups = MihomoControllerClient.parseProxyGroups(from: proxyJSON)

        XCTAssertEqual(groups.first?.name, "GLOBAL")
        XCTAssertEqual(groups.first?.all.first?.delay, 42)

        let connectionsJSON: [String: Any] = [
            "uploadTotal": 12,
            "downloadTotal": "34",
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
        ]
        let (connections, uploadTotal, downloadTotal) = MihomoControllerClient.parseConnections(from: connectionsJSON)

        XCTAssertEqual(uploadTotal, 12)
        XCTAssertEqual(downloadTotal, 34)
        XCTAssertEqual(connections.first?.rule, "DOMAIN-SUFFIX example.com")
        XCTAssertEqual(connections.first?.chain, "Auto -> node-a")
    }

    func testMockControllerProviderParsing() {
        let providerJSON: [String: Any] = [
            "providers": [
                "remote": [
                    "type": "http",
                    "vehicleType": "HTTP",
                    "updatedAt": "2026-07-06",
                    "rules": [["payload": "example.com"]]
                ]
            ]
        ]
        let providers = MihomoControllerClient.parseProviderItems(from: providerJSON, kind: "Rule")

        XCTAssertEqual(providers.first?.name, "remote")
        XCTAssertEqual(providers.first?.ruleCount, 1)
        XCTAssertEqual(providers.first?.memberNames, ["example.com"])
    }

    func testHelperOperationResultMapsPayloadAndFailures() throws {
        let result = try HelperOperationResult(dictionary: [
            "ok": true,
            "message": "done",
            "transactionSteps": "capture,set",
            "rollbackSuggestion": "restore"
        ])

        XCTAssertEqual(result.message, "done")
        XCTAssertEqual(result.payload["transactionSteps"], "capture,set")
        XCTAssertEqual(result.payload["rollbackSuggestion"], "restore")

        XCTAssertThrowsError(try HelperOperationResult(dictionary: [
            "ok": false,
            "message": "permission denied"
        ])) { error in
            XCTAssertTrue(error.localizedDescription.contains("permission denied"))
        }
    }
}
