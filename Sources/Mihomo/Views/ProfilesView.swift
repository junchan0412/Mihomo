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
        let presentation = ProfilesPresentationSnapshot(
            profiles: store.profiles,
            selectedIDs: selectedProfileIDs,
            searchText: searchText,
            activeProfileID: store.settings.activeProfileID
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ProfilesHeader(
                    profileCount: store.profiles.count,
                    activeProfileName: store.activeProfile?.name
                )
                ProfileStoragePane(
                    directory: store.profileStorageDirectory,
                    reveal: store.revealProfileStorageDirectory,
                    choose: chooseProfileStorageDirectory
                )
                ProfileRefreshQueueStrip()
                    .environmentObject(store)
                profileTablePane(presentation)
                ProfilesDetailPane(
                    profile: presentation.selectedProfile,
                    stats: presentation.selectedProfile.map { store.profileStats(for: $0) },
                    report: store.profileQualityReport(for: presentation.selectedProfile),
                    editProfile: { openProfileEditor(presentation.selectedProfile) }
                )
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
        .focusedSceneValue(\.workspaceCommands, commandContext(for: presentation))
        .overlay {
            ProfileDropTargetOverlay(isTargeted: isDropTargeted)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .onAppear { ensureSelection() }
        .onChange(of: store.profiles) {
            ensureSelection()
        }
        .onChange(of: searchText) { ensureSelection() }
        .confirmationDialog("删除所选配置？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("删除 \(presentation.selectedProfiles.count) 个配置", role: .destructive) {
                let profiles = presentation.selectedProfiles
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

    private func profileTablePane(_ presentation: ProfilesPresentationSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("配置列表")
                    .font(.headline)
                Spacer()
                Text("\(store.profiles.count) 个配置")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if presentation.visibleProfiles.isEmpty {
                ContentUnavailableView(
                    store.profiles.isEmpty ? "没有配置" : "没有匹配的配置",
                    systemImage: store.profiles.isEmpty ? "doc.text" : "magnifyingglass",
                    description: Text(store.profiles.isEmpty ? "导入本地配置或添加远程订阅后会显示在这里。" : "请尝试其他搜索词。")
                )
                .frame(height: presentation.tableHeight)
            } else {
                AppKitTable(
                    rows: presentation.visibleProfiles,
                    selection: $selectedProfileIDs,
                    columns: presentation.columns,
                    allowsMultipleSelection: true,
                    onDoubleClick: { profile in
                        selectedProfileIDs = [profile.id]
                        openProfileEditor(profile)
                    },
                    onActivate: { profiles in
                        guard let profile = profiles.first else { return }
                        selectedProfileIDs = [profile.id]
                        openProfileEditor(profile)
                    },
                    onPreview: { profiles in previewProfiles(profiles) },
                    onDelete: requestDeleteProfiles,
                    hasHorizontalScroller: false,
                    allowsParentScrollPassthrough: true,
                    contextMenuActions: profileContextMenuActions
                )
                .frame(height: presentation.tableHeight)
            }

            HStack(spacing: 10) {
                Button {
                    if let selectedProfile = presentation.selectedProfile {
                        Task { await store.setActiveProfile(selectedProfile) }
                    }
                } label: {
                    Label("启用", systemImage: "checkmark.circle")
                }
                .disabled(presentation.selectedProfile == nil)

                Button {
                    openProfileEditor(presentation.selectedProfile)
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                .disabled(presentation.selectedProfile == nil)

                Button {
                    refreshProfiles(presentation.selectedProfiles)
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(presentation.selectedProfiles.contains(where: \.isRemote) == false)

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

                if let selectedProfile = presentation.selectedProfile {
                    ShareLink(item: store.profileStore.profileFile(selectedProfile, settings: store.settings)) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    requestDeleteProfiles(presentation.selectedProfiles)
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(
                    presentation.selectedProfiles.isEmpty
                        || presentation.selectedProfiles.count >= store.profiles.count
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

    private func ensureSelection() {
        let presentation = ProfilesPresentationSnapshot(
            profiles: store.profiles,
            selectedIDs: selectedProfileIDs,
            searchText: searchText,
            activeProfileID: store.settings.activeProfileID
        )
        selectedProfileIDs = TableSelection.reconciled(
            selectedProfileIDs,
            visibleIDs: presentation.visibleProfiles.map(\.id),
            preferredID: store.settings.activeProfileID,
            selectsFirstWhenEmpty: true
        )
    }

    private func openProfileEditor(_ profile: ProfileItem?) {
        guard let profile else { return }
        openWindow(value: profile.id)
    }

    private func requestDeleteProfiles(_ profiles: [ProfileItem]) {
        guard profiles.isEmpty == false,
              profiles.count < store.profiles.count
        else { return }
        selectedProfileIDs = Set(profiles.map(\.id))
        confirmsDeletion = true
    }

    private func refreshProfiles(_ profiles: [ProfileItem]) {
        let remoteProfiles = profiles.filter(\.isRemote)
        Task {
            for profile in remoteProfiles {
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
                openProfileEditor(profile)
            },
            .init("刷新", isEnabled: { $0.contains(where: \.isRemote) }) { profiles in
                selectedProfileIDs = Set(profiles.map(\.id))
                refreshProfiles(profiles)
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
                requestDeleteProfiles(profiles)
            }
        ]
    }

    private func commandContext(for presentation: ProfilesPresentationSnapshot) -> WorkspaceCommandContext {
        WorkspaceCommandContext(
            search: {
                searchIsFocused = true
                MihomoSearchFocus.request()
            },
            refresh: { Task { await store.refreshAllRemoteProfiles() } },
            activateSelection: searchIsFocused || presentation.selectedProfile == nil
                ? nil
                : { openProfileEditor(presentation.selectedProfile) },
            previewSelection: searchIsFocused || presentation.selectedProfiles.isEmpty
                ? nil
                : { previewProfiles(presentation.selectedProfiles) },
            deleteSelection: searchIsFocused
                || presentation.selectedProfiles.isEmpty
                || presentation.selectedProfiles.count >= store.profiles.count
                ? nil
                : { requestDeleteProfiles(presentation.selectedProfiles) }
        )
    }

    private func importLocal() {
        guard let url = ProfileFilePicker.localProfile() else { return }
        Task { await store.importLocalProfile(url: url) }
    }

    private func chooseProfileStorageDirectory() {
        guard let url = ProfileFilePicker.storageDirectory(current: store.profileStorageDirectory) else { return }
        Task { await store.changeProfileStorageDirectory(to: url) }
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
