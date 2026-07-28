import Foundation

enum ProfileQualityReportBuilder {
    static func make(
        issues: [ProfileQualityIssue],
        runtimeItems: [RuntimeInspectorItem],
        sourceItems: [RuntimeConfigSourceItem],
        diffLayers: [ConfigDiffLayer],
        migrationLog: [String],
        generatedConfig: String
    ) -> ProfileQualityReport {
        var seenIssues = Set<String>()
        let uniqueIssues = issues.filter { issue in
            let key = "\(issue.severity.rawValue)\u{1f}\(issue.source.rawValue)\u{1f}\(issue.title)\u{1f}\(issue.detail)"
            return seenIssues.insert(key).inserted
        }
        .sorted { severityRank($0.severity) > severityRank($1.severity) }

        let errorCount = uniqueIssues.filter { $0.severity == .error }.count
        let warningCount = uniqueIssues.filter { $0.severity == .warning }.count
        let rawScore = max(0, 100 - min(80, errorCount * 22) - min(36, warningCount * 6))
        let score = errorCount > 0 ? min(59, rawScore) : rawScore

        let headline: String
        if errorCount > 0 {
            headline = "需要修复后再启用"
        } else if warningCount == 0 {
            headline = "配置质量良好"
        } else if score >= 80 {
            headline = "有少量可优化项"
        } else {
            headline = "建议先检查配置"
        }

        return ProfileQualityReport(
            score: score,
            headline: headline,
            issues: uniqueIssues,
            runtimeItems: runtimeItems,
            sourceItems: sourceItems,
            diffLayers: diffLayers,
            migrationLog: migrationLog,
            generatedConfig: generatedConfig
        )
    }

    private static func severityRank(_ severity: ProfileQualitySeverity) -> Int {
        switch severity {
        case .error: return 3
        case .warning: return 2
        case .info: return 1
        }
    }
}
