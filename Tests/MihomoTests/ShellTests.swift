import XCTest
@testable import Mihomo

final class ShellTests: XCTestCase {
    /// A child process blocks in `write()` once it fills the 64 KiB pipe buffer. If the parent
    /// waits for exit before draining, both sides block forever — this hung `zip -r` on large
    /// profile directories and `mihomo -t` inside the root helper.
    func testRunDrainsLargeStdoutAndStderrWithoutDeadlocking() throws {
        let finished = expectation(description: "Shell.run returns")
        let outcome = ShellOutcomeBox()
        DispatchQueue.global().async {
            outcome.set(Result { try Shell.run("/bin/sh", ["-c", "seq 1 120000; seq 1 120000 1>&2"]) })
            finished.fulfill()
        }
        wait(for: [finished], timeout: 60)

        let result = try XCTUnwrap(outcome.value()).get()
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.split(separator: "\n").count, 120_000)
        XCTAssertEqual(result.stderr.split(separator: "\n").count, 120_000)
    }

    func testRunReportsExitStatusAndStreamsSeparately() throws {
        let result = try Shell.run("/bin/sh", ["-c", "echo out; echo err 1>&2; exit 3"])

        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "out")
        XCTAssertEqual(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines), "err")
    }

    func testRunHonoursWorkingDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MihomoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try "x".write(to: root.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)

        let result = try Shell.run("/bin/ls", [], workDirectory: root)

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("marker.txt"))
    }
}

/// Hands a `Shell.run` outcome back from a background queue without capturing a mutable local,
/// which concurrently-executing closures are not allowed to write to.
private final class ShellOutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Result<ShellResult, Error>?

    func set(_ value: Result<ShellResult, Error>) {
        lock.lock()
        defer { lock.unlock() }
        storage = value
    }

    func value() -> Result<ShellResult, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
