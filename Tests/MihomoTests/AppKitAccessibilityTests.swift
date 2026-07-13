import AppKit
import XCTest
@testable import Mihomo

final class AppKitAccessibilityTests: XCTestCase {
    func testTableExposesTableRoleAndActivatesSelectedRowWithReturn() {
        let tableView = AppKitAccessibleTableView()
        let dataSource = OneRowDataSource()
        tableView.dataSource = dataSource
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.setAccessibilityLabel("数据表：名称")

        var activationCount = 0
        tableView.onActivateSelection = { activationCount += 1 }
        tableView.keyDown(with: keyEvent(characters: "\r", keyCode: 36))

        XCTAssertEqual(tableView.accessibilityRole(), .table)
        XCTAssertEqual(tableView.accessibilityLabel(), "数据表：名称")
        XCTAssertEqual(activationCount, 1)
    }

    func testLogTextViewIsLabeledSelectableTextArea() {
        let textView = NSTextView()
        AppKitLogView.configure(textView)

        XCTAssertEqual(textView.accessibilityRole(), .textArea)
        XCTAssertEqual(textView.accessibilityLabel(), "应用日志")
        XCTAssertTrue(textView.isSelectable)
        XCTAssertFalse(textView.isEditable)
    }

    func testTableSupportsMultiSelectionPreviewAndDeleteKeys() {
        let tableView = AppKitAccessibleTableView()
        let dataSource = TwoRowDataSource()
        tableView.dataSource = dataSource
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        tableView.allowsMultipleSelection = true
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)

        var previewCount = 0
        var deleteCount = 0
        tableView.onPreviewSelection = { previewCount += 1 }
        tableView.onDeleteSelection = { deleteCount += 1 }

        tableView.keyDown(with: keyEvent(characters: " ", keyCode: 49))
        tableView.keyDown(with: keyEvent(characters: "\u{8}", keyCode: 51))

        XCTAssertEqual(tableView.selectedRowIndexes, IndexSet([0, 1]))
        XCTAssertEqual(previewCount, 1)
        XCTAssertEqual(deleteCount, 1)
    }

    private func keyEvent(characters: String, keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}

private final class OneRowDataSource: NSObject, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { 1 }
}

private final class TwoRowDataSource: NSObject, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { 2 }
}
