import SwiftUI

struct NodeProviderEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let original: NodeProvider?
    private let save: (NodeProvider) -> Void
    private let cancel: () -> Void

    @State private var name: String
    @State private var url: String
    @State private var interval: Int
    @State private var enabled: Bool
    @State private var group: String
    @State private var tags: String
    @State private var validationMessage = ""

    init(provider: NodeProvider?, save: @escaping (NodeProvider) -> Void, cancel: @escaping () -> Void) {
        original = provider
        self.save = save
        self.cancel = cancel
        _name = State(initialValue: provider?.name ?? "")
        _url = State(initialValue: provider?.url ?? "")
        _interval = State(initialValue: provider?.interval ?? 86_400)
        _enabled = State(initialValue: provider?.enabled ?? true)
        _group = State(initialValue: provider?.group ?? "未分组")
        _tags = State(initialValue: provider?.tags.joined(separator: ", ") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(original == nil ? "添加节点提供商" : "编辑节点提供商")
                    .font(.title2.weight(.semibold))
                Text("Provider 元数据独立保存；仅在选中的 Profile 生成运行时配置时注入。")
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("名称", text: $name, prompt: Text("例如：订阅 A"))
                TextField("订阅 URL", text: $url, prompt: Text("https://example.com/subscribe"))
                TextField("分组", text: $group, prompt: Text("例如：机场订阅"))
                TextField("标签", text: $tags, prompt: Text("例如：香港, 主力"))
                Stepper(value: $interval, in: 0...604_800, step: 3_600) {
                    HStack {
                        Text("更新间隔")
                        Spacer()
                        Text(interval == 0 ? "由核心默认" : "\(interval / 3_600) 小时")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Toggle("启用此提供商", isOn: $enabled)
            }
            .formStyle(.grouped)

            if validationMessage.isEmpty == false {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") {
                    cancel()
                    dismiss()
                }
                Button("保存") { saveProvider() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private func saveProvider() {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = NodeProvider(
            id: original?.id ?? UUID(),
            name: normalizedName,
            url: normalizedURL,
            path: original?.path,
            interval: interval,
            enabled: enabled,
            profileIDs: original?.profileIDs ?? [],
            group: group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未分组" : group.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tags.components(separatedBy: CharacterSet(charactersIn: ",，\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false },
            updatedAt: original?.updatedAt ?? Date()
        )
        do {
            try NodeProviderStore().validate([provider])
            save(provider)
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

struct NodeProviderRow: View {
    var provider: NodeProvider
    var isSelected: Bool
    var toggleSelection: (Bool) -> Void
    var refresh: () -> Void
    var edit: () -> Void
    var delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("接入当前配置", isOn: Binding(get: { isSelected }, set: toggleSelection))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("接入当前配置")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(provider.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if provider.enabled == false {
                        Text("已停用")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    Text(provider.group)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text(provider.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if provider.tags.isEmpty == false {
                    Text(provider.tags.prefix(3).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(provider.interval == 0 ? "核心默认间隔" : "\(provider.interval / 3_600) 小时")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(Formatters.shortDate.string(from: provider.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 116, alignment: .trailing)

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("更新 \(provider.name)")

            Menu {
                Button("编辑", action: edit)
                Button("删除", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .help("更多操作")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
