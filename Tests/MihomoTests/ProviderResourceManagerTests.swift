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
        XCTAssertTrue(result.validationSummary.contains("校验通过"))
    }

    func testRefreshLocalRejectsHTMLErrorPageAndEmptyMapping() throws {
        let root = temporaryDirectory()
        let runtime = root.appendingPathComponent("Runtime", isDirectory: true)
        let directory = runtime.appendingPathComponent("rules", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("local.yaml")
        let manager = ProviderResourceManager(runtimeDirectory: runtime, backupsDirectory: root.appendingPathComponent("Backups"))
        let provider = ProviderItem(kind: "Rule", name: "Local", detail: "", providerType: "file", path: "rules/local.yaml")

        try "<html><body>bad gateway</body></html>".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try manager.refreshLocal(provider)) { error in
            XCTAssertTrue(error.localizedDescription.contains("HTML"))
        }

        try "{}".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try manager.refreshLocal(provider)) { error in
            XCTAssertTrue(error.localizedDescription.contains("顶层映射为空"))
        }
    }

    func testRefreshLocalExplainsHTML404SubscriptionResponse() throws {
        let root = temporaryDirectory()
        let runtime = root.appendingPathComponent("Runtime", isDirectory: true)
        let directory = runtime.appendingPathComponent("proxy_providers", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("remote.yaml")
        try "<html><body><h1>404 Not Found</h1></body></html>".write(to: file, atomically: true, encoding: .utf8)
        let manager = ProviderResourceManager(runtimeDirectory: runtime, backupsDirectory: root.appendingPathComponent("Backups"))
        let provider = ProviderItem(kind: "Node", name: "Remote", detail: "", providerType: "file", path: "proxy_providers/remote.yaml")

        XCTAssertThrowsError(try manager.refreshLocal(provider)) { error in
            XCTAssertTrue(error.localizedDescription.contains("404 Not Found"))
        }
    }

    func testRefreshLocalAcceptsBase64EncodedProxyProvider() throws {
        let root = temporaryDirectory()
        let runtime = root.appendingPathComponent("Runtime", isDirectory: true)
        let directory = runtime.appendingPathComponent("proxy_providers", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("remote.yaml")
        let content = "proxies:\n  - name: demo\n    type: socks5\n    server: 127.0.0.1\n    port: 1080\n"
        let encoded = Data(content.utf8).base64EncodedString()
        try encoded.write(to: file, atomically: true, encoding: .utf8)
        let manager = ProviderResourceManager(runtimeDirectory: runtime, backupsDirectory: root.appendingPathComponent("Backups"))
        let provider = ProviderItem(kind: "Proxy", name: "Remote", detail: "", providerType: "file", path: "proxy_providers/remote.yaml")

        let result = try manager.refreshLocal(provider)

        XCTAssertTrue(result.validationSummary.contains("1 项"))
    }

    func testRefreshLocalConvertsBase64EncodedShareLinksToProxyProvider() throws {
        let root = temporaryDirectory()
        let runtime = root.appendingPathComponent("Runtime", isDirectory: true)
        let directory = runtime.appendingPathComponent("proxy_providers", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("remote.yaml")
        let links = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmRAMTI3LjAuMC4xOjgzODg#Demo"
        try Data(links.utf8).base64EncodedString().write(to: file, atomically: true, encoding: .utf8)
        let manager = ProviderResourceManager(runtimeDirectory: runtime, backupsDirectory: root.appendingPathComponent("Backups"))
        let provider = ProviderItem(kind: "Node", name: "Remote", detail: "", providerType: "file", path: "proxy_providers/remote.yaml")

        let result = try manager.refreshLocal(provider)

        XCTAssertTrue(result.validationSummary.contains("1 项"))
        let normalized = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(normalized.contains("type: ss"))
        XCTAssertTrue(normalized.contains("server: 127.0.0.1"))
    }

    func testRefreshLocalConvertsSIP002ShadowsocksLinkWithBase64Credentials() throws {
        let root = temporaryDirectory()
        let runtime = root.appendingPathComponent("Runtime", isDirectory: true)
        let directory = runtime.appendingPathComponent("proxy_providers", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("remote.yaml")
        let links = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@127.0.0.1:8388#Demo"
        try links.write(to: file, atomically: true, encoding: .utf8)
        let manager = ProviderResourceManager(runtimeDirectory: runtime, backupsDirectory: root.appendingPathComponent("Backups"))
        let provider = ProviderItem(kind: "Proxy", name: "Remote", detail: "", providerType: "file", path: "proxy_providers/remote.yaml")

        _ = try manager.refreshLocal(provider)

        let normalized = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(normalized.contains("cipher: aes-256-gcm"))
        XCTAssertTrue(normalized.contains("password: password"))
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

    @MainActor
    func testProviderHistoryMatchingSurvivesNormalizedReloadedNames() {
        let provider = ProviderItem(kind: "Rule", name: " Remote ", detail: "")
        let store = AppStore()
        store.providerUpdateHistory = [
            ProviderUpdateRecord(
                providerName: "remote",
                providerKind: "rule",
                action: "下载",
                succeeded: true,
                targetPath: "rule_providers/remote.yaml",
                message: "ok"
            )
        ]

        XCTAssertEqual(store.providerUpdateHistory(for: provider).count, 1)
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
