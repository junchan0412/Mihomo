import XCTest
@testable import Mihomo

final class RuleTablePresentationTests: XCTestCase {
    func testPresentationParsesCountsFiltersAndSelectsRulesInOneSnapshot() {
        let domain = RuleItem(
            index: 1,
            content: "DOMAIN-SUFFIX,example.com,DIRECT",
            disabled: false,
            hitCount: 3
        )
        let ip = RuleItem(
            index: 2,
            content: "IP-CIDR,10.0.0.0/8,PROXY,no-resolve",
            disabled: true,
            hitCount: 5
        )
        let match = RuleItem(
            index: 3,
            content: "MATCH,DIRECT",
            disabled: false,
            hitCount: 7
        )

        let presentation = RuleTablePresentation.make(
            rules: [domain, ip, match],
            selectedCategory: .domain,
            searchText: "example"
        )

        XCTAssertEqual(presentation.entries.count, 3)
        XCTAssertEqual(presentation.filteredEntries.map(\.id), [domain.id])
        XCTAssertEqual(presentation.categoryCounts.map(\.0), [.domain, .ip, .match])
        XCTAssertEqual(presentation.categoryCounts.map(\.1), [1, 1, 1])
        XCTAssertEqual(presentation.hitTotal, 15)
        XCTAssertEqual(
            presentation.selectedEntries(for: [domain.id, match.id]).map(\.id),
            [domain.id, match.id]
        )
        XCTAssertEqual(presentation.selectedEntry(for: [ip.id])?.id, ip.id)
    }

    func testRuleEditorDraftNormalizesFieldsAndOptions() throws {
        let draft = RuleEditorDraft(
            type: "IP-CIDR",
            value: " 10.0.0.0/8 ",
            policy: " PROXY ",
            optionsText: " no-resolve,  src  \n,"
        )

        let rule = try XCTUnwrap(draft.makeRule(index: 8))

        XCTAssertEqual(rule.index, 8)
        XCTAssertEqual(rule.type, "IP-CIDR")
        XCTAssertEqual(rule.payload, "10.0.0.0/8")
        XCTAssertEqual(rule.target, "PROXY")
        XCTAssertEqual(rule.options, ["no-resolve", "src"])
    }

    func testMatchDraftClearsPayloadAndRejectsEmptyPolicy() throws {
        let match = RuleEditorDraft(type: "MATCH", value: "ignored", policy: "DIRECT")
        XCTAssertEqual(try XCTUnwrap(match.makeRule(index: 9)).payload, "")
        XCTAssertNil(RuleEditorDraft(policy: "  ").makeRule(index: 10))
    }
}
