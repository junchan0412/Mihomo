import AppKit
import SwiftUI

struct ProfileQualityPane: View {
    var report: ProfileQualityReport
    @State private var selectedSourceID: String?

    private var topIssues: [ProfileQualityIssue] {
        Array(report.issues.prefix(3))
    }

    private var runtimeItems: [RuntimeInspectorItem] {
        Array(report.runtimeItems.prefix(6))
    }

    private var diffLayers: [ConfigDiffLayer] {
        Array(report.diffLayers.prefix(5))
    }

    private var sourceItems: [RuntimeConfigSourceItem] {
        Array(report.sourceItems.prefix(18))
    }

    private var summaryText: String {
        let changedLayers = report.diffLayers.filter(\.changed).count
        return "\(report.issues.count) 个问题 · \(report.runtimeItems.count) 个运行项 · \(report.sourceItems.count) 个字段来源 · \(changedLayers) 层变化"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(report.score)")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(scoreColor)
                        .monospacedDigit()
                    Text("配置质量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 76, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(report.headline)
                        .font(.headline)
                        .lineLimit(1)
                    Text(summaryText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let migration = report.migrationLog.last {
                    Text(migration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: 260, alignment: .trailing)
                }
            }

            Divider()

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3),
                alignment: .leading,
                spacing: 16
            ) {
                VStack(alignment: .leading, spacing: 7) {
                    ProfileQualityColumnTitle(title: "问题", systemImage: "exclamationmark.triangle")
                    if topIssues.isEmpty {
                        Label("未发现阻断项", systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                    } else {
                        ForEach(topIssues) { issue in
                            ProfileQualityIssueRow(
                                issue: issue,
                                icon: icon(for: issue.severity),
                                color: color(for: issue.severity)
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 7) {
                    ProfileQualityColumnTitle(title: "Runtime Inspector", systemImage: "stethoscope")
                    if runtimeItems.isEmpty {
                        Text("暂无运行时检查项")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(runtimeItems) { item in
                            RuntimeInspectorCell(item: item)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 7) {
                    ProfileQualityColumnTitle(title: "分层 Diff", systemImage: "square.stack.3d.up")
                    if diffLayers.isEmpty {
                        Text("暂无分层差异")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(diffLayers) { layer in
                            ConfigDiffLayerRow(layer: layer)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if sourceItems.isEmpty == false {
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        ProfileQualityColumnTitle(title: "字段来源", systemImage: "point.3.connected.trianglepath.dotted")
                        Spacer()
                        Text("\(report.sourceItems.filter(\.isAppManaged).count) 个 App 接管字段")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    AppKitTable(
                        rows: sourceItems,
                        selection: $selectedSourceID,
                        columns: [
                            .init(title: "字段", width: 145, textColor: sourceTextColor) { $0.path },
                            .init(title: "来源", width: 100, textColor: sourceTextColor) { $0.source },
                            .init(title: "值", width: 110, textColor: sourceTextColor) { $0.value },
                            .init(title: "说明", width: 410, textColor: sourceTextColor) { $0.detail }
                        ],
                        hasHorizontalScroller: true,
                        allowsParentScrollPassthrough: true
                    )
                    .frame(height: sourceTableHeight)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
    }

    private var scoreColor: Color {
        if report.score >= 90 { return .green }
        if report.score >= 70 { return .orange }
        return .red
    }

    private func icon(for severity: ProfileQualitySeverity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func color(for severity: ProfileQualitySeverity) -> Color {
        switch severity {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var sourceTableHeight: CGFloat {
        let rows = max(sourceItems.count, 1)
        return min(210, max(92, 30 + CGFloat(rows) * 28))
    }

    private func sourceTextColor(_ item: RuntimeConfigSourceItem) -> NSColor? {
        item.isAppManaged ? .systemBlue : nil
    }
}

private struct ProfileQualityColumnTitle: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct ProfileQualityIssueRow: View {
    var issue: ProfileQualityIssue
    var icon: String
    var color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(issue.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(issue.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct RuntimeInspectorCell: View {
    var item: RuntimeInspectorItem

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(item.value)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if item.detail.isEmpty == false {
                Text(item.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConfigDiffLayerRow: View {
    var layer: ConfigDiffLayer

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(layer.changed ? Color.accentColor : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
            Text(layer.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Text(layer.summary.isEmpty ? "-" : layer.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
