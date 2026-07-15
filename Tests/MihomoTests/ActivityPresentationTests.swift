import XCTest
@testable import Mihomo

final class ActivityPresentationTests: XCTestCase {
    func testConnectionIDUsesSequenceNumber() {
        let row = ConnectionTableRow(connection: connection(id: "12345678-abcdef"), sequence: 3)

        XCTAssertEqual(row.idText, "#3")
    }

    func testLogPresentationSplitsTitleAndDetail() {
        let row = LogPresentationRow(entry: LogEntry(level: "info", message: "系统代理已开启：端口 7890"))

        XCTAssertEqual(row.category, .network)
        XCTAssertEqual(row.title, "系统代理已开启")
        XCTAssertEqual(row.detail, "端口 7890")
    }

    private func connection(id: String) -> ConnectionItem {
        ConnectionItem(
            id: id,
            host: "example.com",
            process: "Safari",
            network: "tcp",
            rule: "MATCH",
            chain: "DIRECT",
            upload: 0,
            download: 0
        )
    }
}
