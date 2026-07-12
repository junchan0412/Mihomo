import XCTest
@testable import Mihomo

final class FormattersTests: XCTestCase {
    func testBytesUsesCompactZeroAndByteValues() {
        XCTAssertEqual(Formatters.bytes(0), "0 B")
        XCTAssertEqual(Formatters.bytes(42), "42 B")
    }
}
