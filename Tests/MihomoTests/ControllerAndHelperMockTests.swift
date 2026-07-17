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

    func testHelperCallCompletionCanOnlyFinishOnce() {
        let completion = HelperCallCompletion()

        XCTAssertTrue(completion.claim())
        XCTAssertFalse(completion.claim())
    }

    func testHelperTimeoutErrorOffersRecoveryAction() {
        let message = HelperCallError.timeout(seconds: 2).localizedDescription

        XCTAssertTrue(message.contains("2 秒"))
        XCTAssertTrue(message.contains("重新注册 Helper"))
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

    func testLegacyHelperPlistsBindStandaloneHelperToExactAppCDHash() {
        let daemon = LegacyHelperInstaller.legacyPlist(
            helperPath: "/Library/PrivilegedHelperTools/dev.codex.Mihomo.Helper"
        )
        let authorization = LegacyHelperInstaller.authorizationPlist(
            appPath: "/Applications/Mihomo.app",
            cdHash: "ABCDEF1234"
        )

        XCTAssertTrue(daemon.contains("/Library/PrivilegedHelperTools/dev.codex.Mihomo.Helper"))
        XCTAssertFalse(daemon.contains("BundleProgram"))
        XCTAssertTrue(authorization.contains("/Applications/Mihomo.app"))
        XCTAssertTrue(authorization.contains("abcdef1234"))
        XCTAssertTrue(authorization.contains("AuthorizedAppCDHash"))
    }

    func testLegacyHelperInstallCommandUsesRootOwnedFixedPaths() {
        let command = LegacyHelperInstaller.installationCommand(
            sourcePath: "/Applications/Mihomo.app/Contents/Library/LaunchServices/MihomoHelper",
            sourceSHA256: String(repeating: "a", count: 64),
            helperPath: "/Library/PrivilegedHelperTools/dev.codex.Mihomo.Helper",
            stagingPlistPath: "/tmp/helper.plist",
            stagingPlistSHA256: String(repeating: "b", count: 64),
            plistPath: "/Library/LaunchDaemons/dev.codex.Mihomo.Helper.plist",
            stagingAuthorizationPath: "/tmp/authorization.plist",
            stagingAuthorizationSHA256: String(repeating: "c", count: 64),
            authorizationPath: "/Library/PrivilegedHelperTools/dev.codex.Mihomo.Helper.authorization.plist"
        )

        XCTAssertTrue(command.contains("chown root:wheel"))
        XCTAssertTrue(command.contains("chmod 600"))
        XCTAssertTrue(command.contains("launchctl bootstrap system"))
        XCTAssertTrue(command.contains("shasum -a 256"))
        XCTAssertTrue(command.contains(".installing"))
        XCTAssertTrue(command.contains("/Library/PrivilegedHelperTools/dev.codex.Mihomo.Helper"))
        XCTAssertTrue(command.contains("/Library/LaunchDaemons/dev.codex.Mihomo.Helper.plist"))

        let flattened = LegacyHelperInstaller.flattenedShellCommand(command)
        XCTAssertFalse(flattened.contains("\n"))
        XCTAssertEqual(try? Shell.run("/bin/sh", ["-n", "-c", flattened]).status, 0)
    }

    func testAdHocSignaturesUseLegacyHelperInsteadOfWaitingForSMAppServiceApproval() {
        let app = """
        Identifier=dev.codex.Mihomo
        Signature=adhoc
        TeamIdentifier=not set
        """
        let helper = """
        Identifier=dev.codex.Mihomo.Helper
        Signature=adhoc
        TeamIdentifier=not set
        """

        XCTAssertFalse(LegacyHelperInstaller.signaturesSupportBundledSMAppService(
            appOutput: app,
            helperOutput: helper
        ))
    }

    func testMatchingAppleTeamSignaturesCanUseBundledSMAppService() {
        let app = """
        Identifier=dev.codex.Mihomo
        Authority=Developer ID Application: Example (ABCDE12345)
        TeamIdentifier=ABCDE12345
        """
        let helper = """
        Identifier=dev.codex.Mihomo.Helper
        Authority=Developer ID Application: Example (ABCDE12345)
        TeamIdentifier=ABCDE12345
        """

        XCTAssertTrue(LegacyHelperInstaller.signaturesSupportBundledSMAppService(
            appOutput: app,
            helperOutput: helper
        ))

        XCTAssertFalse(LegacyHelperInstaller.signaturesSupportBundledSMAppService(
            appOutput: app,
            helperOutput: helper.replacingOccurrences(of: "ABCDE12345", with: "ZYXWV98765")
        ))
    }
}
