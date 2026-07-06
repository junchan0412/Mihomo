import XCTest
@testable import Mihomo

final class ProfileYAMLStructureEditorTests: XCTestCase {
    func testSnapshotAndRuleUpsertPreserveEditableStructure() throws {
        let content = """
        proxies:
          - name: node-a
            type: direct
        proxy-groups:
          - name: Auto
            type: select
            proxies:
              - node-a
        rules:
          - DOMAIN-SUFFIX,example.com,Auto
        """
        let editor = ProfileYAMLStructureEditor()
        let snapshot = try editor.snapshot(content: content)

        XCTAssertEqual(snapshot.groups.map(\.name), ["Auto"])
        XCTAssertEqual(snapshot.proxyNames, ["node-a"])
        XCTAssertEqual(snapshot.rules.first?.type, "DOMAIN-SUFFIX")

        let updated = try editor.upsertRule(
            content: content,
            originalIndex: nil,
            rule: EditableProfileRule(index: 2, type: "MATCH", payload: "", target: "DIRECT", options: [])
        )
        let updatedSnapshot = try editor.snapshot(content: updated)

        XCTAssertEqual(updatedSnapshot.rules.count, 2)
        XCTAssertEqual(updatedSnapshot.rules.last?.content, "MATCH,DIRECT")
    }

    func testRuleValidatorFindsMissingPolicyAndProviderMismatch() throws {
        let snapshot = ProfileStructureSnapshot(
            groups: [EditablePolicyGroup(name: "Auto", type: "select", proxies: ["node-a"], uses: [])],
            rules: [],
            proxyNames: ["node-a"]
        )
        let providers = [
            ProviderItem(kind: "Proxy", name: "remote-rules", detail: "type: http")
        ]
        let rule = EditableProfileRule(
            index: 1,
            type: "RULE-SET",
            payload: "remote-rules",
            target: "Missing",
            options: []
        )

        let issues = ProfileQualityAnalyzer().validateRule(rule, snapshot: snapshot, providers: providers)

        XCTAssertTrue(issues.contains { $0.title == "目标策略不存在" })
        XCTAssertTrue(issues.contains { $0.title == "Provider 类型不匹配" })
    }
}
