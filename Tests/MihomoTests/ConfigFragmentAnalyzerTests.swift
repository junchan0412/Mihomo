import XCTest
@testable import Mihomo

final class ConfigFragmentAnalyzerTests: XCTestCase {
    private let analyzer = ConfigFragmentAnalyzer()

    func testValidYAMLReportsTopLevelKeys() {
        let fragment = ConfigFragment(
            name: "YAML",
            kind: .yaml,
            enabled: true,
            content: "dns:\n  enable: true\nrules:\n  - MATCH,DIRECT\n"
        )

        let report = analyzer.analyze(fragment)

        XCTAssertEqual(report.errorCount, 0)
        XCTAssertEqual(report.topLevelKeys, ["dns", "rules"])
    }

    func testInvalidYAMLReportsLineAndColumn() {
        let fragment = ConfigFragment(
            name: "Broken YAML",
            kind: .yaml,
            enabled: true,
            content: "dns:\n  enable: true\n invalid\n"
        )

        let report = analyzer.analyze(fragment)

        XCTAssertGreaterThan(report.errorCount, 0)
        XCTAssertNotNil(report.issues.first?.line)
        XCTAssertNotNil(report.issues.first?.column)
    }

    func testInvalidJavaScriptReportsSyntaxLocation() {
        let fragment = ConfigFragment(
            name: "Broken JS",
            kind: .javascript,
            enabled: true,
            content: "function transform(config) {\n  return config;\n"
        )

        let report = analyzer.analyze(fragment)

        XCTAssertGreaterThan(report.errorCount, 0)
        XCTAssertNotNil(report.issues.first?.line)
    }

    func testJavaScriptRequiresTransformEntryPoint() {
        let fragment = ConfigFragment(
            name: "Missing Transform",
            kind: .javascript,
            enabled: true,
            content: "const value = 1;\n"
        )

        let report = analyzer.analyze(fragment)

        XCTAssertTrue(report.issues.contains { $0.message.contains("transform(config)") })
    }

    func testYAMLSnifferRuleReportsSemanticIssueLocation() {
        let fragment = ConfigFragment(
            name: "Sniffer",
            kind: .yaml,
            enabled: true,
            content: "sniffer:\n  skip-domain:\n    - Mijia Cloud\n"
        )

        let report = analyzer.analyze(fragment)
        let issue = report.issues.first { $0.message.contains("Mijia Cloud") }

        XCTAssertEqual(issue?.severity, .warning)
        XCTAssertEqual(issue?.line, 3)
    }
}
