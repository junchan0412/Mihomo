import XCTest
@testable import Mihomo

final class SettingsPresentationTests: XCTestCase {
    func testBasicSettingsTabsDoNotDuplicateAdvancedSection() {
        let titles = SettingsTab.allCases.map(\.title)

        XCTAssertEqual(titles, ["通用", "远程访问", "高级"])
        XCTAssertFalse(AppSection.allCases.map(\.title).contains("设置"))
        XCTAssertTrue(AppSection.allCases.map(\.title).contains("高级工具"))
    }

    func testActivityModulesKeepDNSAndTrafficInsideConnectionWorkspace() {
        XCTAssertEqual(ActivityModuleTab.allCases.map(\.title), ["最近的请求", "活动连接", "DNS", "流量统计"])
    }

    func testLogCategoriesOmitUnsupportedScriptType() {
        XCTAssertEqual(LogCategory.allCases.map(\.title), ["全部", "常规", "网络切换", "DHCP"])
        XCTAssertFalse(LogCategory.allCases.map(\.title).contains("脚本"))
    }

    func testNetworkWorkspaceKeepsDNSAsAFirstClassDestination() {
        XCTAssertEqual(NetworkWorkspaceTab.allCases.map(\.title), ["概览", "DNS", "恢复"])
    }

    func testExistingRulePresentationUsesEditingMode() {
        XCTAssertFalse(RuleEditorPresentation.add.isEditing)
        XCTAssertTrue(RuleEditorPresentation.edit(7).isEditing)
    }

    func testRuleOptionsAreDisplayedWithValueInsteadOfAsNote() {
        let entry = RuleTableEntry(rule: RuleItem(index: 3, content: "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve", disabled: false))

        XCTAssertEqual(entry.displayValue, "10.0.0.0/8 (no-resolve)")
        XCTAssertEqual(entry.optionsText, "no-resolve")
        XCTAssertTrue(entry.note.isEmpty)
    }

    func testConfigFragmentScopeRoundTripsAndFiltersProfiles() throws {
        let selectedID = UUID()
        let fragment = ConfigFragment(
            name: "Scoped",
            kind: .yaml,
            enabled: true,
            content: "mixed-port: 7890",
            appliesGlobally: false,
            profileIDs: [selectedID]
        )
        let decoded = try JSONDecoder().decode(ConfigFragment.self, from: JSONEncoder().encode(fragment))

        XCTAssertFalse(decoded.appliesGlobally)
        XCTAssertTrue(decoded.applies(to: selectedID))
        XCTAssertFalse(decoded.applies(to: UUID()))
    }
}
