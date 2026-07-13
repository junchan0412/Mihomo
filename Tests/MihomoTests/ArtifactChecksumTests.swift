import XCTest
@testable import Mihomo

final class ArtifactChecksumTests: XCTestCase {
    func testManagedCoreChecksumMismatchDoesNotReplaceExistingExecutable() throws {
        let root = temporaryDirectory()
        let target = root.appendingPathComponent("Core/mihomo")
        let downloaded = root.appendingPathComponent("downloaded-mihomo")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "old-core".write(to: target, atomically: true, encoding: .utf8)
        try "new-core".write(to: downloaded, atomically: true, encoding: .utf8)

        let manager = ManagedCoreManager(managedCoreFile: target)

        XCTAssertThrowsError(try manager.installDownloadedArtifact(
            downloaded,
            sourceURL: URL(string: "https://example.com/mihomo")!,
            expectedSHA256: String(repeating: "1", count: 64)
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("SHA-256 不匹配"))
        }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "old-core")
    }

    func testManagedCoreMissingChecksumIsRejected() throws {
        let root = temporaryDirectory()
        let target = root.appendingPathComponent("Core/mihomo")
        let downloaded = root.appendingPathComponent("downloaded-mihomo")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "old-core".write(to: target, atomically: true, encoding: .utf8)
        try "new-core".write(to: downloaded, atomically: true, encoding: .utf8)

        let manager = ManagedCoreManager(managedCoreFile: target)

        XCTAssertThrowsError(try manager.installDownloadedArtifact(
            downloaded,
            sourceURL: URL(string: "https://example.com/mihomo")!,
            expectedSHA256: ""
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("缺少 SHA-256"))
        }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "old-core")
    }

    func testAgeChecksumMismatchDoesNotReplaceExistingTools() throws {
        let root = temporaryDirectory()
        let tools = root.appendingPathComponent("Tools", isDirectory: true)
        let runtime = root.appendingPathComponent("Runtime", isDirectory: true)
        let targetAge = tools.appendingPathComponent("age")
        let targetKeygen = tools.appendingPathComponent("age-keygen")
        let downloaded = root.appendingPathComponent("age.tar.gz")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        try "old-age".write(to: targetAge, atomically: true, encoding: .utf8)
        try "old-keygen".write(to: targetKeygen, atomically: true, encoding: .utf8)
        try "not-the-expected-archive".write(to: downloaded, atomically: true, encoding: .utf8)

        let service = ProfileAgeService(toolsDirectory: tools, runtimeDirectory: runtime)

        XCTAssertThrowsError(try service.installDownloadedArchive(
            downloaded,
            expectedSHA256: String(repeating: "2", count: 64)
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("SHA-256 不匹配"))
        }
        XCTAssertEqual(try String(contentsOf: targetAge, encoding: .utf8), "old-age")
        XCTAssertEqual(try String(contentsOf: targetKeygen, encoding: .utf8), "old-keygen")
    }

    func testGeoChecksumMismatchDoesNotReplaceExistingData() throws {
        let root = temporaryDirectory()
        let target = root.appendingPathComponent("Geo/geoip.dat")
        let downloaded = root.appendingPathComponent("geoip.dat")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "old-geo".write(to: target, atomically: true, encoding: .utf8)
        try "untrusted-geo".write(to: downloaded, atomically: true, encoding: .utf8)

        let manager = GeoUpdateManager(geoDirectory: target.deletingLastPathComponent())

        XCTAssertThrowsError(try manager.installDownloadedArtifact(
            downloaded,
            to: target,
            expectedSHA256: String(repeating: "4", count: 64),
            artifactName: "GeoIP 数据"
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("SHA-256 不匹配"))
        }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "old-geo")
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MihomoArtifactTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
