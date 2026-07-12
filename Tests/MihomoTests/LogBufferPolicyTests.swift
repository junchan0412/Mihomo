import XCTest
@testable import Mihomo

final class LogBufferPolicyTests: XCTestCase {
    func testVisibleLogPruningKeepsRecentEntries() {
        var logs = makeLogs(count: LogBufferPolicy.visibleEntryLimit + 17)

        LogBufferPolicy.pruneVisible(&logs)

        XCTAssertEqual(logs.count, LogBufferPolicy.visibleEntryLimit)
        XCTAssertEqual(logs.first?.message, "entry-17")
        XCTAssertEqual(logs.last?.message, "entry-1216")
    }

    func testPausedBufferPruningKeepsRecentEntries() {
        var logs = makeLogs(count: LogBufferPolicy.bufferedEntryLimit + 9)

        LogBufferPolicy.pruneBuffered(&logs)

        XCTAssertEqual(logs.count, LogBufferPolicy.bufferedEntryLimit)
        XCTAssertEqual(logs.first?.message, "entry-9")
        XCTAssertEqual(logs.last?.message, "entry-1208")
    }

    private func makeLogs(count: Int) -> [LogEntry] {
        (0..<count).map { index in
            LogEntry(level: "info", message: "entry-\(index)")
        }
    }
}
