import SwiftUI

struct NodeProviderChangePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    var preview: NodeProviderChangePreview
    var apply: () -> Bool
    var cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.title)
                    .font(.title2.weight(.semibold))
                Text(summary)
                    .foregroundStyle(.secondary)
            }

            if preview.conflicts.isEmpty == false {
                conflictPane
            }

            deduplicationNotice

            if preview.changes.isEmpty == false {
                changePane
            }

            HStack {
                Spacer()
                Button("取消") {
                    cancel()
                    dismiss()
                }
                Button(confirmTitle) {
                    if apply() {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(preview.hasBlockingConflicts || preview.hasChanges == false)
            }
        }
        .padding(22)
        .frame(width: 660)
    }

    private var summary: String {
        let profileCount = Set(preview.profilePatches.map(\.profileID)).count
        let providerSummary: String
        if preview.providerDelta < 0 {
            providerSummary = "移除 \(-preview.providerDelta) 条 Provider 记录"
        } else if preview.providerDelta > 0 {
            providerSummary = "新增 \(preview.providerDelta) 条 Provider 记录"
        } else {
            providerSummary = "更新 \(preview.changes.count) 个 Provider 定义"
        }
        return "将更新 \(profileCount) 个 Profile、\(providerSummary)。应用后可在资源页单步撤销。"
    }

    private var confirmTitle: String {
        preview.conflicts.isEmpty ? "确认写入" : "确认覆盖 \(preview.conflicts.count) 项"
    }

    private var conflictPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("检测到 \(preview.conflicts.count) 个同名定义", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.headline)
            ForEach(preview.conflicts) { conflict in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(conflict.profileName) · \(conflict.providerName)")
                        .font(.callout.weight(.semibold))
                    Text("\(conflict.existingSource) 与 \(conflict.incomingSource) 的 \(conflict.differingFields.joined(separator: "、")) 不一致。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if conflict.requiresResolution {
                        Text("同一 Profile 内不能同时写入两个不同定义，请返回调整关联或名称。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    @ViewBuilder
    private var deduplicationNotice: some View {
        if preview.deduplicatedProviderCount > 0 {
            Label(
                "将自动合并 \(preview.deduplicatedProviderCount) 条同名重复记录，并以 Profile 中的定义为准。",
                systemImage: "arrow.triangle.merge"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MihomoUI.mutedFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var changePane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("写入摘要")
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(preview.changes) { change in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(change.kind.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(change.kind == .add ? .green : .blue)
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(change.profileName) · \(change.providerName)")
                                Text(change.fields.joined(separator: "、"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 7)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }
}
