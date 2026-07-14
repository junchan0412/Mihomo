import SwiftUI

struct RemoteConfigFragmentImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @EnvironmentObject private var store: AppStore

    @State private var name = ""
    @State private var urlString = ""
    @State private var kind: ConfigFragmentKind = .yaml
    @State private var isImporting = false
    @State private var statusMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("从 URL 导入覆写")
                .font(.title3.bold())
            Text("远程覆写会保存来源 URL，之后可从覆写列表刷新。")
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    fieldLabel("名称")
                    TextField("可选", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    fieldLabel("URL")
                    TextField("https://example.com/override.yaml", text: $urlString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 430)
                }
                GridRow {
                    fieldLabel("类型")
                    Picker("类型", selection: $kind) {
                        ForEach(ConfigFragmentKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                }
            }

            if statusMessage.isEmpty == false {
                Label(statusMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    importFragment()
                } label: {
                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("导入", systemImage: "plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isImporting || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 570)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(width: 64, alignment: .trailing)
    }

    private func importFragment() {
        isImporting = true
        statusMessage = ""
        Task {
            let succeeded = await store.importRemoteConfigFragment(
                urlString: urlString,
                name: name,
                kind: kind,
                undoManager: undoManager
            )
            isImporting = false
            if succeeded {
                dismiss()
            } else {
                statusMessage = store.configFragmentImportStatus
            }
        }
    }
}

struct ConfigFragmentRefreshStrip: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 14) {
            Toggle("YAML 覆写", isOn: overrideBinding(\.yamlOverrideEnabled))
                .toggleStyle(.checkbox)
            Toggle("JS Transform", isOn: overrideBinding(\.jsOverrideEnabled))
                .toggleStyle(.checkbox)

            Divider()
                .frame(height: 18)

            Label(store.configFragmentRefreshStatus, systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if store.configFragmentRefreshFailureCount > 0 {
                Label("\(store.configFragmentRefreshFailureCount) 个失败", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
    }

    private func overrideBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { enabled in
                var updated = store.settings
                updated[keyPath: keyPath] = enabled
                Task { await store.saveSettings(updated) }
            }
        )
    }
}

struct ConfigFragmentSummaryPane: View {
    var fragment: ConfigFragment?
    var profiles: [ProfileItem]
    var editFragment: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Label(fragment?.name ?? "未选择覆写", systemImage: fragment?.kind == .javascript ? "curlybraces" : "doc.text")
                    .font(.headline)
                    .lineLimit(1)
                Button {
                    editFragment()
                } label: {
                    Label("打开编辑器", systemImage: "square.and.pencil")
                }
                .disabled(fragment == nil)
            }
            .frame(width: 140, alignment: .leading)

            if let fragment {
                ConfigFragmentFact(title: "类型", value: fragment.kind.title)
                ConfigFragmentFact(title: "状态", value: fragment.enabled ? "已启用" : "已停用")
                ConfigFragmentFact(title: "来源", value: fragment.source.title)
                ConfigFragmentFact(title: "范围", value: scopeText(fragment))
                ConfigFragmentFact(title: "行数", value: "\(lineCount(fragment.content))")
                ConfigFragmentFact(title: "大小", value: Formatters.bytes(Int64(fragment.content.lengthOfBytes(using: .utf8))))
                ConfigFragmentFact(title: "更新", value: Formatters.shortDate.string(from: fragment.updatedAt))
            } else {
                Text("选择一个覆写后查看来源、作用范围与内容摘要。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
    }

    private func scopeText(_ fragment: ConfigFragment) -> String {
        if fragment.appliesGlobally { return "全部配置" }
        let names = profiles.filter { fragment.profileIDs.contains($0.id) }.map(\.name)
        return names.isEmpty ? "未指定" : (names.count == 1 ? names[0] : "\(names.count) 个配置")
    }

    private func lineCount(_ content: String) -> Int {
        max(content.components(separatedBy: .newlines).count, 1)
    }
}

struct ConfigFragmentOverviewPane: View {
    var fragment: ConfigFragment?
    private let analyzer = ConfigFragmentAnalyzer()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("覆写概览")
                        .font(.headline)
                    Text(sourceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            if let fragment {
                let report = analyzer.analyze(fragment)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 10) {
                    OverviewMetric(title: "语法状态", value: report.statusTitle, color: statusColor(report))
                    OverviewMetric(title: "行数", value: "\(report.lineCount)")
                    OverviewMetric(title: "大小", value: Formatters.bytes(Int64(report.byteCount)))
                    OverviewMetric(
                        title: fragment.kind == .yaml ? "顶层键" : "入口函数",
                        value: fragment.kind == .yaml ? topLevelKeySummary(report) : "transform(config)"
                    )
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("问题定位")
                        .font(.callout.weight(.semibold))
                    if report.issues.isEmpty {
                        Label("未发现 YAML/JavaScript 语法或结构问题", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        ForEach(report.issues) { issue in
                            ConfigFragmentAnalysisIssueRow(issue: issue)
                        }
                    }
                }
            } else {
                ContentUnavailableView("未选择覆写", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
        .padding(14)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
    }

    private var sourceDescription: String {
        guard let fragment else { return "选择覆写后查看结构、统计与问题定位。" }
        if fragment.location.isEmpty {
            return fragment.source == .remote ? "远程来源" : "手动创建"
        }
        return fragment.location
    }

    private func statusColor(_ report: ConfigFragmentOverviewReport) -> Color {
        if report.errorCount > 0 { return .red }
        if report.warningCount > 0 { return .orange }
        return .green
    }

    private func topLevelKeySummary(_ report: ConfigFragmentOverviewReport) -> String {
        guard report.topLevelKeys.isEmpty == false else { return "无" }
        let visible = report.topLevelKeys.prefix(4).joined(separator: "、")
        return report.topLevelKeys.count > 4 ? "\(visible) 等 \(report.topLevelKeys.count) 项" : visible
    }
}

private struct OverviewMetric: View {
    var title: String
    var value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(2)
                .help(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ConfigFragmentFact: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
