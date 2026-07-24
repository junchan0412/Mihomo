import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfilesView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager
    @EnvironmentObject private var store: AppStore
    @State private var selectedProfileIDs: Set<UUID> = []
    @State private var searchText = ""
    @FocusState private var searchIsFocused: Bool
    @State private var isDropTargeted = false
    @State private var showingRemoteImport = false
    @State private var confirmsDeletion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                storagePane
                ProfileRefreshQueueStrip()
                    .environmentObject(store)
                profileTablePane
                detailPane
            }
            .padding(.horizontal, MihomoUI.pageHorizontalPadding)
            .padding(.vertical, MihomoUI.pageVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("配置")
        .background(MihomoUI.pageBackground)
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索配置名称或来源")
        .compatibleSearchFocused($searchIsFocused)
        .focusedSceneValue(\.workspaceCommands, commandContext)
        .overlay {
            DropTargetOverlay(isTargeted: isDropTargeted)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .onAppear {
            if let profileID = store.settings.activeProfileID ?? store.profiles.first?.id {
                selectedProfileIDs = [profileID]
            }
        }
        .onChange(of: store.profiles) {
            selectedProfileIDs.formIntersection(Set(store.profiles.map(\.id)))
            if selectedProfileIDs.isEmpty,
               let profileID = store.settings.activeProfileID ?? store.profiles.first?.id {
                selectedProfileIDs = [profileID]
            }
        }
        .confirmationDialog("删除所选配置？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("删除 \(selectedProfiles.count) 个配置", role: .destructive) {
                let profiles = selectedProfiles
                selectedProfileIDs.removeAll()
                Task { await store.deleteProfiles(profiles, undoManager: undoManager) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("配置文件将从 Mihomo 的配置目录移除。完成后可使用 Command-Z 撤销。")
        }
        .sheet(isPresented: $showingRemoteImport) {
            RemoteProfileImportSheet()
                .environmentObject(store)
        }
        .sheet(item: pendingProfileRefreshPreviewBinding) { preview in
            RemoteProfileRefreshPreviewSheet(
                preview: preview,
                apply: store.applyPendingProfileRefreshPreview,
                cancel: store.discardPendingProfileRefreshPreview
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("配置")
                    .font(MihomoUI.Fonts.pageTitle)
                Text("管理本地配置、远程订阅与运行时覆写。当前 \(store.profiles.count) 个配置，活跃 \(store.activeProfile?.name ?? "无")。")
                    .font(MihomoUI.Fonts.pageSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var storagePane: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("配置存储路径")
                .font(.headline)
                .frame(width: 110, alignment: .trailing)

            Text(store.profileStorageDirectory.path)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer()

            Button {
                store.revealProfileStorageDirectory()
            } label: {
                Label("在 Finder 中显示", systemImage: "folder")
            }

            Button {
                chooseProfileStorageDirectory()
            } label: {
                Label("修改路径", systemImage: "folder.badge.gearshape")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
    }

    private var profileTablePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("配置列表")
                    .font(.headline)
                Spacer()
                Text("\(store.profiles.count) 个配置")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            AppKitTable(
                rows: visibleProfiles,
                selection: $selectedProfileIDs,
                columns: profileColumns,
                allowsMultipleSelection: true,
                onDoubleClick: { profile in
                    selectedProfileIDs = [profile.id]
                    openProfileEditor()
                },
                onActivate: { profiles in
                    guard let profile = profiles.first else { return }
                    selectedProfileIDs = [profile.id]
                    openProfileEditor()
                },
                onPreview: { profiles in previewProfiles(profiles) },
                onDelete: { _ in requestDeleteSelectedProfiles() },
                hasHorizontalScroller: false,
                allowsParentScrollPassthrough: true,
                contextMenuActions: profileContextMenuActions
            )
            .overlay {
                if store.profiles.isEmpty {
                    ContentUnavailableView("没有配置", systemImage: "doc.text")
                }
            }
            .frame(height: profileTableHeight)

            HStack(spacing: 10) {
                Button {
                    if let selectedProfile {
                        Task { await store.setActiveProfile(selectedProfile) }
                    }
                } label: {
                    Label("启用", systemImage: "checkmark.circle")
                }
                .disabled(selectedProfile == nil)

                Button {
                    openProfileEditor()
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                .disabled(selectedProfile == nil)

                Button {
                    refreshSelectedProfiles()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(selectedProfiles.contains(where: \.isRemote) == false)

                Button {
                    Task { await store.refreshAllRemoteProfiles() }
                } label: {
                    Label("刷新订阅", systemImage: "arrow.triangle.2.circlepath")
                }

                Button {
                    importLocal()
                } label: {
                    Label("导入...", systemImage: "square.and.arrow.down")
                }

                Button {
                    showingRemoteImport = true
                } label: {
                    Label("从 URL 安装配置...", systemImage: "link.badge.plus")
                }

                if let selectedProfile {
                    ShareLink(item: store.profileStore.profileFile(selectedProfile, settings: store.settings)) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    requestDeleteSelectedProfiles()
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(selectedProfiles.isEmpty || selectedProfiles.count >= store.profiles.count)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSummaryPane(
                profile: selectedProfile,
                stats: selectedProfile.map { store.profileStats(for: $0) },
                editProfile: openProfileEditor
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)

            ProfileQualityPane(report: store.profileQualityReport(for: selectedProfile))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var selectedProfile: ProfileItem? {
        guard selectedProfileIDs.count == 1, let selectedProfileID = selectedProfileIDs.first else { return nil }
        return store.profiles.first { $0.id == selectedProfileID }
    }

    private var pendingProfileRefreshPreviewBinding: Binding<RemoteProfileRefreshPreview?> {
        Binding(
            get: { store.pendingProfileRefreshPreview },
            set: { preview in
                if preview == nil, store.pendingProfileRefreshPreview != nil {
                    store.discardPendingProfileRefreshPreview()
                }
            }
        )
    }

    private var selectedProfiles: [ProfileItem] {
        store.profiles.filter { selectedProfileIDs.contains($0.id) }
    }

    private var visibleProfiles: [ProfileItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return store.profiles }
        return store.profiles.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.location.localizedCaseInsensitiveContains(query)
                || $0.fileName.localizedCaseInsensitiveContains(query)
        }
    }

    private var profileTableHeight: CGFloat {
        let visibleRows = max(visibleProfiles.count, 1)
        let naturalHeight = 30 + CGFloat(visibleRows) * 28
        return min(max(naturalHeight, 176), 280)
    }

    private var profileColumns: [AppKitTableColumn<ProfileItem>] {
        [
            .init(title: "状态", width: 72) { profile in
                profile.id == store.settings.activeProfileID ? "启用" : "-"
            },
            .init(title: "名称", width: 180) { $0.name },
            .init(title: "类型", width: 80) { $0.source == .remote ? "远程" : "本地" },
            .init(title: "来源", width: 220) { profile in
                profile.source == .remote ? profile.location : profile.fileName
            },
            .init(title: "更新", width: 140) { Formatters.shortDate.string(from: $0.updatedAt) }
        ]
    }

    private func openProfileEditor() {
        guard let selectedProfileID = selectedProfile?.id else { return }
        openWindow(value: selectedProfileID)
    }

    private func requestDeleteSelectedProfiles() {
        guard selectedProfiles.isEmpty == false,
              selectedProfiles.count < store.profiles.count
        else { return }
        confirmsDeletion = true
    }

    private func refreshSelectedProfiles() {
        let profiles = selectedProfiles.filter(\.isRemote)
        Task {
            for profile in profiles {
                await store.refreshProfile(profile)
            }
        }
    }

    private func previewProfiles(_ profiles: [ProfileItem]) {
        let urls = profiles.map { store.profileStore.profileFile($0, settings: store.settings) }
        QuickLookPreviewer.shared.present(urls)
    }

    private var profileContextMenuActions: [AppKitTableContextAction<ProfileItem>] {
        [
            .init("启用", isEnabled: { $0.count == 1 }) { profiles in
                guard let profile = profiles.first else { return }
                Task { await store.setActiveProfile(profile) }
            },
            .init("编辑", isEnabled: { $0.count == 1 }) { profiles in
                guard let profile = profiles.first else { return }
                selectedProfileIDs = [profile.id]
                openProfileEditor()
            },
            .init("刷新", isEnabled: { $0.contains(where: \.isRemote) }) { profiles in
                selectedProfileIDs = Set(profiles.map(\.id))
                refreshSelectedProfiles()
            },
            .init("快速查看") { profiles in
                previewProfiles(profiles)
            },
            .init("在 Finder 中显示") { profiles in
                let urls = profiles.map { store.profileStore.profileFile($0, settings: store.settings) }
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            },
            .init(
                "删除",
                isDestructive: true,
                isEnabled: { $0.isEmpty == false && $0.count < store.profiles.count }
            ) { profiles in
                selectedProfileIDs = Set(profiles.map(\.id))
                requestDeleteSelectedProfiles()
            }
        ]
    }

    private var commandContext: WorkspaceCommandContext {
        WorkspaceCommandContext(
            search: {
                searchIsFocused = true
                MihomoSearchFocus.request()
            },
            refresh: { Task { await store.refreshAllRemoteProfiles() } },
            activateSelection: searchIsFocused || selectedProfile == nil ? nil : openProfileEditor,
            previewSelection: searchIsFocused || selectedProfiles.isEmpty ? nil : { previewProfiles(selectedProfiles) },
            deleteSelection: searchIsFocused || selectedProfiles.isEmpty || selectedProfiles.count >= store.profiles.count
                ? nil
                : requestDeleteSelectedProfiles
        )
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

    private func chooseProfileStorageDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择配置存储路径"
        panel.message = "选择用于保存配置 YAML 文件的目录。现有配置会复制到新目录。"
        panel.prompt = "使用此目录"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.profileStorageDirectory

        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.changeProfileStorageDirectory(to: url) }
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
