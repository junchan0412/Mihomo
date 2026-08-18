import XCTest
@testable import Mihomo

final class MenuBarPresentationTests: XCTestCase {
    func testMenuBarSourceKeepsRequestedTopLevelOrder() throws {
        let source = try String(
            contentsOfFile: sourcePath("Sources/Mihomo/Views/MenuBarView.swift"),
            encoding: .utf8
        )

        let labels = [
            "primaryAction",
            "outboundModeMenu",
            "policyMenus",
            "maintenanceMenus",
            "managementMenus"
        ]
        assertAscending(labels, in: source)

        let management = try XCTUnwrap(section(named: "managementMenus", in: source))
        assertAscending(
            ["功能面板", "覆写列表", "更新外部资源", "切换配置", "重载配置"],
            in: management
        )
        XCTAssertFalse(management.contains("title: \"模块\""))
        XCTAssertFalse(source.contains("connectionMenus"))
    }

    func testPolicyMenuPutsDelayTestBeforeProxyChoices() throws {
        let source = try String(
            contentsOfFile: sourcePath("Sources/Mihomo/Views/MenuBarView.swift"),
            encoding: .utf8
        )
        let policy = try XCTUnwrap(section(named: "policyMenus", in: source))
        assertAscending(["Button(\"延迟测试\")", "ForEach(group.all)"], in: policy)
    }

    func testOverrideMenuUsesApplicableFragmentsAndImmediateToggle() throws {
        let source = try String(
            contentsOfFile: sourcePath("Sources/Mihomo/Views/MenuBarView.swift"),
            encoding: .utf8
        )
        let store = try String(
            contentsOfFile: sourcePath("Sources/Mihomo/Stores/AppStore+ConfigFragments.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("ForEach(applicableConfigFragments)"))
        XCTAssertTrue(source.contains("toggleConfigFragmentEnabled(fragment)"))
        XCTAssertTrue(store.contains("func toggleConfigFragmentEnabled"))
        XCTAssertTrue(store.contains("await restartCore()"))
    }

    private func assertAscending(_ terms: [String], in source: String, file: StaticString = #filePath, line: UInt = #line) {
        let positions = terms.compactMap { source.range(of: $0)?.lowerBound }
        XCTAssertEqual(positions.count, terms.count, "缺少菜单项：\(terms)", file: file, line: line)
        for pair in zip(positions, positions.dropFirst()) {
            XCTAssertLessThan(pair.0, pair.1, "菜单项顺序不正确：\(terms)", file: file, line: line)
        }
    }

    private func section(named name: String, in source: String) -> String? {
        guard let start = source.range(of: "private var \(name):")?.lowerBound else { return nil }
        let remaining = source[start...]
        guard let next = remaining.dropFirst().range(of: "    private ")?.lowerBound else { return String(remaining) }
        return String(remaining[..<next])
    }

    private func sourcePath(_ relativePath: String) -> String {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
            .path
    }
}
