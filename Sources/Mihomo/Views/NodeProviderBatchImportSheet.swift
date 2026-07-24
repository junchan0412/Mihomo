import SwiftUI

struct NodeProviderBatchImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    var profileID: UUID
    var save: ([NodeProvider]) -> Void

    @State private var group = "未分组"
    @State private var entries = ""
    @State private var validationMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("批量导入节点提供商")
                    .font(.title2.weight(.semibold))
                Text("每行填写“名称, URL, 标签”。名称可省略，应用会使用 URL 主机名。导入后会立即接入当前 Profile。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("统一分组", text: $group)

            TextEditor(text: $entries)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .overlay {
                    RoundedRectangle(cornerRadius: 6).stroke(.quaternary, lineWidth: 1)
                }

            if validationMessage.isEmpty == false {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("导入") { importEntries() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 620)
    }

    private func importEntries() {
        let normalizedGroup = group.trimmingCharacters(in: .whitespacesAndNewlines)
        var providers: [NodeProvider] = []
        for (index, rawLine) in entries.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.isEmpty == false else { continue }
            let parts = line.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let urlText: String
            let name: String
            let tags: [String]
            if parts.count == 1 {
                urlText = parts[0]
                name = URL(string: urlText)?.host ?? "节点提供商 \(index + 1)"
                tags = []
            } else {
                name = parts[0].isEmpty ? (URL(string: parts[1])?.host ?? "节点提供商 \(index + 1)") : parts[0]
                urlText = parts[1]
                tags = parts.count > 2
                    ? parts[2].components(separatedBy: CharacterSet(charactersIn: "|/，;；")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.isEmpty == false }
                    : []
            }
            providers.append(NodeProvider(
                name: name,
                url: urlText,
                profileIDs: [profileID],
                group: normalizedGroup.isEmpty ? "未分组" : normalizedGroup,
                tags: tags
            ))
        }

        do {
            guard providers.isEmpty == false else { throw NSError(domain: "Mihomo.BatchImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "请至少填写一条 Provider。"] ) }
            try NodeProviderStore().validate(providers)
            save(providers)
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
