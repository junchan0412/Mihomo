import XCTest
@testable import Mihomo

final class BackupAndDiagnosticSecurityTests: XCTestCase {
    func testRestoreLocalArchiveRestoresApprovedEntries() throws {
        let root = temporaryDirectory()
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Profiles"), withIntermediateDirectories: true)
        try "settings".write(to: source.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        try "profile".write(to: source.appendingPathComponent("Profiles/main.yaml"), atomically: true, encoding: .utf8)

        let archive = root.appendingPathComponent("valid.zip")
        try zip(archive: archive, paths: ["settings.json", "Profiles"], workDirectory: source)

        let manager = BackupManager(supportDirectory: support, backupsDirectory: backups)
        try manager.restoreLocalArchive(archive)

        XCTAssertEqual(try String(contentsOf: support.appendingPathComponent("settings.json"), encoding: .utf8), "settings")
        XCTAssertEqual(try String(contentsOf: support.appendingPathComponent("Profiles/main.yaml"), encoding: .utf8), "profile")
    }

    func testRestoreLocalArchiveRejectsParentTraversal() throws {
        let root = temporaryDirectory()
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let nested = source.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "escape".write(to: source.appendingPathComponent("escape.txt"), atomically: true, encoding: .utf8)

        let archive = root.appendingPathComponent("traversal.zip")
        try zip(archive: archive, paths: ["../escape.txt"], workDirectory: nested)

        let manager = BackupManager(
            supportDirectory: root.appendingPathComponent("Support", isDirectory: true),
            backupsDirectory: root.appendingPathComponent("Backups", isDirectory: true)
        )
        XCTAssertThrowsError(try manager.restoreLocalArchive(archive)) { error in
            XCTAssertTrue(error.localizedDescription.contains("不能包含 .."))
        }
    }

    func testRestoreLocalArchiveRejectsUnknownTopLevelEntries() throws {
        let root = temporaryDirectory()
        let source = root.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Runtime"), withIntermediateDirectories: true)
        try "runtime".write(to: source.appendingPathComponent("Runtime/config.yaml"), atomically: true, encoding: .utf8)

        let archive = root.appendingPathComponent("unknown.zip")
        try zip(archive: archive, paths: ["Runtime"], workDirectory: source)

        let manager = BackupManager(
            supportDirectory: root.appendingPathComponent("Support", isDirectory: true),
            backupsDirectory: root.appendingPathComponent("Backups", isDirectory: true)
        )
        XCTAssertThrowsError(try manager.restoreLocalArchive(archive)) { error in
            XCTAssertTrue(error.localizedDescription.contains("允许恢复清单"))
        }
    }

    func testRestoreLocalArchiveRejectsSymbolicLinks() throws {
        let root = temporaryDirectory()
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Profiles"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("Profiles/link"),
            withDestinationURL: outside
        )

        let archive = root.appendingPathComponent("symlink.zip")
        try zip(archive: archive, paths: ["Profiles"], workDirectory: source)

        let manager = BackupManager(
            supportDirectory: root.appendingPathComponent("Support", isDirectory: true),
            backupsDirectory: root.appendingPathComponent("Backups", isDirectory: true)
        )
        XCTAssertThrowsError(try manager.restoreLocalArchive(archive)) { error in
            XCTAssertTrue(error.localizedDescription.contains("符号链接"))
        }
    }

    func testRestoreLocalArchiveRejectsExistingDestinationSymlinkEscape() throws {
        let root = temporaryDirectory()
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Profiles"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: support.appendingPathComponent("Profiles"),
            withDestinationURL: outside
        )
        try "profile".write(to: source.appendingPathComponent("Profiles/main.yaml"), atomically: true, encoding: .utf8)

        let archive = root.appendingPathComponent("destination-symlink.zip")
        try zip(archive: archive, paths: ["Profiles"], workDirectory: source)

        let manager = BackupManager(
            supportDirectory: support,
            backupsDirectory: root.appendingPathComponent("Backups", isDirectory: true)
        )
        XCTAssertThrowsError(try manager.restoreLocalArchive(archive)) { error in
            XCTAssertTrue(error.localizedDescription.contains("App Support"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("main.yaml").path))
    }

    func testDiagnosticRedactorRemovesKnownSecretsAndCredentialPatterns() {
        var settings = AppSettings.default
        settings.controllerSecret = "controller-secret-123"
        settings.backupWebDAVPassword = "webdav-password-456"
        settings.gistToken = "gist-token-789"
        let redactor = DiagnosticRedactor(settings: settings)

        let redacted = redactor.redact(
            """
            secret: controller-secret-123
            Authorization: Bearer controller-secret-123
            backup: https://user:webdav-password-456@example.com/backup.zip?token=gist-token-789&keep=1
            gistToken: gist-token-789
            """
        )

        XCTAssertFalse(redacted.contains("controller-secret-123"))
        XCTAssertFalse(redacted.contains("webdav-password-456"))
        XCTAssertFalse(redacted.contains("gist-token-789"))
        XCTAssertTrue(redacted.contains("<redacted>"))
        XCTAssertTrue(redacted.contains("keep=1"))
    }

    private func zip(archive: URL, paths: [String], workDirectory: URL) throws {
        let result = try Shell.run("/usr/bin/zip", ["-qry", archive.path] + paths, workDirectory: workDirectory)
        XCTAssertEqual(result.status, 0, result.stderr.isEmpty ? result.stdout : result.stderr)
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MihomoTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
