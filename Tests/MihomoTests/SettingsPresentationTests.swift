import XCTest
@testable import Mihomo

final class SettingsPresentationTests: XCTestCase {
    func testBasicSettingsTabsDoNotDuplicateAdvancedSection() {
        let titles = SettingsTab.allCases.map(\.title)

        XCTAssertEqual(titles, ["通用", "远程访问", "高级"])
        XCTAssertFalse(AppSection.allCases.map(\.title).contains("设置"))
        XCTAssertTrue(AppSection.allCases.map(\.title).contains("高级工具"))
    }

    func testActivityDNSNavigatesToNetworkInsteadOfAdvancedTools() {
        XCTAssertEqual(ActivityModuleTab.dns.destinationSection, .networkSecurity)
        XCTAssertNotEqual(ActivityModuleTab.dns.destinationSection, .advanced)
    }

    func testNetworkWorkspaceKeepsDNSAsAFirstClassDestination() {
        XCTAssertEqual(NetworkWorkspaceTab.allCases.map(\.title), ["概览", "DNS", "恢复"])
    }
}
