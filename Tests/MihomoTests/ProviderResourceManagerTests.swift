import XCTest
@testable import Mihomo

final class ProviderResourceManagerTests: XCTestCase {
    func testRefreshLocalProviderValidatesExistingFile() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = root.appendingPathComponent("Runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: runtime.appendingPathComponent("rules"), withIntermediateDirectories: true)
        let file = runtime.appendingPathComponent("rules/local.yaml")
        try "payload:\n  - example.com\n".write(to: file, atomically: true, encoding: .utf8)
        let manager = ProviderResourceManager(runtimeDirectory: runtime, backupsDirectory: root.appendingPathComponent("Backups"))
        let provider = ProviderItem(kind: "Rule", name: "Local", detail: "", providerType: "file", path: "rules/local.yaml")

        let result = try manager.refreshLocal(provider)

        XCTAssertEqual(result.target.standardizedFileURL, file.standardizedFileURL)
        XCTAssertGreaterThan(result.size, 0)
    }

    func testTargetURLRejectsParentTraversal() throws {
        let root = temporaryDirectory()
        let manager = ProviderResourceManager(
            runtimeDirectory: root.appendingPathComponent("Runtime", isDirectory: true),
            backupsDirectory: root.appendingPathComponent("Backups", isDirectory: true)
        )
        let provider = ProviderItem(
            kind: "Rule",
            name: "remote",
            detail: "",
            remoteURL: "https://example.com/rules.yaml",
            path: "../escape.yaml"
        )

        XCTAssertThrowsError(try manager.targetURL(for: provider)) { error in
            XCTAssertTrue(error.localizedDescription.contains("不能包含 .."))
        }
    }

    func testTargetURLRejectsAbsolutePath() throws {
        let root = temporaryDirectory()
        let manager = ProviderResourceManager(
            runtimeDirectory: root.appendingPathComponent("Runtime", isDirectory: true),
            backupsDirectory: root.appendingPathComponent("Backups", isDirectory: true)
        )
        let provider = ProviderItem(
            kind: "Rule",
            name: "remote",
            detail: "",
            remoteURL: "https://example.com/rules.yaml",
            path: "/tmp/escape.yaml"
        )

        XCTAssertThrowsError(try manager.targetURL(for: provider)) { error in
            XCTAssertTrue(error.localizedDescription.contains("不能使用绝对路径"))
        }
    }

    func testTargetURLRejectsSymlinkEscape() throws {
        let root = temporaryDirectory()
        let runtime = root.appendingPathComponent("Runtime", isDirectory: true)
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: runtime.appendingPathComponent("rule_providers"),
            withDestinationURL: outside
        )
        let manager = ProviderResourceManager(
            runtimeDirectory: runtime,
            backupsDirectory: root.appendingPathComponent("Backups", isDirectory: true)
        )
        let provider = ProviderItem(
            kind: "Rule",
            name: "remote",
            detail: "",
            remoteURL: "https://example.com/rules.yaml",
            path: "rule_providers/escape.yaml"
        )

        XCTAssertThrowsError(try manager.targetURL(for: provider)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Runtime 目录内"))
        }
    }

    func testBackupAndRollbackPreserveProviderVersions() throws {
        let root = temporaryDirectory()
        let manager = ProviderResourceManager(
            runtimeDirectory: root.appendingPathComponent("Runtime", isDirectory: true),
            backupsDirectory: root.appendingPathComponent("Backups", isDirectory: true)
        )
        let provider = ProviderItem(
            kind: "Rule",
            name: "remote",
            detail: "",
            remoteURL: "https://example.com/rules.yaml",
            path: "rule_providers/remote.yaml"
        )
        let target = try manager.targetURL(for: provider)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "old-version".write(to: target, atomically: true, encoding: .utf8)

        let backup = try XCTUnwrap(manager.backupExistingResource(at: target, provider: provider))
        try "new-version".write(to: target, atomically: true, encoding: .utf8)

        let rollback = try manager.rollback(provider, from: backup)

        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "old-version")
        XCTAssertEqual(rollback.target, target)
        XCTAssertEqual(rollback.restoredFrom, backup)
        let replacedBackup = try XCTUnwrap(rollback.replacedBackup)
        XCTAssertEqual(try String(contentsOf: replacedBackup, encoding: .utf8), "new-version")
    }

    func testRollbackRejectsMissingBackupWithoutChangingCurrentProvider() throws {
        let root = temporaryDirectory()
        let manager = ProviderResourceManager(
            runtimeDirectory: root.appendingPathComponent("Runtime", isDirectory: true),
            backupsDirectory: root.appendingPathComponent("Backups", isDirectory: true)
        )
        let provider = ProviderItem(
            kind: "Rule",
            name: "remote",
            detail: "",
            remoteURL: "https://example.com/rules.yaml",
            path: "rule_providers/remote.yaml"
        )
        let target = try manager.targetURL(for: provider)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "current-version".write(to: target, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try manager.rollback(
            provider,
            from: root.appendingPathComponent("Backups/missing.yaml")
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("回滚文件不存在"))
        }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "current-version")
    }

    @MainActor
    func testLatestRollbackRecordSkipsMissingBackupFiles() throws {
        let root = temporaryDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let existingBackup = root.appendingPathComponent("existing.yaml")
        try "old-version".write(to: existingBackup, atomically: true, encoding: .utf8)
        let provider = ProviderItem(
            kind: "Rule",
            name: "remote",
            detail: "",
            remoteURL: "https://example.com/rules.yaml",
            path: "rule_providers/remote.yaml"
        )
        let store = AppStore()
        store.providerUpdateHistory = [
            ProviderUpdateRecord(
                providerName: "remote",
                providerKind: "Rule",
                action: "下载",
                succeeded: true,
                targetPath: "rule_providers/remote.yaml",
                message: "newer record but backup file was pruned",
                backupPath: root.appendingPathComponent("missing.yaml").path,
                restoredFromPath: nil
            ),
            ProviderUpdateRecord(
                providerName: "remote",
                providerKind: "Rule",
                action: "下载",
                succeeded: true,
                targetPath: "rule_providers/remote.yaml",
                message: "usable backup",
                backupPath: existingBackup.path,
                restoredFromPath: nil
            ),
            ProviderUpdateRecord(
                providerName: "other",
                providerKind: "Rule",
                action: "下载",
                succeeded: true,
                targetPath: "rule_providers/other.yaml",
                message: "wrong provider",
                backupPath: existingBackup.path,
                restoredFromPath: nil
            )
        ]

        let record = try XCTUnwrap(store.latestProviderRollbackRecord(for: provider))

        XCTAssertEqual(record.backupPath, existingBackup.path)
        XCTAssertEqual(record.message, "usable backup")
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
