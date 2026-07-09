import XCTest
@testable import MihomoShared

final class HelperPathPolicyTests: XCTestCase {
    func testValidateCorePathsAcceptsManagedCoreAndRuntimeConfig() throws {
        let layout = try makeLayout()

        let paths = try HelperPathPolicy.validateCorePaths(
            mihomoPath: layout.core.appendingPathComponent("mihomo").path,
            configPath: layout.runtime.appendingPathComponent("config.yaml").path,
            workDirectory: layout.runtime.path,
            logPath: layout.logs.appendingPathComponent("mihomo-core.log").path,
            appBundleURL: nil,
            userHomeDirectory: layout.home
        )

        XCTAssertEqual(paths.workDirectory, layout.runtime.path)
        XCTAssertEqual(paths.configPath, layout.runtime.appendingPathComponent("config.yaml").path)
        XCTAssertEqual(paths.logPath, layout.logs.appendingPathComponent("mihomo-core.log").path)
    }

    func testValidateCorePathsAcceptsBundledCoreFromAuthorizedAppBundle() throws {
        let layout = try makeLayout()
        let appBundle = layout.root.appendingPathComponent("Mihomo.app", isDirectory: true)
        let bundledCore = appBundle
            .appendingPathComponent("Contents/Resources/Core", isDirectory: true)
            .appendingPathComponent("mihomo")
        try FileManager.default.createDirectory(at: bundledCore.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: bundledCore.path, contents: nil)

        let paths = try HelperPathPolicy.validateCorePaths(
            mihomoPath: bundledCore.path,
            configPath: layout.runtime.appendingPathComponent("config.yaml").path,
            workDirectory: layout.runtime.path,
            logPath: layout.logs.appendingPathComponent("mihomo-core.log").path,
            appBundleURL: appBundle,
            userHomeDirectory: layout.home
        )

        XCTAssertEqual(paths.mihomoPath, bundledCore.path)
    }

    func testValidateCorePathsRejectsExternalCorePath() throws {
        let layout = try makeLayout()
        let externalCore = layout.root.appendingPathComponent("External/mihomo")
        try FileManager.default.createDirectory(at: externalCore.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: externalCore.path, contents: nil)

        XCTAssertThrowsError(try HelperPathPolicy.validateCorePaths(
            mihomoPath: externalCore.path,
            configPath: layout.runtime.appendingPathComponent("config.yaml").path,
            workDirectory: layout.runtime.path,
            logPath: layout.logs.appendingPathComponent("mihomo-core.log").path,
            appBundleURL: nil,
            userHomeDirectory: layout.home
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("App Support/Core"))
        }
    }

    func testValidateCorePathsRejectsRuntimeSymlinkEscape() throws {
        let layout = try makeLayout()
        let outside = layout.root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: layout.runtime.appendingPathComponent("link"),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(try HelperPathPolicy.validateCorePaths(
            mihomoPath: layout.core.appendingPathComponent("mihomo").path,
            configPath: layout.runtime.appendingPathComponent("link/config.yaml").path,
            workDirectory: layout.runtime.path,
            logPath: layout.logs.appendingPathComponent("mihomo-core.log").path,
            appBundleURL: nil,
            userHomeDirectory: layout.home
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("configPath"))
        }
    }

    func testValidateSnapshotPathsRejectWrongFileName() throws {
        let layout = try makeLayout()

        XCTAssertThrowsError(try HelperPathPolicy.validateProxySnapshotPath(
            layout.support.appendingPathComponent("other.json").path,
            userHomeDirectory: layout.home
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("system-proxy-snapshot.json"))
        }
    }

    func testValidateSnapshotPathsRejectDestinationSymlinkEscape() throws {
        let layout = try makeLayout()
        let outside = layout.root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: layout.support)
        try FileManager.default.createSymbolicLink(at: layout.support, withDestinationURL: outside)

        XCTAssertThrowsError(try HelperPathPolicy.validateDNSSnapshotPath(
            layout.support.appendingPathComponent("system-dns-snapshot.json").path,
            userHomeDirectory: layout.home
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("符号链接"))
        }
    }

    private func makeLayout() throws -> HelperTestLayout {
        let root = temporaryDirectory()
        let home = root.appendingPathComponent("Users/alice", isDirectory: true)
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let support = library
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Mihomo", isDirectory: true)
        let runtime = support.appendingPathComponent("Runtime", isDirectory: true)
        let core = support.appendingPathComponent("Core", isDirectory: true)
        let logs = library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Mihomo", isDirectory: true)
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: core, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try "config".write(to: runtime.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: core.appendingPathComponent("mihomo").path, contents: nil)
        return HelperTestLayout(root: root, home: home, support: support, runtime: runtime, core: core, logs: logs)
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

private struct HelperTestLayout {
    var root: URL
    var home: URL
    var support: URL
    var runtime: URL
    var core: URL
    var logs: URL
}
