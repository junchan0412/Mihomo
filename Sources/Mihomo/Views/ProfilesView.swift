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
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 12) {
                remoteSubscriptionBar
                ProfileRefreshQueueStrip()
                    .environmentObject(store)

                HSplitView {
                    ProfileListPane(
                        selectedProfileID: $selectedProfileID,
                        selectedProfile: selectedProfile
                    )
                    .environmentObject(store)
                    .frame(minWidth: 320, idealWidth: 430)

                    ProfileEditorPane(
                        profile: selectedProfile,
                        editorName: $editorName,
                        editorContent: $editorContent,
                        reload: loadEditor,
                        save: saveEditor
                    )
                    .frame(minWidth: 360, idealWidth: 520)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(16)
        }
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("配置")
                    .font(.title2.bold())
                Text("本地、远程订阅、拖入导入和 YAML 编辑。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                importLocal()
            } label: {
                Label("导入本地", systemImage: "square.and.arrow.down")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var remoteSubscriptionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("远程订阅")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("名称")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    TextField("可选", text: $store.newRemoteName)
                }
                GridRow {
                    Text("URL")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    HStack {
                        TextField("https://example.com/profile.yaml", text: $store.newRemoteURL)
                        Button {
                            Task { await store.addRemoteProfile() }
                        } label: {
                            Label("导入", systemImage: "plus")
                        }
                        Button {
                            Task { await store.refreshAllRemoteProfiles() }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
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

private struct ProfileRefreshQueueStrip: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 10) {
            Label(store.profileAutoRefreshStatus, systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if store.profileRefreshFailureCount > 0 {
                Label("\(store.profileRefreshFailureCount) 个失败", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Spacer()

            if let job = store.profileRefreshQueue.first {
                Text("\(job.profileName)：\(job.state.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProfileListPane: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selectedProfileID: UUID?
    var selectedProfile: ProfileItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    if let selectedProfile {
                        Task { await store.setActiveProfile(selectedProfile) }
                    }
                } label: {
                    Label("启用", systemImage: "checkmark.circle")
                }
                .disabled(selectedProfile == nil)

                Button {
                    if let selectedProfile {
                        Task { await store.refreshProfile(selectedProfile) }
                    }
                } label: {
                    Label("刷新选中", systemImage: "arrow.clockwise")
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
            .init(title: "名称", width: 230) { profile in
                (profile.id == store.settings.activeProfileID ? "* " : "") + profile.name
            },
            .init(title: "类型", width: 72) { $0.source == .remote ? "远程" : "本地" },
            .init(title: "更新", width: 130) { Formatters.shortDate.string(from: $0.updatedAt) },
            .init(title: "用量", width: 170) { profileUsageText($0) }
        ]
    }

    private func profileUsageText(_ profile: ProfileItem) -> String {
        guard let total = profile.total else { return "-" }
        let used = (profile.uploadUsed ?? 0) + (profile.downloadUsed ?? 0)
        return "\(Formatters.bytes(used)) / \(Formatters.bytes(total))"
    }
}

private struct ProfileEditorPane: View {
    var profile: ProfileItem?
    @Binding var editorName: String
    @Binding var editorContent: String
    var reload: () -> Void
    var save: () -> Void
    @State private var editorMode = "yaml"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if profile == nil {
                ContentUnavailableView("未选择配置", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("配置编辑器")
                        .font(.headline)
                    Spacer()
                    Picker("编辑模式", selection: $editorMode) {
                        Text("YAML").tag("yaml")
                        Text("结构").tag("structure")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    Button {
                        reload()
                    } label: {
                        Label("重新载入", systemImage: "arrow.counterclockwise")
                    }
                    Button {
                        save()
                    } label: {
                        Label("保存", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                }

                TextField("配置名称", text: $editorName)
                    .textFieldStyle(.roundedBorder)

                if editorMode == "yaml" {
                    TextEditor(text: $editorContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .border(Color.secondary.opacity(0.25))
                } else {
                    ProfileStructureEditorView(content: $editorContent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Text("保存前会更新源配置文件；结构化编辑会重写 YAML 排版，启动核心时仍会先 dry-run。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 12)
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

private extension UTType {
    static let yaml = UTType(filenameExtension: "yaml") ?? .text
}
