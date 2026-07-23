import XCTest
@testable import Mihomo

final class RuleMatchKeyTests: XCTestCase {
    func testNormalizesControllerRuleTypesToConfigStyle() {
        XCTAssertEqual(RuleMatchKey.normalizeType("DomainSuffix"), "DOMAIN-SUFFIX")
        XCTAssertEqual(RuleMatchKey.normalizeType("domain-keyword"), "DOMAIN-KEYWORD")
        XCTAssertEqual(RuleMatchKey.normalizeType("RuleSet"), "RULE-SET")
        XCTAssertEqual(RuleMatchKey.normalizeType("GeoIP"), "GEOIP")
        XCTAssertEqual(RuleMatchKey.normalizeType("MATCH"), "MATCH")
    }

    func testHitKeyMatchesRuleContentAgainstConnectionMetadata() {
        let contentKey = RuleMatchKey.make(content: "DOMAIN-SUFFIX,google.com,Proxy")
        let connectionKey = RuleMatchKey.make(type: "DomainSuffix", payload: "google.com")
        XCTAssertEqual(contentKey, connectionKey)
        XCTAssertEqual(contentKey, "DOMAIN-SUFFIX,google.com")
    }

    func testMatchRuleUsesCanonicalKey() {
        XCTAssertEqual(RuleMatchKey.make(content: "MATCH,DIRECT"), "MATCH")
        XCTAssertEqual(RuleMatchKey.make(type: "Match", payload: ""), "MATCH")
    }
}
