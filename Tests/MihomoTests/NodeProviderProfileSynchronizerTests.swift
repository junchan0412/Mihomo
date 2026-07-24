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

    func testSynchronizationPreservesCommentsOrderAndUnknownFields() throws {
        let provider = NodeProvider(
            name: "subscription-a",
            url: "https://example.com/new",
            path: "proxy_providers/a.yaml",
            interval: 7_200,
            profileIDs: [UUID()]
        )
        let source = """
        # top-level comment
        mixed-port: 7890
        proxy-providers:
          subscription-a: # provider comment
            type: http
            url: https://example.com/old  # keep this spacing
            health-check:
              enable: true
              url: https://example.com/health
            path: proxy_providers/a.yaml
            interval: 3600
        rules:
          - MATCH,DIRECT
        """

        let synchronized = try NodeProviderProfileSynchronizer().synchronizing([provider], into: source)

        XCTAssertTrue(synchronized.hasPrefix("# top-level comment\nmixed-port: 7890\nproxy-providers:"))
        XCTAssertTrue(synchronized.contains("url: https://example.com/new  # keep this spacing"))
        XCTAssertTrue(synchronized.contains("health-check:\n      enable: true"))
        XCTAssertTrue(synchronized.hasSuffix("rules:\n  - MATCH,DIRECT"))
    }

    func testSynchronizationReusesExistingProviderIndentation() throws {
        let provider = NodeProvider(
            name: "subscription-b",
            url: "https://example.com/b",
            path: "proxy_providers/b.yaml",
            profileIDs: [UUID()]
        )
        let synchronized = try NodeProviderProfileSynchronizer().synchronizing(
            [provider],
            into: """
            proxy-providers:
                subscription-a:
                  type: http
                  url: https://example.com/a
            """
        )

        XCTAssertTrue(synchronized.contains("    subscription-b:\n      type: http"))
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

    func testRefreshPreservesMissingProviderBlockVerbatim() throws {
        let synchronized = try NodeProviderProfileSynchronizer().preservingExistingProviders(
            from: """
            proxy-providers:
              keep-me: # managed locally
                type: http
                # keep health check note
                health-check:
                  enable: true
                url: https://example.com/keep
            """,
            in: """
            proxy-providers:
              upstream:
                type: http
                url: https://example.com/upstream
            rules: []
            """
        )

        XCTAssertTrue(synchronized.contains("keep-me: # managed locally\n    type: http\n    # keep health check note"))
        XCTAssertTrue(synchronized.contains("rules: []"))
    }
}
