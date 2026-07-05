import SwiftUI

struct ProfileEditorWindowView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editorName = ""
    @State private var editorContent = ""
    @State private var editorMode = "yaml"
    @State private var status = "选择配置后载入内容"

    private var profile: ProfileItem? {
        guard let id = store.profileEditorProfileID ?? store.settings.activeProfileID else {
            return store.profiles.first
        }
        return store.profiles.first { $0.id == id }
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
                        YAMLHighlightTextEditor(text: $editorContent)
                    } else {
                        ProfileStructureEditorView(content: $editorContent)
                    }

                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(16)
            }
        }
        .navigationTitle("配置编辑器")
        .onAppear(perform: loadEditor)
        .onChange(of: store.profileEditorProfileID) {
            loadEditor()
        }
        .onChange(of: store.profiles) {
            if let profile, profile.id == store.profileEditorProfileID {
                return
            }
            loadEditor()
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

    private func saveEditor() {
        guard let profile else { return }
        Task {
            await store.saveProfileEditor(
                profileID: profile.id,
                name: editorName,
                content: editorContent
            )
            status = "已保存：\(Formatters.shortDate.string(from: Date()))"
        }
    }
}
