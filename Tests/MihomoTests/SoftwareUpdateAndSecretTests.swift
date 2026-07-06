import XCTest
@testable import Mihomo

final class SoftwareUpdateAndSecretTests: XCTestCase {
    func testUpdateManagerComparesVersionsAndBuilds() {
        let manager = SoftwareUpdateManager()

        XCTAssertTrue(manager.isManifestNewer(
            AppUpdateManifest(version: "1.3.0", build: nil, url: "Mihomo.zip", sha256: String(repeating: "a", count: 64)),
            currentVersion: "1.2.0",
            currentBuild: "abc123"
        ))
        XCTAssertTrue(manager.isManifestNewer(
            AppUpdateManifest(version: "1.2.0", build: "def456", url: "Mihomo.zip", sha256: String(repeating: "b", count: 64)),
            currentVersion: "1.2.0",
            currentBuild: "abc123"
        ))
        XCTAssertFalse(manager.isManifestNewer(
            AppUpdateManifest(version: "1.1.9", build: nil, url: "Mihomo.zip", sha256: String(repeating: "c", count: 64)),
            currentVersion: "1.2.0",
            currentBuild: "abc123"
        ))
    }

    func testLocalSecretVaultRoundTripsEncryptedPayload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mihomo-secret-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let vaultURL = directory.appendingPathComponent("secrets.json")
        let vault = LocalSecretVault(fileURL: vaultURL)
        let secrets = AppSecretValues(
            controllerSecret: "controller",
            backupWebDAVPassword: "webdav",
            gistToken: "gist"
        )

        try vault.saveSecrets(secrets)
        XCTAssertEqual(try vault.loadSecrets(), secrets)
        XCTAssertFalse((try String(contentsOf: vaultURL, encoding: .utf8)).contains("controller"))
    }
}
