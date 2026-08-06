import AppKit
import SwiftUI

struct ResourcesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var workspace: ResourceWorkspace = .configResources
    @State private var selectedResourceIDs: Set<String> = []
    @State private var searchText = ""
    @FocusState private var searchIsFocused: Bool
    @State private var showsOnlyUnready = false
    @State private var confirmsRollback = false

    private var latestRecords: [String: ProviderUpdateRecord] {
        var records: [String: ProviderUpdateRecord] = [:]
        for record in store.providerUpdateHistory {
            let key = store.providerHistoryKey(kind: record.providerKind, name: record.providerName)
            if records[key] == nil {
                records[key] = record
            }
        }
        return records
    }

    private func resourcePresentation() -> ResourceTablePresentation {
        ResourceTablePresentation.make(
            providers: store.providers,
            latestRecords: latestRecords,
            historyKey: store.providerHistoryKey(for:),
            searchText: searchText,
            showsOnlyUnready: showsOnlyUnready,
            kindFilter: workspace.providerKind
        )
    }

    private var selectedNodeProviderCount: Int {
        guard let activeProfile = store.activeProfile else { return 0 }
        return store.nodeProviders.count { $0.applies(to: activeProfile.id) }
    }

    var body: some View {
        let presentation = resourcePresentation()
        let selectedRows = presentation.selectedRows(for: selectedResourceIDs)
        let rollbackableRows = rollbackableSelectedRows(in: selectedRows)

        return VStack(alignment: .leading, spacing: 14) {
            header(presentation)
            Picker("资源工作区", selection: $workspace) {
                ForEach(ResourceWorkspace.allCases) { workspace in
                    Label(workspace.title, systemImage: workspace.systemImage).tag(workspace)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

            if workspace == .nodeProviders {
                NodeProviderWorkspaceView(searchText: $searchText)
            } else {
                ResourceTablePane(
                    presentation: presentation,
                    selectedResourceIDs: $selectedResourceIDs,
                    showsOnlyUnready: $showsOnlyUnready,
                    updateStatus: store.resourceUpdateStatus,
                    emptyState: ResourceEmptyState(
                        searchText: searchText,
                        showsOnlyUnready: showsOnlyUnready
                    ),
                    selectedRows: selectedRows,
                    rollbackableRows: rollbackableRows,
                    selectedURLs: resourceURLs(for: selectedRows),
                    isResourceUpdateInProgress: store.isResourceBatchOperationInProgress,
                    contextMenuActions: resourceContextMenuActions,
                    updateAll: { Task { await store.updateAllExternalResources() } },
                    refresh: refreshResources,
                    preview: previewResources,
                    requestRollback: { confirmsRollback = true }
                )
                selectedResourcePane(presentation)
            }
        }
        .padding(.horizontal, MihomoUI.pageHorizontalPadding)
        .padding(.vertical, MihomoUI.pageVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("资源")
        .background(MihomoUI.pageBackground)
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索 Provider 或路径")
        .compatibleSearchFocused($searchIsFocused)
        .focusedSceneValue(\.workspaceCommands, commandContext(presentation, selectedRows: selectedRows))
        .onAppear {
            store.refreshConfigArtifacts()
            ensureSelection()
        }
        .onChange(of: store.providers) {
            ensureSelection()
        }
        .onChange(of: workspace) {
            searchText = ""
            ensureSelection()
        }
        .onChange(of: showsOnlyUnready) {
            ensureSelection()
        }
        .onChange(of: searchText) { ensureSelection() }
        .confirmationDialog(rollbackConfirmationTitle(count: rollbackableRows.count), isPresented: $confirmsRollback, titleVisibility: .visible) {
            Button("回滚 \(rollbackableRows.count) 个资源", role: .destructive) {
                rollbackSelectedResources(rollbackableRows)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前资源文件会被备份版本替换；Mihomo 会保留被替换版本供后续再次回滚。")
        }
    }

    private func header(_ presentation: ResourceTablePresentation) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("外部资源")
                    .font(MihomoUI.Fonts.pageTitle)
                Text(workspace.subtitle)
                    .font(MihomoUI.Fonts.pageSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if workspace == .nodeProviders {
                    ResourceCountBadge(title: "节点提供商", value: store.nodeProviders.count)
                    ResourceCountBadge(title: "当前配置", value: selectedNodeProviderCount)
                } else {
                    ResourceCountBadge(
                        title: workspace == .rules ? "规则" : "配置资源",
                        value: presentation.allRows.count
                    )
                    if workspace == .configResources {
                        ResourceCountBadge(title: "代理", value: presentation.proxyCount)
                    }
                    ResourceCountBadge(title: "规则", value: presentation.ruleCount)
                    ResourceCountBadge(title: "未就绪", value: presentation.unreadyCount)
                }
                Text("并发").foregroundStyle(.secondary)
                Stepper(value: resourceConcurrency, in: 1...12) {
                    Text("\(store.settings.resourceUpdateMaxConcurrent)").monospacedDigit().frame(width: 24)
                }
                .help("同时更新的 Provider 数量")
                if store.isResourceBatchOperationInProgress {
                    Button {
                        store.cancelResourceBatchOperation()
                    } label: {
                        Label("取消更新", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .help("停止派发新的资源请求，已开始的请求会完成或取消")
                }
            }
        }
    }

    private var resourceConcurrency: Binding<Int> {
        Binding(
            get: { store.settings.resourceUpdateMaxConcurrent },
            set: { value in
                var updated = store.settings
                updated.resourceUpdateMaxConcurrent = value
                Task { await store.saveSettings(updated) }
            }
        )
    }

    private func rollbackConfirmationTitle(count: Int) -> String {
        "回滚 \(count) 个资源？"
    }

    private func selectedResourcePane(_ presentation: ResourceTablePresentation) -> some View {
        Group {
            if let selectedRow = presentation.selectedRow(for: selectedResourceIDs) {
                let history = store.providerUpdateHistory(for: selectedRow.provider)
                let rollbackRecord = store.latestProviderRollbackRecord(for: selectedRow.provider)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Label(selectedRow.provider.name, systemImage: selectedRow.provider.kind == "Proxy" ? "point.3.connected.trianglepath.dotted" : "list.bullet.clipboard")
                            .font(.headline)
                            .lineLimit(1)

                        Text(selectedRow.detailText)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        Spacer()

                        Button {
                            Task { await store.rollbackProviderResource(selectedRow.provider) }
                        } label: {
                            Label("回滚", systemImage: "arrow.uturn.backward.circle")
                        }
                        .disabled(rollbackRecord == nil || store.isResourceBatchOperationInProgress)
                        .help(rollbackRecord?.backupPath ?? "没有可用备份")

                        Button {
                            Task { await store.refreshProviderResource(selectedRow.provider) }
                        } label: {
                            Label(selectedRow.updateActionTitle, systemImage: selectedRow.canDownload ? "arrow.down.circle" : "arrow.clockwise")
                        }
                        .disabled(selectedRow.canRefresh == false || store.isResourceBatchOperationInProgress)
                    }

                    ProviderHistoryPane(records: Array(history.prefix(6)))
                }
            } else {
                ContentUnavailableView(
                    showsOnlyUnready ? "没有需要处理的资源" : "选择一个资源",
                    systemImage: "shippingbox",
                    description: Text(showsOnlyUnready ? "关闭过滤可以查看全部资源。" : "选择资源后可查看路径、更新与回滚历史。")
                )
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
    }

    private func ensureSelection() {
        let visibleRows = resourcePresentation().visibleRows
        selectedResourceIDs = TableSelection.reconciled(
            selectedResourceIDs,
            visibleIDs: visibleRows.map(\.id),
            selectsFirstWhenEmpty: true
        )
    }

    private func refreshResources(_ rows: [ExternalResourceRow]) {
        let providers = rows.filter(\.canRefresh).map(\.provider)
        Task {
            await store.refreshProviderResources(providers)
        }
    }

    private func previewResources(_ rows: [ExternalResourceRow]) {
        QuickLookPreviewer.shared.present(resourceURLs(for: rows))
    }

    private func resourceURLs(for rows: [ExternalResourceRow]) -> [URL] {
        rows.compactMap { row in
            let path = row.provider.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard path.isEmpty == false else { return nil }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
    }

    private func rollbackableSelectedRows(
        in rows: [ExternalResourceRow]
    ) -> [ExternalResourceRow] {
        rows.filter { store.latestProviderRollbackRecord(for: $0.provider) != nil }
    }

    private func rollbackSelectedResources(_ rows: [ExternalResourceRow]) {
        let providers = rows.map(\.provider)
        Task {
            await store.rollbackProviderResources(providers)
        }
    }

    private var resourceContextMenuActions: [AppKitTableContextAction<ExternalResourceRow>] {
        [
            .init("更新", isEnabled: { _ in store.isResourceBatchOperationInProgress == false }) { rows in
                refreshResources(rows)
            },
            .init(
                "回滚",
                isDestructive: true,
                isEnabled: { rows in rows.contains { store.latestProviderRollbackRecord(for: $0.provider) != nil } }
            ) { rows in
                selectedResourceIDs = Set(rows.map(\.id))
                confirmsRollback = true
            },
            .init("快速查看", isEnabled: { resourceURLs(for: $0).isEmpty == false }) { rows in
                previewResources(rows)
            },
            .init("在 Finder 中显示", isEnabled: { resourceURLs(for: $0).isEmpty == false }) { rows in
                NSWorkspace.shared.activateFileViewerSelecting(resourceURLs(for: rows))
            }
        ]
    }

    private func commandContext(
        _ presentation: ResourceTablePresentation,
        selectedRows: [ExternalResourceRow]
    ) -> WorkspaceCommandContext {
        let selectedURLs = resourceURLs(for: selectedRows)
        return WorkspaceCommandContext(
            search: {
                searchIsFocused = true
                MihomoSearchFocus.request()
            },
            refresh: { refreshResources(selectedRows.isEmpty ? presentation.visibleRows : selectedRows) },
            activateSelection: searchIsFocused || selectedRows.isEmpty ? nil : { refreshResources(selectedRows) },
            previewSelection: searchIsFocused || selectedURLs.isEmpty ? nil : { previewResources(selectedRows) }
        )
    }

}
