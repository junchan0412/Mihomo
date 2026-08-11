import AppKit
import XCTest
@testable import Mihomo

final class TableSelectionTests: XCTestCase {
    func testReconciledSelectionRetainsOnlyVisibleIdentifiers() {
        let selection = TableSelection.reconciled(
            Set(["visible", "hidden"]),
            visibleIDs: ["other", "visible"]
        )

        XCTAssertEqual(selection, ["visible"])
    }

    func testReconciledSelectionUsesVisiblePreferredIdentifier() {
        let selection = TableSelection.reconciled(
            Set(["hidden"]),
            visibleIDs: ["first", "preferred"],
            preferredID: "preferred",
            selectsFirstWhenEmpty: true
        )

        XCTAssertEqual(selection, ["preferred"])
    }

    func testReconciledSelectionFallsBackToFirstVisibleIdentifier() {
        let selection = TableSelection.reconciled(
            Set<String>(),
            visibleIDs: ["first", "second"],
            preferredID: "hidden",
            selectsFirstWhenEmpty: true
        )

        XCTAssertEqual(selection, ["first"])
    }

    func testReconciledSelectionStaysEmptyWithoutFallback() {
        let selection = TableSelection.reconciled(
            Set(["hidden"]),
            visibleIDs: ["visible"]
        )

        XCTAssertTrue(selection.isEmpty)
    }

    func testUpdatedSelectionSupportsSingleCommandAndShiftClicks() {
        let ids = ["a", "b", "c", "d"]

        let single = TableSelection.updated(
            ["a", "b"],
            clicking: "c",
            visibleIDs: ids,
            anchor: "a",
            modifiers: []
        )
        XCTAssertEqual(single.selection, ["c"])
        XCTAssertEqual(single.anchor, "c")

        let toggled = TableSelection.updated(
            single.selection,
            clicking: "a",
            visibleIDs: ids,
            anchor: single.anchor,
            modifiers: [.command]
        )
        XCTAssertEqual(toggled.selection, ["a", "c"])
        XCTAssertEqual(toggled.anchor, "a")

        let ranged = TableSelection.updated(
            toggled.selection,
            clicking: "d",
            visibleIDs: ids,
            anchor: toggled.anchor,
            modifiers: [.shift]
        )
        XCTAssertEqual(ranged.selection, Set(ids))
        XCTAssertEqual(ranged.anchor, "a")
    }
}
