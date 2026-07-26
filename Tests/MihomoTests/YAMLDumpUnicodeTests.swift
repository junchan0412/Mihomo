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
        XCTAssertFalse(dumped.contains("\\U0001F680"), dumped)
    }

    func testEditorTextDecodesOnlyUnicodeEscapesInsideDoubleQuotedScalars() {
        let source = #"""
        # "not a scalar: \U0001F1ED"
        filter: "^(?=.*\U0001F1ED\U0001F1F0)\\b\u6D4B"
        literal: '\U0001F1ED'
        plain: \U0001F1ED
        # \U0001F1ED
        """#

        let display = YAMLText.editorText(from: source)

        XCTAssertTrue(display.contains("🇭🇰"), display)
        XCTAssertTrue(display.contains("测"), display)
        XCTAssertTrue(display.contains(#"\\b"#), display)
        XCTAssertTrue(display.contains("'\\U0001F1ED'"), display)
        XCTAssertTrue(display.contains("plain: \\U0001F1ED"), display)
        XCTAssertTrue(display.contains("# \\U0001F1ED"), display)
        XCTAssertTrue(display.contains(#"# "not a scalar: \U0001F1ED""#), display)
    }
}
