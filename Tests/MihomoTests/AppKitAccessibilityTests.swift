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
