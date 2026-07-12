import XCTest
@testable import Mihomo

final class SettingsPresentationTests: XCTestCase {
    func testBasicSettingsTabsDoNotDuplicateAdvancedSection() {
        let titles = SettingsTab.allCases.map(\.title)

        XCTAssertEqual(titles, ["通用", "远程访问", "高级"])
        XCTAssertTrue(AppSection.allCases.map(\.title).contains("设置"))
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

    func testMenuBarModeLettersMatchOutboundModes() {
        XCTAssertEqual(MenuBarPresentation.modeLetter(for: "rule"), "R")
        XCTAssertEqual(MenuBarPresentation.modeLetter(for: "direct"), "D")
        XCTAssertEqual(MenuBarPresentation.modeLetter(for: "global"), "G")
        XCTAssertEqual(MenuBarPresentation.modeLetter(for: "unknown"), "R")
    }

    func testTimelineRoutingMixUsesOnlyDirectAndProxySemantics() {
        let mix = TimelineRoutingMix(directBytes: 3, proxyBytes: 1)

        XCTAssertEqual(mix.directRatio, 0.75, accuracy: 0.001)
        XCTAssertEqual(mix.proxyRatio, 0.25, accuracy: 0.001)
        XCTAssertTrue(TimelineRoutingMix.isDirect(policy: "DIRECT"))
        XCTAssertTrue(TimelineRoutingMix.isDirect(policy: " 直连 "))
        XCTAssertFalse(TimelineRoutingMix.isDirect(policy: "PROXY"))
        XCTAssertFalse(TimelineRoutingMix.isDirect(policy: "新加坡"))
    }

    func testWorkspaceResponsibilitiesDoNotDuplicateDiagnosticsOrNetworkRepair() {
        XCTAssertEqual(AdvancedWorkspaceTab.allCases.map(\.title), ["运行工具", "数据与界面", "备份与安全", "配置预览"])
        XCTAssertEqual(DiagnosticWorkspaceTab.allCases.map(\.title), ["概览", "检查结果"])
        XCTAssertFalse(AdvancedWorkspaceTab.allCases.map(\.title).contains("诊断"))
        XCTAssertFalse(DiagnosticWorkspaceTab.allCases.map(\.title).contains("修复中心"))
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

    func testCachedProviderNamesSupportYAMLAndBase64Subscriptions() {
        let yaml = """
        proxies:
          - name: Tokyo
            type: direct
          - name: Singapore
            type: direct
        """
        XCTAssertEqual(ConfigFragmentStore.parseCachedProxyNames(yaml), ["Tokyo", "Singapore"])

        let links = "vless://id@example.com:443#Hong%20Kong\ntrojan://key@example.net:443#Japan"
        let encoded = Data(links.utf8).base64EncodedString()
        XCTAssertEqual(ConfigFragmentStore.parseCachedProxyNames(encoded), ["Hong Kong", "Japan"])
    }
}
