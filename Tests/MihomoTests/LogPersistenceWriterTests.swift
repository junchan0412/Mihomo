import XCTest
@testable import Mihomo

final class LogPersistenceWriterTests: XCTestCase {
    func testWriterBatchesAppAndCoreLogs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MihomoLogWriter-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appLog = root.appendingPathComponent("mihomo-app.log")
        let coreLog = root.appendingPathComponent("mihomo-core.log")
        let writer = LogPersistenceWriter(
            logsDirectory: root,
            appLogFile: appLog,
            coreLogFile: coreLog,
            flushDelayNanoseconds: 60_000_000_000
        )
        let policy = LogPersistencePolicy(maxFileSizeBytes: 1_024 * 1_024, retentionDays: 7)

        await writer.enqueue(line: "app\n", isCore: false, policy: policy)
        await writer.enqueue(line: "core\n", isCore: true, policy: policy)
        await writer.flush()

        XCTAssertEqual(try String(contentsOf: appLog, encoding: .utf8), "app\ncore\n")
        XCTAssertEqual(try String(contentsOf: coreLog, encoding: .utf8), "core\n")
    }
}
