import CryptoKit
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

    func testPortableSecretBundleImportsIntoDifferentVault() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mihomo-secret-portable-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceVault = LocalSecretVault(fileURL: directory.appendingPathComponent("source.vault"))
        let targetVault = LocalSecretVault(fileURL: directory.appendingPathComponent("target.vault"))
        let secrets = AppSecretValues(
            controllerSecret: "controller-portable",
            backupWebDAVPassword: "webdav-portable",
            gistToken: "gist-portable"
        )

        try sourceVault.saveSecrets(secrets)
        let bundle = try sourceVault.exportPortableSecrets(passphrase: "correct horse battery staple", iterations: 10_000)

        XCTAssertFalse(bundle.contains("controller-portable"))
        XCTAssertEqual(try targetVault.importPortableSecrets(bundle, passphrase: "correct horse battery staple"), secrets)
        XCTAssertEqual(try targetVault.loadSecrets(), secrets)
    }

    func testPortableSecretBundleRejectsWrongPassphraseWithoutReplacingVault() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mihomo-secret-portable-failure-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceVault = LocalSecretVault(fileURL: directory.appendingPathComponent("source.vault"))
        let targetVault = LocalSecretVault(fileURL: directory.appendingPathComponent("target.vault"))
        let sourceSecrets = AppSecretValues(
            controllerSecret: "source-controller",
            backupWebDAVPassword: "source-webdav",
            gistToken: "source-gist"
        )
        let existingSecrets = AppSecretValues(
            controllerSecret: "existing-controller",
            backupWebDAVPassword: "existing-webdav",
            gistToken: "existing-gist"
        )

        try sourceVault.saveSecrets(sourceSecrets)
        try targetVault.saveSecrets(existingSecrets)
        let bundle = try sourceVault.exportPortableSecrets(passphrase: "migration-passphrase", iterations: 10_000)

        XCTAssertThrowsError(try targetVault.importPortableSecrets(bundle, passphrase: "wrong-passphrase"))
        XCTAssertEqual(try targetVault.loadSecrets(), existingSecrets)
    }

    func testUpdatePackageValidationRejectsShaMismatchBeforeInstallScript() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let zipURL = root.appendingPathComponent("Mihomo.zip")
        try Data("not a zip".utf8).write(to: zipURL)
        let tempRoot = root.appendingPathComponent("update", isDirectory: true)

        XCTAssertThrowsError(try SoftwareUpdateManager().prepareDownloadedUpdatePackage(
            zipURL: zipURL,
            manifest: manifest(sha256: String(repeating: "0", count: 64)),
            tempRoot: tempRoot
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("SHA-256 不匹配"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("install-update.sh").path))
    }

    func testUpdatePackageValidationRejectsZipWithoutAppBeforeInstallScript() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("release notes".utf8).write(to: source.appendingPathComponent("README.txt"))

        let zipURL = root.appendingPathComponent("Mihomo.zip")
        try zip(archive: zipURL, paths: ["README.txt"], workDirectory: source)
        let tempRoot = root.appendingPathComponent("update", isDirectory: true)

        XCTAssertThrowsError(try SoftwareUpdateManager().prepareDownloadedUpdatePackage(
            zipURL: zipURL,
            manifest: manifest(sha256: sha256(of: zipURL)),
            tempRoot: tempRoot
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("没有 Mihomo.app"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("install-update.sh").path))
    }

    func testUpdatePackageValidationRejectsBundleIdentifierBeforeInstallScript() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        let app = source.appendingPathComponent("Mihomo.app", isDirectory: true)
        try writeInfoPlist(to: app, bundleIdentifier: "com.example.BadMihomo", version: "1.8.33")

        let zipURL = root.appendingPathComponent("Mihomo.zip")
        try zip(archive: zipURL, paths: ["Mihomo.app"], workDirectory: source)
        let tempRoot = root.appendingPathComponent("update", isDirectory: true)

        XCTAssertThrowsError(try SoftwareUpdateManager().prepareDownloadedUpdatePackage(
            zipURL: zipURL,
            manifest: manifest(sha256: sha256(of: zipURL)),
            tempRoot: tempRoot
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("bundle id 不匹配"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("install-update.sh").path))
    }

    func testInstallScriptRestoresPreviousAppWhenDittoFails() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let current = root.appendingPathComponent("Mihomo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("current version".utf8).write(to: current.appendingPathComponent("marker.txt"))

        let tempRoot = root.appendingPathComponent("installer", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let script = try SoftwareUpdateManager().writeInstallScript(tempRoot: tempRoot)
        let missingCandidate = root.appendingPathComponent("missing-candidate.app", isDirectory: true)

        let result = try Shell.run("/bin/sh", [script.path, current.path, missingCandidate.path, tempRoot.path])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertEqual(try String(contentsOf: current.appendingPathComponent("marker.txt"), encoding: .utf8), "current version")
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.path + ".previous-update"))
    }

    func testInstallScriptRestoresPreviousAppWhenPostCopyCodesignFails() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let current = root.appendingPathComponent("Mihomo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("current version".utf8).write(to: current.appendingPathComponent("marker.txt"))

        let candidate = root.appendingPathComponent("candidate.app", isDirectory: true)
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        try Data("unsigned candidate".utf8).write(to: candidate.appendingPathComponent("marker.txt"))

        let tempRoot = root.appendingPathComponent("installer", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let script = try SoftwareUpdateManager().writeInstallScript(tempRoot: tempRoot)

        let result = try Shell.run("/bin/sh", [script.path, current.path, candidate.path, tempRoot.path])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertEqual(try String(contentsOf: current.appendingPathComponent("marker.txt"), encoding: .utf8), "current version")
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.path + ".previous-update"))
    }

    private func manifest(sha256: String) -> AppUpdateManifest {
        AppUpdateManifest(
            version: "1.8.33",
            build: nil,
            url: "Mihomo.zip",
            sha256: sha256,
            bundleIdentifier: "dev.codex.Mihomo",
            signingIdentifier: "dev.codex.Mihomo"
        )
    }

    private func writeInfoPlist(to appURL: URL, bundleIdentifier: String, version: String) throws {
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleShortVersionString": version
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private func zip(archive: URL, paths: [String], workDirectory: URL) throws {
        let result = try Shell.run("/usr/bin/zip", ["-qry", archive.path] + paths, workDirectory: workDirectory)
        XCTAssertEqual(result.status, 0, result.stderr)
    }

    private func sha256(of fileURL: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: fileURL))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mihomo-update-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
