import SwiftUI
import Yams

struct ConfigRevisionHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let revisions: [ConfigRevision]
    let currentContent: String
    let restore: (ConfigRevision) -> Void

    @State private var selectedRevisionID: UUID?
    @State private var confirmsRestore = false

    private var selectedRevision: ConfigRevision? {
        let id = selectedRevisionID ?? revisions.first?.id
        return revisions.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("版本历史").font(.title3.weight(.semibold))
                    Text("保存前会自动创建快照；恢复当前版本前会再保留一份快照。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
            }
            .padding(18)

            Divider()

            HSplitView {
                List(selection: $selectedRevisionID) {
                    ForEach(revisions) { revision in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(revision.actionName).font(.body.weight(.medium))
                            Text(Formatters.shortDate.string(from: revision.createdAt))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(revision.id)
                    }
                }
                .frame(minWidth: 220, idealWidth: 260)

                VStack(alignment: .leading, spacing: 14) {
                    if let revision = selectedRevision {
                        RevisionDiffSummary(currentContent: currentContent, revision: revision)
                        Spacer()
                        Button("恢复此版本", role: .destructive) { confirmsRestore = true }
                            .buttonStyle(.borderedProminent)
                    } else {
                        ContentUnavailableView("没有可恢复版本", systemImage: "clock.arrow.circlepath")
                    }
                }
                .padding(18)
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 760, height: 460)
        .confirmationDialog("恢复此版本？", isPresented: $confirmsRestore, titleVisibility: .visible) {
            Button("恢复", role: .destructive) {
                if let selectedRevision { restore(selectedRevision); dismiss() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前内容会先创建一个新的可恢复快照。")
        }
    }
}

private struct RevisionDiffSummary: View {
    let currentContent: String
    let revision: ConfigRevision

    @EnvironmentObject private var store: AppStore

    private var revisionContent: String { store.revisionContent(revision) ?? "" }

    private var changedFields: [String] {
        let before = topLevelFields(in: revisionContent)
        let after = topLevelFields(in: currentContent)
        return Array(Set(before.keys).union(after.keys)).filter { before[$0] != after[$0] }.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(revision.subjectName).font(.headline)
            Text("快照时间：\(Formatters.shortDate.string(from: revision.createdAt))")
                .font(.caption).foregroundStyle(.secondary)
            Text("变更字段：\(changedFields.isEmpty ? "无" : changedFields.joined(separator: "、"))")
                .font(.callout).textSelection(.enabled)
            Divider()
            HStack(alignment: .top, spacing: 12) {
                codeColumn("当前", content: currentContent)
                codeColumn("快照", content: revisionContent)
            }
        }
    }

    private func codeColumn(_ title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView {
                Text(content.isEmpty ? "无法读取快照内容" : content)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(MihomoUI.mutedFill, in: RoundedRectangle(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func topLevelFields(in content: String) -> [String: String] {
        guard let loaded = try? Yams.load(yaml: content), let fields = loaded as? [String: Any] else { return [:] }
        return fields.reduce(into: [:]) { result, entry in
            result[entry.key] = String(describing: entry.value)
        }
    }
}
