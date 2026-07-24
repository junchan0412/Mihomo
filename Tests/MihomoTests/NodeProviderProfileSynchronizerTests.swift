import XCTest
@testable import Mihomo

final class NodeProviderProfileSynchronizerTests: XCTestCase {
    func testExtractsProxyProvidersForImportedProfile() throws {
        let profileID = UUID(uuidString: "E7830C07-60E6-4C40-A7C2-881ED586FBB9")!
        let providers = try NodeProviderProfileSynchronizer().nodeProviders(
            from: """
            proxy-providers:
              subscription-a:
                type: http
                url: https://example.com/a
                path: proxy_providers/a.yaml
                interval: 3600
              local-cache:
                type: file
                path: proxy_providers/local.yaml
            """,
            profileID: profileID
        )

        XCTAssertEqual(providers.map(\.name), ["local-cache", "subscription-a"])
        XCTAssertEqual(providers.first { $0.name == "subscription-a" }?.url, "https://example.com/a")
        XCTAssertEqual(providers.first { $0.name == "subscription-a" }?.interval, 3_600)
        XCTAssertEqual(providers.first { $0.name == "local-cache" }?.providerType, "file")
        XCTAssertTrue(providers.allSatisfy { $0.profileIDs == [profileID] })
    }

    func testSynchronizesSelectedProviderWithoutDiscardingExtraProfileFields() throws {
        let provider = NodeProvider(
            name: "subscription-a",
            url: "https://example.com/new",
            path: "proxy_providers/a.yaml",
            interval: 7_200,
            profileIDs: [UUID()]
        )
        let synchronized = try NodeProviderProfileSynchronizer().synchronizing(
            [provider],
            into: """
            proxy-providers:
              subscription-a:
                type: http
                url: https://example.com/old
                health-check:
                  enable: true
                  url: https://example.com/health
            """
        )

        XCTAssertTrue(synchronized.contains("https://example.com/new"))
        XCTAssertTrue(synchronized.contains("health-check:"))
        XCTAssertTrue(synchronized.contains("proxy_providers/a.yaml"))
    }

    func testRefreshPreservesExistingProvidersWhenRemotePayloadOmitsThem() throws {
        let synchronized = try NodeProviderProfileSynchronizer().preservingExistingProviders(
            from: """
            proxy-providers:
              keep-me:
                type: http
                url: https://example.com/keep
            proxy-groups: []
            """,
            in: """
            proxies: []
            proxy-groups: []
            """
        )

        XCTAssertTrue(synchronized.contains("keep-me:"))
        XCTAssertTrue(synchronized.contains("https://example.com/keep"))
    }
}
