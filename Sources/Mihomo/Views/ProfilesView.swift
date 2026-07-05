import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfilesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedProfileID: UUID?
    @State private var editorName = ""
    @State private var editorContent = ""
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            remoteSubscriptionBox

            HSplitView {
                ProfileListPane(
                    selectedProfileID: $selectedProfileID,
                    selectedProfile: selectedProfile
                )
                .environmentObject(store)
                .frame(minWidth: 520)

                ProfileEditorPane(
                    profile: selectedProfile,
                    editorName: $editorName,
                    editorContent: $editorContent,
                    reload: loadEditor,
                    save: saveEditor
                )
                .frame(minWidth: 460)
            }
        }
        .padding(24)
        .navigationTitle("配置")
        .overlay {
            DropTargetOverlay(isTargeted: isDropTargeted)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .onAppear {
            selectedProfileID = store.settings.activeProfileID ?? store.profiles.first?.id
            loadEditor()
        }
        .onChange(of: selectedProfileID) {
            loadEditor()
        }
        .onChange(of: store.profiles) {
            if selectedProfileID == nil {
                selectedProfileID = store.settings.activeProfileID ?? store.profiles.first?.id
            }
            loadEditor()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("配置")
                    .font(.largeTitle.bold())
                Text("支持本地/远程导入、拖入导入、订阅刷新和基础 YAML 编辑。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("导入本地...") {
                importLocal()
            }
        }
    }

    private var remoteSubscriptionBox: some View {
        GroupBox("远程订阅") {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("名称")
                    TextField("可选", text: $store.newRemoteName)
                }
                GridRow {
                    Text("URL")
                    TextField("https://example.com/profile.yaml", text: $store.newRemoteURL)
                }
                GridRow {
                    Text("")
                    HStack {
                        Button("导入远程订阅") {
                            Task { await store.addRemoteProfile() }
                        }
                        Button("刷新所有订阅") {
                            Task { await store.refreshAllRemoteProfiles() }
                        }
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 4)
        }
    }

    private var selectedProfile: ProfileItem? {
        guard let selectedProfileID else { return nil }
        return store.profiles.first { $0.id == selectedProfileID }
    }

    private func loadEditor() {
        guard let selectedProfile else {
            editorName = ""
            editorContent = ""
            return
        }
        editorName = selectedProfile.name
        editorContent = store.profileContent(for: selectedProfile)
    }

    private func saveEditor() {
        guard let selectedProfileID else { return }
        Task {
            await store.saveProfileEditor(
                profileID: selectedProfileID,
                name: editorName,
                content: editorContent
            )
        }
    }

    private func importLocal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.yaml, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.importLocalProfile(url: url) }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                Task { await store.importLocalProfile(url: url) }
            }
        }
        return accepted
    }
}

private struct ProfileListPane: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selectedProfileID: UUID?
    var selectedProfile: ProfileItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("启用") {
                    if let selectedProfile {
                        Task { await store.setActiveProfile(selectedProfile) }
                    }
                }
                .disabled(selectedProfile == nil)

                Button("刷新选中") {
                    if let selectedProfile {
                        Task { await store.refreshProfile(selectedProfile) }
                    }
                }
                .disabled(selectedProfile?.isRemote != true)

                Spacer()
            }

            AppKitTable(
                rows: store.profiles,
                selection: $selectedProfileID,
                columns: profileColumns
            )
            .overlay {
                if store.profiles.isEmpty {
                    ContentUnavailableView("没有配置", systemImage: "doc.text")
                }
            }
        }
    }

    private var profileColumns: [AppKitTableColumn<ProfileItem>] {
        [
            .init(title: "名称", width: 260) { profile in
                (profile.id == store.settings.activeProfileID ? "* " : "") + profile.name
            },
            .init(title: "类型", width: 90) { $0.source == .remote ? "远程" : "本地" },
            .init(title: "更新", width: 160) { Formatters.shortDate.string(from: $0.updatedAt) },
            .init(title: "用量", width: 220) { profileUsageText($0) }
        ]
    }

    private func profileUsageText(_ profile: ProfileItem) -> String {
        guard let total = profile.total else { return "-" }
        let used = (profile.uploadUsed ?? 0) + (profile.downloadUsed ?? 0)
        return "\(Formatters.bytes(used)) / \(Formatters.bytes(total))"
    }
}

private struct DropTargetOverlay: View {
    var isTargeted: Bool

    var body: some View {
        if isTargeted {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                .padding(12)
        }
    }
}

private struct ProfileEditorPane: View {
    var profile: ProfileItem?
    @Binding var editorName: String
    @Binding var editorContent: String
    var reload: () -> Void
    var save: () -> Void

    var body: some View {
        GroupBox("配置编辑器") {
            VStack(alignment: .leading, spacing: 10) {
                if profile == nil {
                    ContentUnavailableView("未选择配置", systemImage: "square.and.pencil")
                } else {
                    TextField("配置名称", text: $editorName)
                        .textFieldStyle(.roundedBorder)

                    TextEditor(text: $editorContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 420, minHeight: 340)
                        .border(Color.secondary.opacity(0.25))

                    HStack {
                        Text("保存前会更新源配置文件；启动核心时仍会先 dry-run。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("重新载入", action: reload)
                        Button("保存编辑", action: save)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private extension UTType {
    static let yaml = UTType(filenameExtension: "yaml") ?? .text
}
