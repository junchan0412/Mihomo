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
                    "processPath": "/Applications/Safari.app/Contents/MacOS/Safari",
                    "network": "tcp",
                    "type": "HTTPS",
                    "sourceIP": "127.0.0.1",
                    "sourcePort": 51000,
                    "destinationIP": "93.184.216.34",
                    "destinationPort": "443",
                    "remoteDestination": "example.com:443"
                ],
                "rule": "DOMAIN-SUFFIX",
                "rulePayload": "example.com",
                "chains": ["Auto", "node-a"],
                "upload": 1,
                "download": 2,
                "start": "2026-07-10T15:35:34Z"
            ]]
        ]
        let (connections, uploadTotal, downloadTotal) = MihomoControllerClient.parseConnections(from: connectionsJSON)

        XCTAssertEqual(uploadTotal, 12)
        XCTAssertEqual(downloadTotal, 34)
        XCTAssertEqual(connections.first?.rule, "DOMAIN-SUFFIX example.com")
        XCTAssertEqual(connections.first?.chain, "Auto -> node-a")
        XCTAssertEqual(connections.first?.processPath, "/Applications/Safari.app/Contents/MacOS/Safari")
        XCTAssertEqual(connections.first?.metadataType, "HTTPS")
        XCTAssertEqual(connections.first?.sourceIP, "127.0.0.1")
        XCTAssertEqual(connections.first?.sourcePort, "51000")
        XCTAssertEqual(connections.first?.destinationIP, "93.184.216.34")
        XCTAssertEqual(connections.first?.destinationPort, "443")
        XCTAssertEqual(connections.first?.remoteDestination, "example.com:443")
        XCTAssertNotNil(connections.first?.start)
    }

    func testConnectionParsingUsesSniffHostAndNormalizesInnerProcess() throws {
        let payload: [String: Any] = [
            "connections": [[
                "id": "sniffed",
                "metadata": [
                    "type": "Inner",
                    "sniffHost": "cdn.example.com",
                    "destinationIP": "198.18.0.2",
                    "network": "tcp"
                ],
                "chains": ["DIRECT"]
            ]]
        ]

        let item = try XCTUnwrap(MihomoControllerClient.parseConnections(from: payload).0.first)
        XCTAssertEqual(item.host, "cdn.example.com")
        XCTAssertEqual(item.process, "mihomo")
    }

    func testConnectionStartParsingSupportsFractionalISOAndEpochValues() throws {
        let connectionsJSON: [String: Any] = [
            "connections": [
                [
                    "id": "fractional",
                    "metadata": ["host": "fractional.example", "process": "Safari", "network": "tcp"],
                    "upload": 0,
                    "download": 0,
                    "start": "2026-07-10T15:35:34.250Z"
                ],
                [
                    "id": "milliseconds",
                    "metadata": ["host": "milliseconds.example", "process": "Safari", "network": "tcp"],
                    "upload": 0,
                    "download": 0,
                    "start": 1_700_000_000_000
                ],
                [
                    "id": "seconds",
                    "metadata": ["host": "seconds.example", "process": "Safari", "network": "tcp"],
                    "upload": 0,
                    "download": 0,
                    "start": 1_700_000_100
                ]
            ]
        ]

        let (connections, _, _) = MihomoControllerClient.parseConnections(from: connectionsJSON)
        let baseDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-10T15:35:34Z"))
        let fractionalStart = try XCTUnwrap(connections[0].start)
        let millisecondsStart = try XCTUnwrap(connections[1].start)
        let secondsStart = try XCTUnwrap(connections[2].start)

        XCTAssertEqual(connections.count, 3)
        XCTAssertEqual(
            fractionalStart.timeIntervalSince1970,
            baseDate.timeIntervalSince1970 + 0.25,
            accuracy: 0.001
        )
        XCTAssertEqual(millisecondsStart.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
        XCTAssertEqual(secondsStart.timeIntervalSince1970, 1_700_000_100, accuracy: 0.001)
    }

    func testConnectionWithoutControllerIDGetsStableFallbackIdentity() throws {
        let payload: [String: Any] = [
            "connections": [[
                "metadata": [
                    "host": "example.com",
                    "sourceIP": "127.0.0.1",
                    "sourcePort": 51000,
                    "destinationIP": "93.184.216.34",
                    "destinationPort": 443,
                    "network": "tcp",
                    "processPath": "/Applications/Safari.app/Contents/MacOS/Safari"
                ],
                "chains": ["Auto", "node-a"],
                "upload": 1,
                "download": 2
            ]]
        ]

        let first = try XCTUnwrap(MihomoControllerClient.parseConnections(from: payload).0.first?.id)
        let second = try XCTUnwrap(MihomoControllerClient.parseConnections(from: payload).0.first?.id)

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("connection-"))
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

    func testHelperRuntimeBindingAuditAcceptsCurrentAppVersionAndPath() {
        let appURL = URL(fileURLWithPath: "/Applications/Mihomo.app")
        let result = HelperRuntimeBindingAudit.evaluate(
            currentAppURL: appURL,
            currentVersion: "1.8.47",
            currentBuild: "abc123",
            payload: [
                "authorizedAppBundle": "/Applications/Mihomo.app",
                "authorizedAppVersion": "1.8.47",
                "authorizedAppBuild": "abc123"
            ]
        )

        XCTAssertEqual(result.state, .ok)
    }

    func testHelperRuntimeBindingAuditWarnsForOldRegisteredApp() {
        let appURL = URL(fileURLWithPath: "/Applications/Mihomo.app")
        let result = HelperRuntimeBindingAudit.evaluate(
            currentAppURL: appURL,
            currentVersion: "1.8.47",
            currentBuild: "abc123",
            payload: [
                "authorizedAppBundle": "/Applications/Mihomo-Old.app",
                "authorizedAppVersion": "1.8.46",
                "authorizedAppBuild": "old999"
            ]
        )

        XCTAssertEqual(result.state, .warning)
        XCTAssertTrue(result.detail.contains("Mihomo-Old.app"))
        XCTAssertTrue(result.detail.contains("old999"))
    }
}
