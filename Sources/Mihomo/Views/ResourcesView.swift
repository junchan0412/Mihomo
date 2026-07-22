import AppKit
import SwiftUI

struct ResourcesView: View {
    @EnvironmentObject private var store: AppStore
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

    private var allRows: [ExternalResourceRow] {
        let records = latestRecords
        return store.providers.map { provider in
            ExternalResourceRow(provider: provider, latestRecord: records[store.providerHistoryKey(for: provider)])
        }
    }

    private var visibleRows: [ExternalResourceRow] {
        let readinessRows = showsOnlyUnready ? allRows.filter { $0.isReady == false } : allRows
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return readinessRows }
        return readinessRows.filter {
            $0.nameText.localizedCaseInsensitiveContains(query)
                || $0.typeText.localizedCaseInsensitiveContains(query)
                || $0.pathText.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedRow: ExternalResourceRow? {
        guard selectedResourceIDs.count == 1, let selectedResourceID = selectedResourceIDs.first else { return nil }
        return allRows.first { $0.id == selectedResourceID }
    }

    private var selectedRows: [ExternalResourceRow] {
        allRows.filter { selectedResourceIDs.contains($0.id) }
    }

    private var refreshableCount: Int {
        allRows.filter(\.canRefresh).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            resourceTablePane
            selectedResourcePane
        }
        .padding(.horizontal, MihomoUI.pageHorizontalPadding)
        .padding(.vertical, MihomoUI.pageVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("资源")
        .background(MihomoUI.pageBackground)
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索 Provider 或路径")
        .compatibleSearchFocused($searchIsFocused)
        .focusedSceneValue(\.workspaceCommands, commandContext)
        .onAppear {
            store.refreshConfigArtifacts()
            ensureSelection()
        }
        .onChange(of: store.providers) {
            ensureSelection()
        }
        .onChange(of: showsOnlyUnready) {
            ensureSelection()
        }
        .confirmationDialog("回滚所选资源？", isPresented: $confirmsRollback, titleVisibility: .visible) {
            Button("回滚 \(rollbackableSelectedRows.count) 个资源", role: .destructive) {
                rollbackSelectedResources()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前资源文件会被备份版本替换；Mihomo 会保留被替换版本供后续再次回滚。")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("外部资源")
                    .font(MihomoUI.Fonts.pageTitle)
                Text("统一管理配置引用的 Proxy Provider、Rule Provider、本地规则集与 Geo 数据。")
                    .font(MihomoUI.Fonts.pageSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                ResourceCountBadge(title: "Proxy", value: allRows.filter { $0.provider.kind == "Proxy" }.count)
                ResourceCountBadge(title: "Rule", value: allRows.filter { $0.provider.kind == "Rule" }.count)
                ResourceCountBadge(title: "未就绪", value: allRows.filter { $0.isReady == false }.count)
                Divider().frame(height: 22)
                Text("并发").foregroundStyle(.secondary)
                Stepper(value: resourceConcurrency, in: 1...12) {
                    Text("\(store.settings.resourceUpdateMaxConcurrent)").monospacedDigit().frame(width: 24)
                }
                .help("同时更新的 Provider 数量")
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

    private var resourceTablePane: some View {
        VStack(spacing: 0) {
            AppKitTable(
                rows: visibleRows,
                selection: $selectedResourceIDs,
                columns: [
                    .init(title: "名称", width: 160) { $0.nameText },
                    .init(title: "类型", width: 150) { $0.typeText },
                    .init(title: "最后更新", width: 150) { $0.lastUpdatedText },
                    .init(title: "状态", width: 150, textColor: statusTextColor) { $0.statusText },
                    .init(title: "路径", width: 420) { $0.pathText }
                ],
                allowsMultipleSelection: true,
                onDoubleClick: handleDoubleClick,
                onActivate: { rows in refreshResources(rows) },
                onPreview: { rows in previewResources(rows) },
                hasHorizontalScroller: true,
                contextMenuActions: resourceContextMenuActions
            )
            .frame(minHeight: 360, maxHeight: .infinity)
            .overlay {
                if visibleRows.isEmpty {
                    ContentUnavailableView(
                        showsOnlyUnready ? "没有未就绪资源" : "没有外部资源",
                        systemImage: "shippingbox",
                        description: Text(showsOnlyUnready ? "当前本地与远程资源均已就绪。" : "当前配置没有声明 Provider 或本地规则集。")
                    )
                }
            }

            Divider()

            bottomBar
        }
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Toggle("仅显示未就绪的项目", isOn: $showsOnlyUnready)
                .toggleStyle(.checkbox)

            Text("\(visibleRows.count)/\(allRows.count) 项")
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 16)

            Text(store.resourceUpdateStatus)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer()

            Button {
                Task { await store.updateAllExternalResources() }
            } label: {
                Label("全部更新", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(refreshableCount == 0)

            Button {
                refreshResources(selectedRows)
            } label: {
                Label("更新所选", systemImage: "arrow.clockwise")
            }
            .disabled(selectedRows.contains(where: \.canRefresh) == false)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var selectedResourcePane: some View {
        Group {
            if let selectedRow {
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
                    .disabled(rollbackRecord == nil)
                    .help(rollbackRecord?.backupPath ?? "没有可用备份")

                    Button {
                        Task { await store.refreshProviderResource(selectedRow.provider) }
                    } label: {
                        Label(selectedRow.updateActionTitle, systemImage: selectedRow.canDownload ? "arrow.down.circle" : "arrow.clockwise")
                    }
                    .disabled(selectedRow.canRefresh == false)
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
        let rows = visibleRows
        guard rows.isEmpty == false else {
            selectedResourceIDs.removeAll()
            return
        }
        selectedResourceIDs.formIntersection(Set(rows.map(\.id)))
        if selectedResourceIDs.isEmpty == false {
            return
        }
        if let firstID = rows.first?.id {
            selectedResourceIDs = [firstID]
        }
    }

    private func handleDoubleClick(_ row: ExternalResourceRow) {
        guard row.canRefresh else { return }
        Task { await store.refreshProviderResource(row.provider) }
    }

    private func refreshResources(_ rows: [ExternalResourceRow]) {
        let providers = rows.filter(\.canRefresh).map(\.provider)
        Task {
            for provider in providers {
                await store.refreshProviderResource(provider)
            }
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

    private var rollbackableSelectedRows: [ExternalResourceRow] {
        selectedRows.filter { store.latestProviderRollbackRecord(for: $0.provider) != nil }
    }

    private func rollbackSelectedResources() {
        let providers = rollbackableSelectedRows.map(\.provider)
        Task {
            for provider in providers {
                await store.rollbackProviderResource(provider)
            }
        }
    }

    private var resourceContextMenuActions: [AppKitTableContextAction<ExternalResourceRow>] {
        [
            .init("更新") { rows in
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

    private var commandContext: WorkspaceCommandContext {
        WorkspaceCommandContext(
            search: {
                searchIsFocused = true
                MihomoSearchFocus.request()
            },
            refresh: { refreshResources(selectedRows.isEmpty ? visibleRows : selectedRows) },
            activateSelection: searchIsFocused || selectedRows.isEmpty ? nil : { refreshResources(selectedRows) },
            previewSelection: searchIsFocused || resourceURLs(for: selectedRows).isEmpty ? nil : { previewResources(selectedRows) }
        )
    }

    private func statusTextColor(_ row: ExternalResourceRow) -> NSColor? {
        switch row.statusKind {
        case .ready:
            return .systemGreen
        case .pending:
            return .systemOrange
        case .failed:
            return .systemRed
        case .localOnly:
            return .secondaryLabelColor
        }
    }
}
