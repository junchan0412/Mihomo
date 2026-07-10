import XCTest
@testable import Mihomo

final class SettingsPresentationTests: XCTestCase {
    func testBasicSettingsTabsDoNotDuplicateAdvancedSection() {
        let titles = SettingsTab.allCases.map(\.title)

        XCTAssertEqual(titles, ["核心", "Controller", "网络", "常驻"])
        XCTAssertFalse(titles.contains("高级"))
        XCTAssertFalse(AppSection.allCases.map(\.title).contains("设置"))
        XCTAssertTrue(AppSection.allCases.map(\.title).contains("高级工具"))
    }
}
