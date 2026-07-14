import Foundation
import XCTest
@testable import Mihomo

final class ConfigFragmentStoreTests: XCTestCase {
    func testLegacyFragmentDefaultsToLocalSource() throws {
        let data = Data(#"{"name":"Legacy","kind":"yaml","enabled":true,"content":"dns:\n  enable: true"}"#.utf8)
        let fragment = try JSONDecoder().decode(ConfigFragment.self, from: data)

        XCTAssertEqual(fragment.source, .local)
        XCTAssertEqual(fragment.location, "")
        XCTAssertNil(fragment.certificateFingerprint)
        XCTAssertFalse(fragment.isRemote)
    }

    func testRemoteSourceMetadataRoundTripsThroughPersistence() throws {
        let original = ConfigFragment(
            name: "Remote",
            kind: .yaml,
            enabled: true,
            content: "dns:\n  enable: true",
            source: .remote,
            location: "https://example.com/override.yaml",
            certificateFingerprint: "abc123"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(ConfigFragment.self, from: encoder.encode(original))

        XCTAssertEqual(decoded.source, .remote)
        XCTAssertEqual(decoded.location, original.location)
        XCTAssertEqual(decoded.certificateFingerprint, "abc123")
        XCTAssertTrue(decoded.isRemote)
    }

    func testRemoteImportAndRefreshPreserveURLAndPinCertificate() async throws {
        let url = URL(string: "https://example.com/override.yaml")!
        let loader = ConfigFragmentRemoteLoaderStub(responses: [
            .init(
                data: Data("dns:\n  enable: true\n".utf8),
                response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                certificateFingerprint: "first"
            ),
            .init(
                data: Data("dns:\n  enable: false\n".utf8),
                response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                certificateFingerprint: "second"
            )
        ])
        let store = ConfigFragmentStore(remoteLoader: loader)

        let imported = try await store.importRemoteFragment(
            urlString: url.absoluteString,
            name: "DNS Patch",
            kind: .yaml
        )
        let refreshed = try await store.refreshRemoteFragment(imported)

        XCTAssertEqual(imported.source, .remote)
        XCTAssertEqual(imported.location, url.absoluteString)
        XCTAssertEqual(imported.certificateFingerprint, "first")
        XCTAssertTrue(refreshed.content.contains("enable: false"))
        XCTAssertEqual(refreshed.certificateFingerprint, "second")
        XCTAssertEqual(loader.expectedFingerprints, [nil, "first"])
    }

    func testRemoteImportRejectsInvalidURLAndNonMappingYAML() async throws {
        let url = URL(string: "https://example.com/override.yaml")!
        let loader = ConfigFragmentRemoteLoaderStub(responses: [
            .init(
                data: Data("- DIRECT\n- PROXY\n".utf8),
                response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                certificateFingerprint: nil
            )
        ])
        let store = ConfigFragmentStore(remoteLoader: loader)

        await XCTAssertThrowsErrorAsync {
            _ = try await store.importRemoteFragment(urlString: "file:///tmp/override.yaml", kind: .yaml)
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await store.importRemoteFragment(urlString: url.absoluteString, kind: .yaml)
        }
    }

    func testLocalImportInfersJavaScriptAndTracksOriginalPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mihomo-ConfigFragmentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("transform.js")
        try "function transform(config) { return config }".write(to: file, atomically: true, encoding: .utf8)

        let fragment = try ConfigFragmentStore().importLocalFragment(fileURL: file)

        XCTAssertEqual(fragment.name, "transform")
        XCTAssertEqual(fragment.kind, .javascript)
        XCTAssertEqual(fragment.source, .local)
        XCTAssertEqual(fragment.location, file.path)
    }

    func testLocalImportCanHonorExplicitKindForDeepLinks() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mihomo-ConfigFragment-\(UUID().uuidString).txt")
        try "function transform(config) { return config }".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let fragment = try ConfigFragmentStore().importLocalFragment(
            fileURL: file,
            name: "Deep Link",
            kind: .javascript
        )

        XCTAssertEqual(fragment.name, "Deep Link")
        XCTAssertEqual(fragment.kind, .javascript)
    }
}

private final class ConfigFragmentRemoteLoaderStub: ConfigFragmentRemoteLoading {
    private var responses: [ConfigFragmentRemoteResponse]
    private(set) var expectedFingerprints: [String?] = []

    init(responses: [ConfigFragmentRemoteResponse]) {
        self.responses = responses
    }

    func fetch(_ url: URL, expectedFingerprint: String?) async throws -> ConfigFragmentRemoteResponse {
        expectedFingerprints.append(expectedFingerprint)
        guard responses.isEmpty == false else {
            throw NSError(domain: "ConfigFragmentRemoteLoaderStub", code: 1)
        }
        return responses.removeFirst()
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        // Expected.
    }
}
