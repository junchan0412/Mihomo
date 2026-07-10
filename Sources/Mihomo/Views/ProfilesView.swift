import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfilesView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AppStore
    @State private var selectedProfileID: UUID?
    @State private var isDropTargeted = false
    @State private var showingRemoteImport = false

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
        .sheet(isPresented: $showingRemoteImport) {
            RemoteProfileImportSheet()
                .environmentObject(store)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("配置")
                    .font(MihomoUI.Fonts.pageTitle)
                Text("管理本地配置、远程订阅与运行时覆写。")
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
                rows: store.profiles,
                selection: $selectedProfileID,
                columns: profileColumns,
                hasHorizontalScroller: false,
                allowsParentScrollPassthrough: true
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
                    if let selectedProfile {
                        Task { await store.refreshProfile(selectedProfile) }
                    }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(selectedProfile?.isRemote != true)

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

                Spacer()

                Button {
                    openWindow(id: "fragments-editor")
                } label: {
                    Label("覆写", systemImage: "slider.horizontal.3")
                }

                Button(role: .destructive) {
                    deleteSelectedProfile()
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(selectedProfile == nil || store.profiles.count <= 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ProfileSummaryPane(
                    profile: selectedProfile,
                    stats: selectedProfile.map { store.profileStats(for: $0) },
                    editProfile: openProfileEditor
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)

                ConfigFragmentsSummaryView {
                    openWindow(id: "fragments-editor")
                }
                .environmentObject(store)
                .frame(width: 380, alignment: .topLeading)
            }

            ProfileQualityPane(report: store.profileQualityReport(for: selectedProfile))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var selectedProfile: ProfileItem? {
        guard let selectedProfileID else { return nil }
        return store.profiles.first { $0.id == selectedProfileID }
    }

    private var profileTableHeight: CGFloat {
        let visibleRows = max(store.profiles.count, 1)
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
