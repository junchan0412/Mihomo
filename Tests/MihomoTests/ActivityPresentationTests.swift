import XCTest
@testable import Mihomo

final class ActivityPresentationTests: XCTestCase {
    func testConnectionIDUsesSequenceNumber() {
        let row = ConnectionTableRow(connection: connection(id: "12345678-abcdef"), sequence: 3)

        XCTAssertEqual(row.idText, "#3")
    }

    func testConnectionTableRowsSortByNewestConnectionAndKeepActivityState() {
        var older = connection(id: "older")
        older.start = Date(timeIntervalSinceReferenceDate: 100)
        var newer = connection(id: "newer")
        newer.start = Date(timeIntervalSinceReferenceDate: 200)

        let rows = ActivityConnectionTableRows.make(
            from: [older, newer],
            activeConnectionIDs: ["newer"]
        )

        XCTAssertEqual(rows.map(\.id), ["newer", "older"])
        XCTAssertEqual(rows.map(\.sequence), [1, 2])
        XCTAssertTrue(rows[0].isActive)
        XCTAssertFalse(rows[1].isActive)
    }

    func testLogPresentationSplitsTitleAndDetail() {
        let row = LogPresentationRow(entry: LogEntry(level: "info", message: "系统代理已开启：端口 7890"))

        XCTAssertEqual(row.category, .network)
        XCTAssertEqual(row.title, "系统代理已开启")
        XCTAssertEqual(row.detail, "端口 7890")
    }

    func testLogPresentationRowsKeepNewestEntryFirst() {
        let older = LogEntry(level: "info", message: "older")
        let newer = LogEntry(level: "warning", message: "newer")

        let rows = LogPresentationRows.make(from: [older, newer])

        XCTAssertEqual(rows.map(\.id), [newer.id, older.id])
    }

    func testLogPresentationRowsFilterByCategoryAndSearch() {
        let rows = LogPresentationRows.make(from: [
            LogEntry(level: "info", message: "常规事件"),
            LogEntry(level: "warning", message: "系统代理已切换：端口 7890")
        ])

        XCTAssertEqual(
            LogPresentationRows.filter(rows, category: .network, query: "7890").map(\.title),
            ["系统代理已切换"]
        )
        XCTAssertTrue(LogPresentationRows.filter(rows, category: .general, query: "7890").isEmpty)
    }

    func testTrafficPresentationAggregatesAllWindowsInOneSamplePass() {
        let now = Date(timeIntervalSince1970: 18 * 60 * 60)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let samples = [
            trafficSample(date: now.addingTimeInterval(-2 * 60), policy: "A", upload: 1, download: 2),
            trafficSample(date: now.addingTimeInterval(-10 * 60), policy: "A", upload: 3, download: 4),
            trafficSample(date: now.addingTimeInterval(-2 * 60 * 60), policy: "B", upload: 5, download: 6),
            trafficSample(date: now.addingTimeInterval(-13 * 60 * 60), policy: "C", upload: 7, download: 8),
            trafficSample(date: now.addingTimeInterval(-19 * 60 * 60), policy: "Outside", upload: 9, download: 10)
        ]

        let rows = ActivityTrafficPresentation.rows(
            samples: samples,
            grouping: .policy,
            searchText: "",
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(rows.map(\.name), ["C", "B", "A"])
        XCTAssertEqual(rows[2].value(for: .fiveMinutes), ActivityTrafficValue(upload: 1, download: 2))
        XCTAssertEqual(rows[2].value(for: .fifteenMinutes), ActivityTrafficValue(upload: 4, download: 6))
        XCTAssertEqual(rows[1].value(for: .sixtyMinutes), ActivityTrafficValue())
        XCTAssertEqual(rows[1].value(for: .sixHours), ActivityTrafficValue(upload: 5, download: 6))
        XCTAssertEqual(rows[0].value(for: .today), ActivityTrafficValue(upload: 7, download: 8))
        XCTAssertEqual(rows[0].value(for: .twelveHours), ActivityTrafficValue())
    }

    func testTrafficPresentationFiltersGroupingAndUsesStableTieOrder() {
        let now = Date(timeIntervalSince1970: 20_000)
        let samples = [
            PolicyTrafficSample(date: now, policy: "DIRECT", process: "Beta", uploadBytes: 2, downloadBytes: 3),
            PolicyTrafficSample(date: now, policy: "PROXY", process: "Alpha", uploadBytes: 1, downloadBytes: 4)
        ]

        let allRows = ActivityTrafficPresentation.rows(
            samples: samples,
            grouping: .process,
            searchText: "",
            now: now
        )
        let filteredRows = ActivityTrafficPresentation.rows(
            samples: samples,
            grouping: .process,
            searchText: "be",
            now: now
        )

        XCTAssertEqual(allRows.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(filteredRows.map(\.name), ["Beta"])
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

    private func trafficSample(
        date: Date,
        policy: String,
        upload: Int64,
        download: Int64
    ) -> PolicyTrafficSample {
        PolicyTrafficSample(
            date: date,
            policy: policy,
            uploadBytes: upload,
            downloadBytes: download
        )
    }
}
