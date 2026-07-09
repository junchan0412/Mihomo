import XCTest
@testable import Mihomo

final class ProviderResourceManagerTests: XCTestCase {
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

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MihomoTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
