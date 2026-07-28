import SwiftUI

struct ActivityView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var activityStore: RuntimeActivityStore
    @State private var selectedRowIDs: Set<String> = []
    @State private var filterText = ""
    @FocusState private var searchIsFocused: Bool
    @State private var grouping: ConnectionSidebarGrouping = .client
    @State private var selectedFilterID = ActivityConnectionFilter.allID
    @State private var moduleTab: ActivityModuleTab = .recent
    @State private var detailTab: ActivityConnectionDetailTab = .general
    @State private var showsConnectionDetail = true
    @State private var dnsFilter: ActivityDNSFilter = .all
    @State private var trafficGrouping: ActivityTrafficGrouping = .policy
    @State private var confirmsClearingRecent = false
    @State private var confirmsClosingAll = false
    @State private var confirmsClosingSelection = false
    @State private var cachedTableRows: [ConnectionTableRow] = []
    @State private var tableRowsInput: ActivityConnectionTableRowsInput?

    private var connectionSource: [ConnectionItem] {
        switch moduleTab {
        case .recent:
            return activityStore.recentConnections
        case .active, .dns, .traffic:
            return activityStore.connections
        }
    }

    private var sidebarItems: [ActivityConnectionFilter] {
        ActivityConnectionFilter.items(for: connectionSource, grouping: grouping)
    }

    private var scopedConnections: [ConnectionItem] {
        guard let selectedFilter = sidebarItems.first(where: { $0.id == selectedFilterID }) else {
            return connectionSource
        }
        return connectionSource.filter { selectedFilter.matches($0) }
    }

    private var filteredConnections: [ConnectionItem] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return scopedConnections }
        return scopedConnections.filter { connection in
            [
                connection.id,
                connection.host,
                connection.process,
                connection.processPath,
                connection.network,
                connection.metadataType,
                connection.rule,
                connection.chain,
                connection.sourceIP,
                connection.destinationIP,
                connection.remoteDestination
            ]
            .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var tableRows: [ConnectionTableRow] {
        cachedTableRows
    }

    private func rebuildTableRowsIfNeeded() {
        let sourceRevision = moduleTab == .recent
            ? activityStore.recentConnectionsRevision
            : activityStore.connectionsRevision
        let nextInput = ActivityConnectionTableRowsInput(
            sourceRevision: sourceRevision,
            filterText: filterText,
            selectedFilterID: selectedFilterID,
            moduleTab: moduleTab,
            grouping: grouping
        )
        guard nextInput != tableRowsInput else { return }

        tableRowsInput = nextInput
        cachedTableRows = ActivityConnectionTableRows.make(
            from: filteredConnections,
            activeConnectionIDs: activityStore.activeConnectionIDs
        )
    }

    private var selectedConnection: ConnectionItem? {
        guard selectedRowIDs.count == 1,
              let selectedRowID = selectedRowIDs.first,
              let row = tableRows.first(where: { $0.id == selectedRowID })
        else { return nil }
        return row.connection
    }

    private var selectedRows: [ConnectionTableRow] {
        tableRows.filter { selectedRowIDs.contains($0.id) }
    }

    private var selectedActiveConnections: [ConnectionItem] {
        selectedRows.map(\.connection).filter { activityStore.isActiveConnectionID($0.id) }
    }

    private var selectedConnectionIsActive: Bool {
        guard let selectedConnection else { return false }
        return activityStore.isActiveConnectionID(selectedConnection.id)
    }

    private func moduleItemCount(trafficRowCount: Int) -> Int {
        switch moduleTab {
        case .recent, .active:
            return tableRows.count
        case .dns:
            return Set(activityStore.recentConnections.map(\.host).filter { !$0.isEmpty }).count
        case .traffic:
            return trafficRowCount
        }
    }

    var body: some View {
        let rows = tableRows
        let trafficRows = moduleTab == .traffic
            ? ActivityTrafficPresentation.rows(
                samples: activityStore.policyTrafficSamples,
                grouping: trafficGrouping,
                searchText: filterText
            )
            : []

        return HStack(spacing: 0) {
            moduleSidebar
                .frame(width: 248)

            Divider()

            VStack(spacing: 0) {
                ActivityWorkspaceHeader(
                    selection: moduleTab,
                    rowCount: moduleItemCount(trafficRowCount: trafficRows.count),
                    searchText: $filterText,
                    searchIsFocused: $searchIsFocused,
                    selectModule: selectModule
                )
                moduleContent(rows: rows, trafficRows: trafficRows)
            }
        }
        .background(MihomoUI.pageBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("连接")
        .onAppear { rebuildTableRowsIfNeeded() }
        .onChange(of: activityStore.connectionsRevision) { rebuildTableRowsIfNeeded() }
        .onChange(of: activityStore.recentConnectionsRevision) { rebuildTableRowsIfNeeded() }
        .onChange(of: filterText) { rebuildTableRowsIfNeeded() }
        .onChange(of: selectedFilterID) { rebuildTableRowsIfNeeded() }
        .onChange(of: moduleTab) { rebuildTableRowsIfNeeded() }
        .onChange(of: grouping) { rebuildTableRowsIfNeeded() }
        .focusedSceneValue(\.workspaceCommands, commandContext)
        .confirmationDialog("清空最近请求？", isPresented: $confirmsClearingRecent, titleVisibility: .visible) {
            Button("清空记录", role: .destructive) {
                selectedRowIDs.removeAll()
                activityStore.clearRecentConnections()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除当前保存的最近请求记录，但不会关闭活动连接。")
        }
        .confirmationDialog("关闭全部活动连接？", isPresented: $confirmsClosingAll, titleVisibility: .visible) {
            Button("关闭全部", role: .destructive) {
                selectedRowIDs.removeAll()
                Task { await store.closeAllConnections() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有正在传输的连接都会立即中断，此操作无法撤销。")
        }
        .confirmationDialog("关闭所选连接？", isPresented: $confirmsClosingSelection, titleVisibility: .visible) {
            Button("关闭 \(selectedActiveConnections.count) 个连接", role: .destructive) {
                closeSelectedConnectionsImmediately()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所选活动连接会立即中断，此操作无法撤销。")
        }
        .onChange(of: selectedRowIDs) {
            store.connectionDetailConnectionID = selectedConnection?.id
            if selectedConnection != nil {
                showsConnectionDetail = true
            }
        }
        .onChange(of: grouping) {
            selectedFilterID = ActivityConnectionFilter.allID
            selectedRowIDs.removeAll()
        }
        .onChange(of: selectedFilterID) {
            selectedRowIDs.removeAll()
        }
        .onChange(of: filterText) {
            if selectedConnection == nil {
                selectedRowIDs = TableSelection.reconciled(
                    selectedRowIDs,
                    visibleIDs: tableRows.map(\.id)
                )
            }
        }
    }

    @ViewBuilder
    private var moduleSidebar: some View {
        switch moduleTab {
        case .recent, .active:
            ActivityConnectionSidebar(
                grouping: $grouping,
                selectedFilterID: $selectedFilterID,
                items: sidebarItems
            )
        case .dns:
            ActivityDNSSidebar(selection: $dnsFilter)
        case .traffic:
            ActivityTrafficSidebar(selection: $trafficGrouping)
        }
    }

    private func selectModule(_ tab: ActivityModuleTab) {
        moduleTab = tab
        selectedRowIDs.removeAll()
        filterText = ""
    }

    @ViewBuilder
    private func moduleContent(
        rows: [ConnectionTableRow],
        trafficRows: [ActivityTrafficRow]
    ) -> some View {
        switch moduleTab {
        case .recent, .active:
            ActivityConnectionTableSection(
                moduleTab: moduleTab,
                rows: rows,
                selection: $selectedRowIDs,
                showsConnectionDetail: $showsConnectionDetail,
                hasConnections: connectionSource.isEmpty == false,
                hasSelectedActiveConnections: selectedActiveConnections.isEmpty == false,
                selectedConnection: selectedConnection,
                clearOrCloseAll: {
                    if moduleTab == .recent {
                        confirmsClearingRecent = true
                    } else {
                        confirmsClosingAll = true
                    }
                },
                reload: { Task { await store.refreshController() } },
                requestCloseSelected: requestCloseSelectedConnections,
                focusRule: focusRuleInMain,
                focusResources: focusResourcesInMain,
                open: { row in
                    selectedRowIDs = [row.id]
                    openSelectedConnectionDetail()
                }
            )
            if let selectedConnection, showsConnectionDetail {
                ConnectionInlineDetailView(
                    connection: selectedConnection,
                    isActive: selectedConnectionIsActive,
                    tab: $detailTab,
                    close: { connection in
                        selectedRowIDs.removeAll()
                        Task { await store.closeConnection(connection.id) }
                    },
                    focusRule: focusRuleInMain,
                    focusResources: focusResourcesInMain
                )
                .frame(height: 292)
            }
        case .dns:
            ActivityDNSView(
                connections: activityStore.recentConnections.isEmpty
                    ? activityStore.connections
                    : activityStore.recentConnections,
                filter: dnsFilter,
                searchText: filterText
            )
        case .traffic:
            ActivityTrafficStatisticsView(
                grouping: trafficGrouping,
                rows: trafficRows
            )
        }
    }

    private var commandContext: WorkspaceCommandContext {
        WorkspaceCommandContext(
            search: {
                searchIsFocused = true
            },
            refresh: { Task { await store.refreshController() } },
            activateSelection: searchIsFocused || selectedConnection == nil ? nil : openSelectedConnectionDetail,
            previewSelection: searchIsFocused || selectedConnection == nil ? nil : openSelectedConnectionDetail,
            deleteSelection: searchIsFocused || selectedActiveConnections.isEmpty ? nil : requestCloseSelectedConnections
        )
    }

    private func openSelectedConnectionDetail() {
        guard let selectedConnection else { return }
        store.connectionDetailConnectionID = selectedConnection.id
        openWindow(id: "connection-detail")
    }

    private func focusRuleInMain(_ connection: ConnectionItem) {
        store.focusRule(for: connection)
        MainWindowPresenter.present(openWindow: openWindow)
    }

    private func focusResourcesInMain() {
        store.selectedSection = .resources
        MainWindowPresenter.present(openWindow: openWindow)
    }

    private func requestCloseSelectedConnections() {
        guard selectedActiveConnections.isEmpty == false else { return }
        if selectedActiveConnections.count > 1 {
            confirmsClosingSelection = true
        } else {
            closeSelectedConnectionsImmediately()
        }
    }

    private func closeSelectedConnectionsImmediately() {
        let ids = selectedActiveConnections.map(\.id)
        selectedRowIDs.subtract(ids)
        Task {
            for id in ids {
                await store.closeConnection(id)
            }
        }
    }
}
