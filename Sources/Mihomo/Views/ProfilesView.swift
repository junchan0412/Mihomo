import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfilesView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AppStore
    @State private var selectedProfileID: UUID?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    remoteSubscriptionBar
                    ProfileRefreshQueueStrip()
                        .environmentObject(store)

                    ProfileListPane(
                        selectedProfileID: $selectedProfileID,
                        selectedProfile: selectedProfile,
                        editProfile: openProfileEditor,
                        deleteProfile: deleteSelectedProfile
                    )
                    .environmentObject(store)

                    ProfileSummaryPane(
                        profile: selectedProfile,
                        stats: selectedProfile.map { store.profileStats(for: $0) },
                        editProfile: openProfileEditor
                    )

                    ConfigFragmentsSummaryView {
                        openWindow(id: "fragments-editor")
                    }
                    .environmentObject(store)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .navigationTitle("配置")
        .overlay {
            DropTargetOverlay(isTargeted: isDropTargeted)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .onAppear {
            selectedProfileID = store.settings.activeProfileID ?? store.profiles.first?.id
        }
        .onChange(of: store.profiles) {
            if selectedProfileID == nil || store.profiles.contains(where: { $0.id == selectedProfileID }) == false {
                selectedProfileID = store.settings.activeProfileID ?? store.profiles.first?.id
            }
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

    private func openProfileEditor() {
        guard let selectedProfileID else { return }
        store.profileEditorProfileID = selectedProfileID
        openWindow(id: "profile-editor")
    }

    private func deleteSelectedProfile() {
        guard let selectedProfile else { return }
        Task { await store.deleteProfile(selectedProfile) }
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
    var editProfile: () -> Void
    var deleteProfile: () -> Void

    var body: some View {
        GroupBox("配置列表") {
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

                    Button {
                        editProfile()
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    .disabled(selectedProfile == nil)

                    Button(role: .destructive) {
                        deleteProfile()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .disabled(selectedProfile == nil || store.profiles.count <= 1)

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
                .frame(height: 260)
            }
            .padding(.vertical, 4)
        }
    }

    private var profileColumns: [AppKitTableColumn<ProfileItem>] {
        [
            .init(title: "状态", width: 72) { profile in
                profile.id == store.settings.activeProfileID ? "启用" : "-"
            },
            .init(title: "名称", width: 230) { profile in
                profile.name
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

private struct ProfileSummaryPane: View {
    var profile: ProfileItem?
    var stats: ProfileStats?
    var editProfile: () -> Void

    var body: some View {
        GroupBox("配置摘要") {
            if profile == nil {
                ContentUnavailableView("未选择配置", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(profile?.name ?? "", systemImage: "doc.text")
                            .font(.headline)
                        Spacer()
                        Button {
                            editProfile()
                        } label: {
                            Label("打开编辑器", systemImage: "square.and.pencil")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if let error = stats?.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                            ProfileMetric(title: "规则", value: "\(stats?.ruleCount ?? 0)")
                            ProfileMetric(title: "策略组", value: "\(stats?.policyGroupCount ?? 0)")
                            ProfileMetric(title: "节点", value: "\(stats?.proxyCount ?? 0)")
                            ProfileMetric(title: "Provider", value: "\(statsProviderCount)")
                            ProfileMetric(title: "行数", value: "\(stats?.lineCount ?? 0)")
                            ProfileMetric(title: "大小", value: Formatters.bytes(Int64(stats?.fileSize ?? 0)))
                            ProfileMetric(title: "来源", value: profile?.source == .remote ? "远程" : "本地")
                            ProfileMetric(title: "更新", value: profile.map { Formatters.shortDate.string(from: $0.updatedAt) } ?? "-")
                        }
                    }

                    Text("默认仅显示统计信息；需要查看或修改 YAML / 结构化规则时打开独立编辑窗口。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var statsProviderCount: Int {
        (stats?.proxyProviderCount ?? 0) + (stats?.ruleProviderCount ?? 0)
    }
}

private struct ProfileMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ConfigFragmentsSummaryView: View {
    @EnvironmentObject private var store: AppStore
    var openEditor: () -> Void

    var body: some View {
        GroupBox("覆写摘要") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Toggle("YAML 覆写", isOn: overrideBinding(\.yamlOverrideEnabled))
                    Toggle("JS Transform", isOn: overrideBinding(\.jsOverrideEnabled))
                    Spacer()
                    Button {
                        openEditor()
                    } label: {
                        Label("管理覆写", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderedProminent)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ProfileMetric(title: "片段", value: "\(store.configFragments.count)")
                    ProfileMetric(title: "已启用", value: "\(store.configFragments.filter(\.enabled).count)")
                    ProfileMetric(title: "YAML", value: "\(store.configFragments.filter { $0.kind == .yaml }.count)")
                    ProfileMetric(title: "JavaScript", value: "\(store.configFragments.filter { $0.kind == .javascript }.count)")
                }

                Text("覆写内容不在配置页直接展开；点击管理后在独立窗口中编辑、启用或删除片段。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
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
