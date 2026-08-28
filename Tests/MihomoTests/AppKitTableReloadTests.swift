import AppKit
import SwiftUI
import XCTest
@testable import Mihomo

@MainActor
final class AppKitTableReloadTests: XCTestCase {
    private struct Row: Identifiable, Hashable {
        var id: String
        var value: String
    }

    func testReloadsOnlyRowsThatChangedWhenIdentifiersAreStable() {
        var table = makeTable(rows: [Row(id: "a", value: "1"), Row(id: "b", value: "2")])
        let coordinator = table.makeCoordinator()
        let tableView = RecordingTableView()
        tableView.dataSource = coordinator
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c0")))

        coordinator.reloadDataIfNeeded(on: tableView)
        XCTAssertEqual(tableView.fullReloadCount, 1, "首次加载应整表刷新")

        coordinator.reloadDataIfNeeded(on: tableView)
        XCTAssertEqual(tableView.fullReloadCount, 1, "行未变化时不应再刷新")
        XCTAssertTrue(tableView.partialReloads.isEmpty)

        table.rows = [Row(id: "a", value: "1"), Row(id: "b", value: "9")]
        coordinator.parent = table
        coordinator.reloadDataIfNeeded(on: tableView)

        XCTAssertEqual(tableView.fullReloadCount, 1, "ID 稳定时应做局部刷新而非整表重载")
        XCTAssertEqual(tableView.partialReloads, [IndexSet(integer: 1)])
    }

    func testFallsBackToFullReloadWhenIdentifiersChange() {
        var table = makeTable(rows: [Row(id: "a", value: "1"), Row(id: "b", value: "2")])
        let coordinator = table.makeCoordinator()
        let tableView = RecordingTableView()
        tableView.dataSource = coordinator
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c0")))
        coordinator.reloadDataIfNeeded(on: tableView)

        table.rows = [Row(id: "a", value: "1")]
        coordinator.parent = table
        coordinator.reloadDataIfNeeded(on: tableView)

        XCTAssertEqual(tableView.fullReloadCount, 2)
        XCTAssertTrue(tableView.partialReloads.isEmpty)
    }

    private func makeTable(rows: [Row]) -> AppKitTable<Row> {
        AppKitTable(
            rows: rows,
            selection: .constant(Set<String>()),
            columns: [AppKitTableColumn(title: "值", width: 100) { $0.value }]
        )
    }
}

private final class RecordingTableView: NSTableView {
    var fullReloadCount = 0
    var partialReloads: [IndexSet] = []

    override func reloadData() {
        fullReloadCount += 1
        super.reloadData()
    }

    override func reloadData(forRowIndexes rowIndexes: IndexSet, columnIndexes: IndexSet) {
        partialReloads.append(rowIndexes)
        super.reloadData(forRowIndexes: rowIndexes, columnIndexes: columnIndexes)
    }
}
