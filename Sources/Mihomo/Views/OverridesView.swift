import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OverridesView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager
    @EnvironmentObject private var store: AppStore

    @State private var selectedFragmentIDs: Set<UUID> = []
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
                ConfigFragmentRefreshStrip()
                    .environmentObject(store)
                fragmentTablePane
                detailPane
            }
            .padding(.horizontal, MihomoUI.pageHorizontalPadding)
            .padding(.vertical, MihomoUI.pageVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("覆写")
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索覆写名称、来源或内容")
        .compatibleSearchFocused($searchIsFocused)
        .focusedSceneValue(\.workspaceCommands, commandContext)
        .overlay {
            ConfigFragmentDropTargetOverlay(isTargeted: isDropTargeted)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .onAppear { ensureSelection() }
        .onChange(of: store.configFragments) { ensureSelection() }
        .confirmationDialog("删除所选覆写？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("删除 \(selectedFragments.count) 个覆写", role: .destructive) {
                let fragments = selectedFragments
                selectedFragmentIDs.removeAll()
                store.deleteConfigFragments(fragments, undoManager: undoManager)
                ensureSelection()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("覆写会从运行时配置链中移除。完成后可使用 Command-Z 撤销。")
        }
        .sheet(isPresented: $showingRemoteImport) {
            RemoteConfigFragmentImportSheet()
                .environmentObject(store)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("覆写")
                    .font(MihomoUI.Fonts.pageTitle)
                Text("管理本地覆写、远程订阅与生效顺序。")
                    .font(MihomoUI.Fonts.pageSubtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var storagePane: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("覆写存储路径")
                .font(.headline)
                .frame(width: 110, alignment: .trailing)

            Text(AppPaths.configFragmentsFile.path)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer()

            Button {
                store.revealConfigFragmentStorage()
            } label: {
                Label("在 Finder 中显示", systemImage: "folder")
            }

            Button {
                store.reloadConfigFragmentsFromDisk()
            } label: {
                Label("重新载入", systemImage: "arrow.clockwise")
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

    private var fragmentTablePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("覆写列表")
                    .font(.headline)
                Spacer()
                Text("\(store.configFragments.count) 个覆写")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            AppKitTable(
                rows: visibleFragments,
                selection: $selectedFragmentIDs,
                columns: fragmentColumns,
                allowsMultipleSelection: true,
                onDoubleClick: { fragment in
                    selectedFragmentIDs = [fragment.id]
                    openFragmentEditor()
                },
                onActivate: { fragments in
                    guard let fragment = fragments.first else { return }
                    selectedFragmentIDs = [fragment.id]
                    openFragmentEditor()
                },
                onPreview: previewFragments,
                onDelete: { _ in requestDeleteSelectedFragments() },
                hasHorizontalScroller: false,
                allowsParentScrollPassthrough: true,
                contextMenuActions: fragmentContextMenuActions
            )
            .overlay {
                if store.configFragments.isEmpty {
                    ContentUnavailableView("没有覆写", systemImage: "doc.badge.plus", description: Text("可以新建、导入文件或从 URL 安装覆写。"))
                }
            }
            .frame(height: fragmentTableHeight)

            HStack(spacing: 10) {
                Button {
                    setSelectedFragmentsEnabled()
                } label: {
                    Label(enableActionTitle, systemImage: enableActionSystemImage)
                }
                .disabled(selectedFragments.isEmpty)

                Button {
                    openFragmentEditor()
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                .disabled(selectedFragment == nil)

                Button {
                    refreshSelectedFragments()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(selectedFragments.contains(where: \.isRemote) == false)

                Button {
                    Task { await store.refreshAllRemoteConfigFragments() }
                } label: {
                    Label("刷新订阅", systemImage: "arrow.triangle.2.circlepath")
                }

                Button {
                    createFragment()
                } label: {
                    Label("新增...", systemImage: "plus")
                }

                Button {
                    importLocal()
                } label: {
                    Label("导入...", systemImage: "square.and.arrow.down")
                }

                Button {
                    showingRemoteImport = true
                } label: {
                    Label("从 URL 安装覆写...", systemImage: "link.badge.plus")
                }

                Button {
                    exportSelectedFragment()
                } label: {
                    Label("导出...", systemImage: "square.and.arrow.up")
                }
                .disabled(selectedFragment == nil)

                Spacer()

                Button(role: .destructive) {
                    requestDeleteSelectedFragments()
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(selectedFragments.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            ConfigFragmentSummaryPane(
                fragment: selectedFragment,
                profiles: store.profiles,
                editFragment: openFragmentEditor
            )
            ConfigFragmentContentPane(fragment: selectedFragment)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var selectedFragment: ConfigFragment? {
        guard selectedFragmentIDs.count == 1, let selectedFragmentID = selectedFragmentIDs.first else { return nil }
        return store.configFragments.first { $0.id == selectedFragmentID }
    }

    private var selectedFragments: [ConfigFragment] {
        store.configFragments.filter { selectedFragmentIDs.contains($0.id) }
    }

    private var visibleFragments: [ConfigFragment] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return store.configFragments }
        return store.configFragments.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.location.localizedCaseInsensitiveContains(query)
                || $0.content.localizedCaseInsensitiveContains(query)
        }
    }

    private var fragmentTableHeight: CGFloat {
        let visibleRows = max(visibleFragments.count, 1)
        let naturalHeight = 30 + CGFloat(visibleRows) * 28
        return min(max(naturalHeight, 176), 280)
    }

    private var fragmentColumns: [AppKitTableColumn<ConfigFragment>] {
        [
            .init(title: "顺序", width: 60) { fragment in
                store.configFragments.firstIndex(where: { $0.id == fragment.id }).map { "\($0 + 1)" } ?? "-"
            },
            .init(title: "状态", width: 72) { $0.enabled ? "启用" : "停用" },
            .init(title: "名称", width: 150) { $0.name },
            .init(title: "类型", width: 80) { $0.kind.title },
            .init(title: "来源", width: 190) { sourceText($0) },
            .init(title: "范围", width: 110) { scopeText($0) },
            .init(title: "更新", width: 140) { Formatters.shortDate.string(from: $0.updatedAt) }
        ]
    }

    private var enableActionTitle: String {
        selectedFragments.contains(where: { $0.enabled == false }) ? "启用" : "停用"
    }

    private var enableActionSystemImage: String {
        selectedFragments.contains(where: { $0.enabled == false }) ? "checkmark.circle" : "pause.circle"
    }

    private func sourceText(_ fragment: ConfigFragment) -> String {
        if fragment.location.isEmpty { return fragment.source == .remote ? "远程" : "手动创建" }
        if fragment.isRemote { return fragment.location }
        return URL(fileURLWithPath: fragment.location).lastPathComponent
    }

    private func scopeText(_ fragment: ConfigFragment) -> String {
        fragment.appliesGlobally ? "全部配置" : "\(fragment.profileIDs.count) 个配置"
    }

    private func ensureSelection() {
        selectedFragmentIDs.formIntersection(Set(store.configFragments.map(\.id)))
        if selectedFragmentIDs.isEmpty, let firstID = visibleFragments.first?.id ?? store.configFragments.first?.id {
            selectedFragmentIDs = [firstID]
        }
    }

    private func openFragmentEditor() {
        guard let fragmentID = selectedFragment?.id else { return }
        openWindow(value: ConfigFragmentEditorRoute.editing(fragmentID))
    }

    private func createFragment() {
        openWindow(value: ConfigFragmentEditorRoute.creating())
    }

    private func setSelectedFragmentsEnabled() {
        let enabled = selectedFragments.contains(where: { $0.enabled == false })
        store.setConfigFragments(selectedFragments, enabled: enabled, undoManager: undoManager)
    }

    private func refreshSelectedFragments() {
        let fragments = selectedFragments.filter(\.isRemote)
        Task {
            for fragment in fragments {
                await store.refreshConfigFragment(fragment)
            }
        }
    }

    private func requestDeleteSelectedFragments() {
        guard selectedFragments.isEmpty == false else { return }
        confirmsDeletion = true
    }

    private func previewFragments(_ fragments: [ConfigFragment]) {
        let urls = fragments.compactMap(materializedPreviewURL)
        guard urls.isEmpty == false else { return }
        QuickLookPreviewer.shared.present(urls)
    }

    private func materializedPreviewURL(_ fragment: ConfigFragment) -> URL? {
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("Mihomo-Override-Preview", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let pathExtension = fragment.kind == .yaml ? "yaml" : "js"
            let url = directory.appendingPathComponent("\(fragment.id.uuidString).\(pathExtension)")
            try fragment.content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            store.appendLog("error", "覆写预览生成失败：\(error.localizedDescription)")
            return nil
        }
    }

    private func exportSelectedFragment() {
        guard let fragment = selectedFragment else { return }
        let panel = NSSavePanel()
        panel.title = "导出覆写"
        panel.nameFieldStringValue = "\(fragment.name).\(fragment.kind == .yaml ? "yaml" : "js")"
        panel.allowedContentTypes = [fragment.kind == .yaml ? .mihomoOverrideYAML : .mihomoJavaScript]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try fragment.content.write(to: url, atomically: true, encoding: .utf8)
                store.appendLog("info", "已导出覆写 \(fragment.name)")
            } catch {
                store.appendLog("error", "覆写导出失败：\(error.localizedDescription)")
            }
        }
    }

    private func importLocal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mihomoOverrideYAML, .mihomoJavaScript, .plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task {
                for url in urls {
                    await store.importLocalConfigFragment(url: url, undoManager: undoManager)
                }
            }
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
                Task { await store.importLocalConfigFragment(url: url, undoManager: undoManager) }
            }
        }
        return accepted
    }

    private var fragmentContextMenuActions: [AppKitTableContextAction<ConfigFragment>] {
        [
            .init("启用", isEnabled: { $0.contains(where: { $0.enabled == false }) }) { fragments in
                store.setConfigFragments(fragments, enabled: true, undoManager: undoManager)
            },
            .init("停用", isEnabled: { $0.contains(where: \.enabled) }) { fragments in
                store.setConfigFragments(fragments, enabled: false, undoManager: undoManager)
            },
            .init("编辑", isEnabled: { $0.count == 1 }) { fragments in
                guard let fragment = fragments.first else { return }
                selectedFragmentIDs = [fragment.id]
                openFragmentEditor()
            },
            .init("刷新", isEnabled: { $0.contains(where: \.isRemote) }) { fragments in
                selectedFragmentIDs = Set(fragments.map(\.id))
                refreshSelectedFragments()
            },
            .init("快速查看") { previewFragments($0) },
            .init("复制内容", isEnabled: { $0.count == 1 }) { fragments in
                guard let fragment = fragments.first else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fragment.content, forType: .string)
            },
            .init("上移", isEnabled: { fragments in
                guard fragments.count == 1, let fragment = fragments.first,
                      let index = store.configFragments.firstIndex(where: { $0.id == fragment.id })
                else { return false }
                return index > 0
            }) { fragments in
                if let fragment = fragments.first { store.moveConfigFragment(fragment, offset: -1, undoManager: undoManager) }
            },
            .init("下移", isEnabled: { fragments in
                guard fragments.count == 1, let fragment = fragments.first,
                      let index = store.configFragments.firstIndex(where: { $0.id == fragment.id })
                else { return false }
                return index < store.configFragments.count - 1
            }) { fragments in
                if let fragment = fragments.first { store.moveConfigFragment(fragment, offset: 1, undoManager: undoManager) }
            },
            .init("删除", isDestructive: true, isEnabled: { $0.isEmpty == false }) { fragments in
                selectedFragmentIDs = Set(fragments.map(\.id))
                requestDeleteSelectedFragments()
            }
        ]
    }

    private var commandContext: WorkspaceCommandContext {
        WorkspaceCommandContext(
            search: {
                searchIsFocused = true
                MihomoSearchFocus.request()
            },
            refresh: { Task { await store.refreshAllRemoteConfigFragments() } },
            activateSelection: searchIsFocused || selectedFragment == nil ? nil : openFragmentEditor,
            previewSelection: searchIsFocused || selectedFragments.isEmpty ? nil : { previewFragments(selectedFragments) },
            deleteSelection: searchIsFocused || selectedFragments.isEmpty ? nil : requestDeleteSelectedFragments
        )
    }
}

private struct ConfigFragmentDropTargetOverlay: View {
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
    static let mihomoOverrideYAML = UTType(filenameExtension: "yaml") ?? .plainText
    static let mihomoJavaScript = UTType(filenameExtension: "js") ?? .plainText
}
