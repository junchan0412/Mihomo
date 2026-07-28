import XCTest
@testable import Mihomo

final class SettingsPresentationTests: XCTestCase {
    func testSettingsArePresentedAsMainWindowDestination() {
        let titles = SettingsTab.allCases.map(\.title)

        XCTAssertEqual(titles, ["通用", "远程访问", "高级"])
        XCTAssertTrue(AppSection.allCases.map(\.title).contains("设置"))
        XCTAssertTrue(AppSection.allCases.map(\.title).contains("高级工具"))
    }

    func testActivityModulesKeepDNSAndTrafficInsideConnectionWorkspace() {
        XCTAssertEqual(ActivityModuleTab.allCases.map(\.title), ["最近的请求", "活动连接", "DNS", "流量统计"])
        XCTAssertEqual(ActivityDNSFilter.allCases.map(\.title), ["全部", "本地", "系统", "动态"])
        XCTAssertEqual(ActivityTrafficGrouping.allCases.map(\.title), ["策略", "进程", "网络适配器", "设备", "主机名"])
    }

    func testLogCategoriesOmitUnsupportedScriptType() {
        XCTAssertEqual(LogCategory.allCases.map(\.title), ["全部", "常规", "网络切换", "DHCP"])
        XCTAssertFalse(LogCategory.allCases.map(\.title).contains("脚本"))
    }

    func testNetworkWorkspaceKeepsDNSAndDomainSniffingAsFirstClassDestinations() {
        XCTAssertEqual(NetworkWorkspaceTab.allCases.map(\.title), ["概览", "DNS", "域名嗅探", "恢复"])
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

    func testOverviewTimelineAssignsMidpointBoundaryToFollowingBucket() {
        let start = Date(timeIntervalSince1970: 1_000)
        let samples = [
            TrafficSample(date: start, uploadRate: 10, downloadRate: 20),
            TrafficSample(date: start.addingTimeInterval(10), uploadRate: 20, downloadRate: 40)
        ]
        let policySamples = [
            PolicyTrafficSample(
                date: start.addingTimeInterval(4.999),
                policy: "DIRECT",
                uploadBytes: 2,
                downloadBytes: 3
            ),
            PolicyTrafficSample(
                date: start.addingTimeInterval(5),
                policy: "PROXY",
                uploadBytes: 7,
                downloadBytes: 11
            )
        ]

        let result = makeTimeline(samples: samples, policySamples: policySamples)

        XCTAssertEqual(result.bars.map(\.mix), [
            TimelineRoutingMix(directBytes: 5, proxyBytes: 0),
            TimelineRoutingMix(directBytes: 0, proxyBytes: 18)
        ])
    }

    func testOverviewTimelineAccumulatesDirectAndProxyTrafficInOnePass() {
        let date = Date(timeIntervalSince1970: 2_000)
        let samples = [TrafficSample(date: date, uploadRate: 8, downloadRate: 16)]
        let policySamples = [
            PolicyTrafficSample(date: date, policy: "直连", uploadBytes: 3, downloadBytes: 5),
            PolicyTrafficSample(date: date, policy: "日本", uploadBytes: 7, downloadBytes: 11),
            PolicyTrafficSample(date: date.addingTimeInterval(0.5), policy: "DIRECT", uploadBytes: 13, downloadBytes: 17)
        ]

        let result = makeTimeline(samples: samples, policySamples: policySamples)

        XCTAssertEqual(
            result.bars.first?.mix,
            TimelineRoutingMix(directBytes: 38, proxyBytes: 18)
        )
    }

    func testOverviewTimelineFallsBackWhenBucketHasNoPolicyTraffic() {
        let start = Date(timeIntervalSince1970: 3_000)
        let samples = [
            TrafficSample(date: start, uploadRate: 1, downloadRate: 2),
            TrafficSample(date: start.addingTimeInterval(2), uploadRate: 3, downloadRate: 4)
        ]
        let fallback = TimelineRoutingMix(directBytes: 23, proxyBytes: 29)

        let result = makeTimeline(samples: samples, fallback: fallback)

        XCTAssertEqual(result.bars.map(\.mix), [fallback, fallback])
    }

    func testOverviewTimelineKeepsSampleOrderIDsAndNormalizesHeights() {
        let start = Date(timeIntervalSince1970: 4_000)
        let samples = [
            TrafficSample(date: start, uploadRate: 10, downloadRate: 4),
            TrafficSample(date: start.addingTimeInterval(1), uploadRate: 5, downloadRate: 20),
            TrafficSample(date: start.addingTimeInterval(2), uploadRate: 0, downloadRate: 1)
        ]

        let result = makeTimeline(samples: samples)

        XCTAssertEqual(result.bars.map(\.id), samples.map(\.id))
        XCTAssertEqual(result.bars[0].height, 52, accuracy: 0.001)
        XCTAssertEqual(result.bars[1].height, 104, accuracy: 0.001)
        XCTAssertEqual(result.bars[2].height, 8, accuracy: 0.001)
        XCTAssertEqual(result.axisLabels.map(\.id), samples.map(\.id))
        XCTAssertEqual(result.axisLabels.map(\.text), ["4000", "4001", "4002"])
    }

    func testOverviewTimelineReturnsStableEmptySnapshotWithoutSamples() {
        XCTAssertEqual(makeTimeline(samples: []), .empty)
    }

    func testWorkspaceResponsibilitiesDoNotDuplicateDiagnosticsOrNetworkRepair() {
        XCTAssertEqual(AdvancedWorkspaceTab.allCases.map(\.title), ["运行工具", "Geo 数据", "备份与安全", "配置预览"])
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

    private func makeTimeline(
        samples: [TrafficSample],
        policySamples: [PolicyTrafficSample] = [],
        fallback: TimelineRoutingMix = TimelineRoutingMix(directBytes: 1, proxyBytes: 1)
    ) -> OverviewTimelineSnapshot {
        OverviewTimelinePresentation.make(
            samples: samples,
            policySamples: policySamples,
            fallbackMix: fallback,
            timeText: { String(Int($0.timeIntervalSince1970)) }
        )
    }
}
