import SwiftUI

struct ProfileQualityPane: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var report: ProfileQualityReport
    @State private var section: ProfileQualitySection = .overview

    private var summaryText: String {
        let changedLayers = report.diffLayers.filter(\.changed).count
        return "\(report.issues.count) 个问题 · \(report.runtimeItems.count) 个运行项 · \(report.sourceItems.count) 个字段 · \(changedLayers) 层变化"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            qualityHeader

            VStack(spacing: 0) {
                Picker("配置质量内容", selection: $section) {
                    ForEach(ProfileQualitySection.allCases) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 520)
                .padding(12)

                Divider()

                Group {
                    switch section {
                    case .overview:
                        overviewContent
                    case .sources:
                        sourceContent
                    case .layers:
                        layerContent
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(minHeight: 250, alignment: .topLeading)
                .transition(.opacity)
            }
            .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(reduceMotion ? nil : MihomoUI.Motion.quick, value: section)
        }
        .padding(16)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
    }

    private var qualityHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.16), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat(report.score) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(report.score)")
                    .font(.title.weight(.bold))
                    .monospacedDigit()
            }
            .frame(width: 68, height: 68)
            .accessibilityLabel("配置质量评分")
            .accessibilityValue("\(report.score) 分")

            VStack(alignment: .leading, spacing: 5) {
                Text(report.headline)
                    .font(.title3.weight(.semibold))
                Text(summaryText)
                    .font(MihomoUI.Fonts.body)
                    .foregroundStyle(.secondary)
                Text("配置中的字段优先于应用内设置；应用设置仅作为未声明字段的默认值。")
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .help("最终优先级从高到低：YAML 覆写、JS Transform、Profile 配置、应用默认。禁用某一覆写层后，将自动回退到下一层。")
            }

            Spacer()

            if let migration = report.migrationLog.last {
                Label(migration, systemImage: "checkmark.seal")
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            QualityPanel(title: "需要关注", systemImage: "exclamationmark.triangle") {
                if report.issues.isEmpty {
                    Label("未发现阻断项", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(report.issues.prefix(5)) { issue in
                        ProfileQualityIssueRow(issue: issue)
                    }
                }
            }

            QualityPanel(title: "运行时摘要", systemImage: "stethoscope") {
                if report.runtimeItems.isEmpty {
                    Text("暂无运行时检查项")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], alignment: .leading, spacing: 12) {
                        ForEach(report.runtimeItems.prefix(9)) { item in
                            RuntimeInspectorCell(item: item)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var sourceContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label("YAML 覆写 > JS Transform > Profile 配置 > 应用默认", systemImage: "arrow.down.to.line.compact")
                    .font(MihomoUI.Fonts.bodyMedium)
                Spacer()
                Text("\(report.sourceItems.filter(\.usesAppDefault).count) 个字段使用应用默认")
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            if report.sourceItems.isEmpty {
                ContentUnavailableView("没有字段来源", systemImage: "point.3.connected.trianglepath.dotted")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ForEach(Array(report.sourceItems.enumerated()), id: \.element.id) { index, item in
                    RuntimeSourceRow(item: item)
                    if index < report.sourceItems.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var layerContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("从应用默认开始，后续每一层都可以覆盖前一层的同名字段。")
                .font(MihomoUI.Fonts.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(Array(report.diffLayers.enumerated()), id: \.element.id) { index, layer in
                    ConfigLayerCard(layer: layer, priority: index + 1)
                    if index < report.diffLayers.count - 1 {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var scoreColor: Color {
        if report.score >= 90 { return .green }
        if report.score >= 70 { return .orange }
        return .red
    }
}

private enum ProfileQualitySection: String, CaseIterable, Identifiable {
    case overview
    case sources
    case layers

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "质量总览"
        case .sources: return "字段来源"
        case .layers: return "合并层级"
        }
    }
    var systemImage: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .sources: return "point.3.connected.trianglepath.dotted"
        case .layers: return "square.stack.3d.up"
        }
    }
}

private struct QualityPanel<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: () -> Content

    init(title: String, systemImage: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(MihomoUI.Fonts.bodyMedium)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ProfileQualityIssueRow: View {
    var issue: ProfileQualityIssue

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(issue.title)
                        .font(MihomoUI.Fonts.bodyMedium)
                    Text(issue.source.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(sourceColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(sourceColor.opacity(0.12), in: Capsule())
                }
                Text(issue.detail)
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var icon: String {
        switch issue.severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch issue.severity {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var sourceColor: Color {
        switch issue.source {
        case .profile: return .blue
        case .appSettings: return .purple
        case .override: return .orange
        case .runtime: return .secondary
        }
    }
}

private struct RuntimeInspectorCell: View {
    var item: RuntimeInspectorItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(item.value)
                    .font(MihomoUI.Fonts.bodyMedium)
                    .lineLimit(1)
            }
            Text(item.detail)
                .font(MihomoUI.Fonts.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .help(item.detail)
        }
    }
}

private struct RuntimeSourceRow: View {
    var item: RuntimeConfigSourceItem

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullWidthRow
            compactRow
        }
        .padding(.vertical, 8)
    }

    private var fullWidthRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(item.path)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .frame(minWidth: 130, idealWidth: 150, maxWidth: 190, alignment: .leading)
                .lineLimit(1)
                .layoutPriority(1)

            Text(item.source)
                .font(MihomoUI.Fonts.caption)
                .foregroundStyle(sourceColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(sourceColor.opacity(0.12), in: Capsule())
                .frame(width: 112, alignment: .leading)

            Text(item.value)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 160, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            Text(shortDetail)
                .font(MihomoUI.Fonts.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 140, idealWidth: 220, maxWidth: 360, alignment: .leading)
                .help(item.detail)

            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .help(item.detail)
                .accessibilityLabel("字段说明")
                .accessibilityValue(item.detail)
        }
    }

    private var compactRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(item.path)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .lineLimit(1)

                Text(item.source)
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(sourceColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(sourceColor.opacity(0.12), in: Capsule())

                Spacer(minLength: 0)

                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .help(item.detail)
                    .accessibilityLabel("字段说明")
                    .accessibilityValue(item.detail)
            }

            Text(item.value)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)

            Text(shortDetail)
                .font(MihomoUI.Fonts.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .help(item.detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shortDetail: String {
        item.detail.components(separatedBy: "；").first ?? item.detail
    }

    private var sourceColor: Color {
        switch item.source {
        case "YAML 覆写": return .purple
        case "JS Transform": return .orange
        case "Profile 配置": return .blue
        case "应用默认": return .secondary
        default: return .green
        }
    }
}

private struct ConfigLayerCard: View {
    var layer: ConfigDiffLayer
    var priority: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(priority)")
                    .font(.caption.bold())
                    .frame(width: 22, height: 22)
                    .background(layer.changed ? Color.accentColor : Color.secondary.opacity(0.18), in: Circle())
                    .foregroundStyle(layer.changed ? Color.white : Color.secondary)
                Text(layer.name)
                    .font(MihomoUI.Fonts.bodyMedium)
            }
            Text(layer.summary.isEmpty ? "未参与" : layer.summary)
                .font(MihomoUI.Fonts.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .padding(10)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
