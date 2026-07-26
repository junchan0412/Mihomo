import Foundation
import XCTest
@testable import Mihomo

final class ConfigRevisionDiffTests: XCTestCase {
    func testProfileDiffReportsChangedTopLevelFields() {
        let changed = ConfigRevisionDiff.changedFields(
            currentContent: "mixed-port: 7890\ndns:\n  enable: true\n",
            revisionContent: "mixed-port: 7891\nmode: rule\n",
            kind: .profile
        )

        XCTAssertEqual(changed, ["dns", "mixed-port", "mode"])
    }

    func testOverrideDiffReportsAddedDeletedAndEditedFragments() throws {
        let commonID = UUID()
        let removed = ConfigFragment(name: "旧覆写", kind: .yaml, enabled: true, content: "dns:\n  enable: true")
        let revision = [
            ConfigFragment(id: commonID, name: "DNS", kind: .yaml, enabled: true, content: "dns:\n  enable: true"),
            removed
        ]
        let current = [
            ConfigFragment(id: commonID, name: "DNS", kind: .yaml, enabled: false, content: "dns:\n  enable: false"),
            ConfigFragment(name: "新覆写", kind: .javascript, enabled: true, content: "function transform(config) { return config }")
        ]

        XCTAssertEqual(
            ConfigRevisionDiff.changedFields(
                currentContent: try encoded(current),
                revisionContent: try encoded(revision),
                kind: .overrides
            ),
            ["DNS.内容", "DNS.状态", "删除：旧覆写", "新增：新覆写"]
        )
    }

    private func encoded(_ fragments: [ConfigFragment]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(fragments), as: UTF8.self)
    }
}
