import XCTest
@testable import Mihomo

final class YAMLDumpUnicodeTests: XCTestCase {
    func testYAMLTextDumpKeepsChineseReadable() throws {
        let map: [String: Any] = [
            "name": "测试中文",
            "node": "香港节点",
            "emoji": "🚀"
        ]
        let dumped = try YAMLText.dump(map)
        XCTAssertTrue(dumped.contains("测试中文"), dumped)
        XCTAssertTrue(dumped.contains("香港节点"), dumped)
        XCTAssertFalse(dumped.contains("\\u6d4b"), dumped)
    }
}
