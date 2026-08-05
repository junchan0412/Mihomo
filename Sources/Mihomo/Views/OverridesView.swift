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
        let presentation = listPresentation()

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                storagePane
                ConfigFragmentRefreshStrip()
                    .environmentObject(store)
                ConfigFragmentListPane(
                    presentation: presentation,
                    selectedFragmentIDs: $selectedFragmentIDs,
                    actions: listActions
                )
                detailPane(presentation.selectedFragment)
            }
            .padding(.horizontal, MihomoUI.pageHorizontalPadding)
            .padding(.vertical, MihomoUI.pageVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("覆写")
        .background(MihomoUI.pageBackground)
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索覆写名称、来源或内容")
        .compatibleSearchFocused($searchIsFocused)
        .focusedSceneValue(\.workspaceCommands, commandContext(presentation))
        .overlay {
            ConfigFragmentDropTargetOverlay(isTargeted: isDropTargeted)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .onAppear { ensureSelection() }
        .onChange(of: store.configFragments) { ensureSelection() }
        .onChange(of: searchText) { ensureSelection() }
        .confirmationDialog("删除所选覆写？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("删除 \(presentation.selectedFragments.count) 个覆写", role: .destructive) {
                let fragments = presentation.selectedFragments
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

    private func detailPane(_ selectedFragment: ConfigFragment?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ConfigFragmentSummaryPane(
                fragment: selectedFragment,
                profiles: store.profiles,
                editFragment: {
                    guard let selectedFragment else { return }
                    openFragmentEditor(selectedFragment)
                }
            )
            ConfigFragmentOverviewPane(fragment: selectedFragment)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func listPresentation() -> ConfigFragmentListPresentation {
        ConfigFragmentListPresentation.make(
            fragments: store.configFragments,
            selectedIDs: selectedFragmentIDs,
            searchText: searchText
        )
    }

    private func ensureSelection() {
        let presentation = listPresentation()
        selectedFragmentIDs = TableSelection.reconciled(
            selectedFragmentIDs,
            visibleIDs: presentation.visibleFragments.map(\.id),
            selectsFirstWhenEmpty: true
        )
    }

    private func openFragmentEditor(_ fragment: ConfigFragment) {
        openWindow(value: ConfigFragmentEditorRoute.editing(fragment.id))
    }

    private func createFragment() {
        openWindow(value: ConfigFragmentEditorRoute.creating())
    }

    private func refreshFragments(_ fragments: [ConfigFragment]) {
        Task {
            await store.refreshConfigFragments(fragments)
        }
    }

    private func requestDeleteFragments(_ fragments: [ConfigFragment]) {
        guard fragments.isEmpty == false else { return }
        selectedFragmentIDs = Set(fragments.map(\.id))
        confirmsDeletion = true
    }

    private func previewFragments(_ fragments: [ConfigFragment]) {
        let ids = fragments.map(\.id)
        guard ids.isEmpty == false else { return }
        openWindow(value: ConfigFragmentPreviewRoute(fragmentIDs: ids))
    }

    private func exportFragment(_ fragment: ConfigFragment) {
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

    private var listActions: ConfigFragmentListActions {
        ConfigFragmentListActions(
            setEnabled: { fragments, enabled in
                store.setConfigFragments(fragments, enabled: enabled, undoManager: undoManager)
            },
            edit: openFragmentEditor,
            refresh: refreshFragments,
            refreshAll: { Task { await store.refreshAllRemoteConfigFragments() } },
            isRefreshing: store.isConfigFragmentRefreshInProgress,
            preview: previewFragments,
            move: { fragment, offset in
                store.moveConfigFragment(fragment, offset: offset, undoManager: undoManager)
            },
            create: createFragment,
            importLocal: importLocal,
            importRemote: { showingRemoteImport = true },
            export: exportFragment,
            delete: requestDeleteFragments
        )
    }

    private func commandContext(_ presentation: ConfigFragmentListPresentation) -> WorkspaceCommandContext {
        WorkspaceCommandContext(
            search: {
                searchIsFocused = true
                MihomoSearchFocus.request()
            },
            refresh: { Task { await store.refreshAllRemoteConfigFragments() } },
            activateSelection: searchIsFocused || presentation.selectedFragment == nil
                ? nil
                : { if let fragment = presentation.selectedFragment { openFragmentEditor(fragment) } },
            previewSelection: searchIsFocused || presentation.selectedFragments.isEmpty
                ? nil
                : { previewFragments(presentation.selectedFragments) },
            deleteSelection: searchIsFocused || presentation.selectedFragments.isEmpty
                ? nil
                : { requestDeleteFragments(presentation.selectedFragments) }
        )
    }
}
