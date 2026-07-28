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
}
