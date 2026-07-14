import AppKit
import SwiftUI

struct ConfigFragmentPreviewWindowView: View {
    @EnvironmentObject private var store: AppStore
    let route: ConfigFragmentPreviewRoute
    @State private var currentIndex = 0

    private let analyzer = ConfigFragmentAnalyzer()

    private var fragments: [ConfigFragment] {
        route.fragmentIDs.compactMap { id in store.configFragments.first { $0.id == id } }
    }

    private var fragment: ConfigFragment? {
        guard fragments.indices.contains(currentIndex) else { return fragments.first }
        return fragments[currentIndex]
    }

    var body: some View {
        Group {
            if let fragment {
                preview(fragment)
            } else {
                ContentUnavailableView("覆写已不存在", systemImage: "doc.text.magnifyingglass")
            }
        }
        .navigationTitle(fragment?.name ?? "覆写快速查看")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { currentIndex = max(0, currentIndex - 1) } label: {
                    Label("上一个", systemImage: "chevron.left")
                }
                .disabled(currentIndex <= 0)

                Button { currentIndex = min(fragments.count - 1, currentIndex + 1) } label: {
                    Label("下一个", systemImage: "chevron.right")
                }
                .disabled(currentIndex >= fragments.count - 1)
            }
        }
        .onChange(of: fragments.count) {
            currentIndex = min(currentIndex, max(fragments.count - 1, 0))
        }
    }

    private func preview(_ fragment: ConfigFragment) -> some View {
        let report = analyzer.analyze(fragment)
        return VStack(spacing: 0) {
            previewHeader(fragment, report: report)
            Divider()
            HSplitView {
                ConfigFragmentCodeView(fragment: fragment)
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)

                issueSidebar(report)
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 340, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func previewHeader(_ fragment: ConfigFragment, report: ConfigFragmentOverviewReport) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(fragment.name)
                        .font(.title3.weight(.semibold))
                    Text(fragment.kind.title)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
                Text(fragment.location.isEmpty ? (fragment.source == .remote ? "远程来源" : "手动创建") : fragment.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            PreviewFact(title: "状态", value: fragment.enabled ? "已启用" : "已停用")
            PreviewFact(title: "范围", value: fragment.appliesGlobally ? "全部配置" : "\(fragment.profileIDs.count) 个配置")
            PreviewFact(title: "行数", value: "\(report.lineCount)")
            PreviewFact(title: "大小", value: Formatters.bytes(Int64(report.byteCount)))
        }
        .padding(16)
    }

    private func issueSidebar(_ report: ConfigFragmentOverviewReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label(report.statusTitle, systemImage: report.errorCount > 0 ? "xmark.octagon.fill" : (report.warningCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"))
                    .font(.headline)
                    .foregroundStyle(report.errorCount > 0 ? .red : (report.warningCount > 0 ? .orange : .green))

                if report.issues.isEmpty {
                    Text("未发现 YAML/JavaScript 语法或结构问题。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(report.issues) { issue in
                        ConfigFragmentAnalysisIssueRow(issue: issue)
                    }
                }

                if report.topLevelKeys.isEmpty == false {
                    Divider()
                    Text("顶层键")
                        .font(.headline)
                    Text(report.topLevelKeys.joined(separator: "、"))
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(MihomoUI.cardFill)
    }
}

struct ConfigFragmentCodeView: View {
    let fragment: ConfigFragment

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            HStack(alignment: .top, spacing: 12) {
                Text(lineNumbers)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.disabled)

                Divider()

                Text(highlightedSource)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(14)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityLabel("\(fragment.name) 覆写代码")
    }

    private var lineNumbers: String {
        let count = max(fragment.content.components(separatedBy: .newlines).count, 1)
        return (1...count).map(String.init).joined(separator: "\n")
    }

    private var highlightedSource: AttributedString {
        let source = fragment.content
        let attributed = NSMutableAttributedString(
            string: source,
            attributes: [.foregroundColor: NSColor.labelColor]
        )
        let patterns: [(String, NSColor)]
        switch fragment.kind {
        case .yaml:
            patterns = [
                (#"(?m)^\s*[^#\s][^:\n]*:(?=\s|$)"#, .systemBlue),
                (#"(?m)#.*$"#, .secondaryLabelColor),
                (#"(?:\"(?:\\.|[^\"])*\"|'[^']*')"#, .systemOrange),
                (#"\b(?:true|false|null|yes|no)\b"#, .systemPurple)
            ]
        case .javascript:
            patterns = [
                (#"\b(?:function|return|const|let|var|if|else|for|while|async|await|throw|try|catch|new)\b"#, .systemPurple),
                (#"(?:\"(?:\\.|[^\"])*\"|'(?:\\.|[^'])*'|`(?:\\.|[^`])*`)"#, .systemOrange),
                (#"(?m)//.*$|/\*[\s\S]*?\*/"#, .secondaryLabelColor)
            ]
        }
        let whole = NSRange(location: 0, length: attributed.length)
        for (pattern, color) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in expression.matches(in: source, range: whole) {
                attributed.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
        return AttributedString(attributed)
    }
}

struct ConfigFragmentAnalysisIssueRow: View {
    let issue: ConfigFragmentAnalysisIssue

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                if let location = issue.locationText {
                    Text(location)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(color)
                }
                Text(issue.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
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
}

private struct PreviewFact: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
    }
}
