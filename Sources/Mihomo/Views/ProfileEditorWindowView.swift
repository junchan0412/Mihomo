import SwiftUI

struct ProfileEditorWindowView: View {
    @Environment(\.undoManager) private var undoManager
    @EnvironmentObject private var store: AppStore
    let profileID: UUID
    @State private var editorName = ""
    @State private var editorContent = ""
    @State private var editorMode = "yaml"
    @State private var status = "选择配置后载入内容"

    private var profile: ProfileItem? {
        store.profiles.first { $0.id == profileID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if profile == nil {
                ContentUnavailableView("未选择配置", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("配置名称", text: $editorName)
                        .textFieldStyle(.roundedBorder)

                    if editorMode == "yaml" {
                        YAMLHighlightTextEditor(text: $editorContent, showsLineNumbers: true)
                    } else {
                        ProfileStructureEditorView(content: $editorContent)
                    }

                    HStack {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer()
                        Text(lineCountLabel(editorContent))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(profile?.name ?? "配置编辑器")
        .onAppear(perform: loadEditor)
        .onChange(of: store.profiles) {
            guard profile == nil else { return }
            status = "配置已被删除"
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile?.name ?? "配置编辑器")
                    .font(.title3.bold())
                Text("YAML 与结构化编辑会写回源配置文件。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("编辑模式", selection: $editorMode) {
                Text("YAML").tag("yaml")
                Text("结构").tag("structure")
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .labelsHidden()

            Button {
                loadEditor()
            } label: {
                Label("重新载入", systemImage: "arrow.counterclockwise")
            }

            Button {
                saveEditor()
            } label: {
                Label("保存", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .disabled(profile == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func loadEditor() {
        guard let profile else {
            editorName = ""
            editorContent = ""
            status = "未选择配置"
            return
        }
        editorName = profile.name
        editorContent = store.profileContent(for: profile)
        status = "已载入：\(Formatters.shortDate.string(from: Date()))"
    }

    private func lineCountLabel(_ content: String) -> String {
        let lines = max(content.components(separatedBy: .newlines).count, content.isEmpty ? 0 : 1)
        return "\(lines) 行 · \(content.count) 字符"
    }

    private func saveEditor() {
        guard let profile else { return }
        Task {
            await store.saveProfileEditor(
                profileID: profile.id,
                name: editorName,
                content: editorContent,
                undoManager: undoManager
            )
            status = "已保存：\(Formatters.shortDate.string(from: Date()))"
        }
    }
}
