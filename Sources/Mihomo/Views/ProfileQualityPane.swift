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
                .frame(maxWidth: 520, alignment: .leading)
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(report.sourceItems.enumerated()), id: \.element.id) { index, item in
                            RuntimeSourceRow(item: item)
                            if index < report.sourceItems.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
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
