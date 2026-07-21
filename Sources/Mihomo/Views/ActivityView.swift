import AppKit
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
        filteredConnections
            .sorted { lhs, rhs in
                switch (lhs.start, rhs.start) {
                case let (lhs?, rhs?):
                    return lhs > rhs
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.id.localizedStandardCompare(rhs.id) == .orderedDescending
                }
            }
            .enumerated().map { offset, connection in
                ConnectionTableRow(
                    connection: connection,
                    isActive: activityStore.connections.contains { $0.id == connection.id },
                    sequence: offset + 1
                )
            }
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
        selectedRows.map(\.connection).filter { connection in
            activityStore.connections.contains { $0.id == connection.id }
        }
    }

    private var selectedConnectionIsActive: Bool {
        guard let selectedConnection else { return false }
        return activityStore.connections.contains { $0.id == selectedConnection.id }
    }

    private var moduleItemCount: Int {
        switch moduleTab {
        case .recent, .active:
            return tableRows.count
        case .dns:
            return Set(activityStore.recentConnections.map(\.host).filter { !$0.isEmpty }).count
        case .traffic:
            return activityStore.trafficTotals(
                since: Calendar.current.startOfDay(for: Date()),
                key: trafficGrouping.sampleKeyPath
            ).count
        }
    }

    var body: some View {
        let rows = tableRows

        HStack(spacing: 0) {
            moduleSidebar
                .frame(width: 248)

            Divider()

            VStack(spacing: 0) {
                connectionHeader(rowCount: moduleItemCount)
                moduleContent(rows: rows)
            }
        }
        .background(MihomoUI.pageBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("连接")
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
                selectedRowIDs = selectedRowIDs.intersection(Set(tableRows.map(\.id)))
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

    private func connectionHeader(rowCount: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                moduleTabs
                    .frame(minWidth: 480, maxWidth: 720, alignment: .leading)

                Spacer(minLength: 10)
                connectionCount(rowCount)
                connectionSearchField
            }

            VStack(spacing: 8) {
                moduleTabs
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Spacer(minLength: 8)
                    connectionCount(rowCount)
                    connectionSearchField
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MihomoUI.cardStroke)
                .frame(height: 1)
        }
    }

    private var moduleTabs: some View {
        ActivityModuleTabs(selection: moduleTab) { tab in
            moduleTab = tab
            selectedRowIDs.removeAll()
            filterText = ""
        }
    }

    private var connectionSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("搜索", text: $filterText)
                .textFieldStyle(.plain)
                .focused($searchIsFocused)
                .accessibilityLabel("搜索连接、客户端、规则或地址")

            if filterText.isEmpty == false {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 230, height: 28)
        .background(MihomoUI.mutedFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func moduleContent(rows: [ConnectionTableRow]) -> some View {
        switch moduleTab {
        case .recent, .active:
            connectionTable(rows: rows)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            activityActionBar
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
                searchText: filterText
            )
        }
    }

    private func connectionCount(_ rowCount: Int) -> some View {
        Text("\(rowCount)")
            .font(MihomoUI.Fonts.bodyMedium)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(minWidth: 42, alignment: .trailing)
    }

    private var activityActionBar: some View {
        HStack(spacing: 8) {
            Button(moduleTab == .recent ? "清空记录" : "关闭全部") {
                if moduleTab == .recent {
                    confirmsClearingRecent = true
                } else {
                    confirmsClosingAll = true
                }
            }
            .disabled(connectionSource.isEmpty)

            Button("重新载入") {
                Task { await store.refreshController() }
            }

            Button("关闭连接") {
                requestCloseSelectedConnections()
            }
            .disabled(selectedActiveConnections.isEmpty)

            Button("查看规则") {
                guard let selectedConnection else { return }
                focusRuleInMain(selectedConnection)
            }
            .disabled(selectedConnection == nil)

            Button("Provider") {
                focusResourcesInMain()
            }
            .disabled(selectedConnection == nil)

            Spacer()

            Button {
                showsConnectionDetail.toggle()
            } label: {
                Image(systemName: showsConnectionDetail ? "chevron.down" : "chevron.up")
            }
            .buttonStyle(.borderless)
            .help(showsConnectionDetail ? "收起连接详情" : "展开连接详情")
            .disabled(selectedConnection == nil)
        }
        .font(MihomoUI.Fonts.bodyMedium)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MihomoUI.cardStroke)
                .frame(height: 1)
        }
    }

    private func connectionTable(rows: [ConnectionTableRow]) -> some View {
        AppKitTable(
            rows: rows,
            selection: $selectedRowIDs,
            columns: [
                .init(title: "ID", width: 74, textColor: { $0.statusColor }) { $0.idText },
                .init(title: "时间", width: 86) { $0.timeText },
                .init(title: "客户端", width: 150, image: { $0.clientIcon }) { $0.clientText },
                .init(title: "规则", width: 220) { $0.ruleText },
                .init(title: "策略", width: 150) { $0.policyText },
                .init(title: "上传", width: 78) { $0.uploadText },
                .init(title: "下载", width: 78) { $0.downloadText },
                .init(title: "时长", width: 78) { $0.durationText },
                .init(title: "方法", width: 82) { $0.methodText },
                .init(title: "地址", width: 300) { $0.addressText }
            ],
            allowsMultipleSelection: true,
            onDoubleClick: { row in
                selectedRowIDs = [row.id]
                openSelectedConnectionDetail()
            },
            onActivate: { selectedRows in
                guard let row = selectedRows.first else { return }
                selectedRowIDs = [row.id]
                openSelectedConnectionDetail()
            },
            onPreview: { selectedRows in
                guard let row = selectedRows.first else { return }
                selectedRowIDs = [row.id]
                openSelectedConnectionDetail()
            },
            onDelete: { _ in
                requestCloseSelectedConnections()
            },
            hasHorizontalScroller: true,
            borderType: .noBorder,
            contextMenuActions: connectionContextMenuActions
        )
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(
                    moduleTab == .recent ? "暂无最近请求" : "暂无活动连接",
                    systemImage: "network",
                    description: Text(moduleTab == .recent ? "新的连接请求会显示在这里。" : "核心当前没有活动连接。")
                )
            }
        }
    }

    private var connectionContextMenuActions: [AppKitTableContextAction<ConnectionTableRow>] {
        [
            .init(
                "关闭所选连接",
                isDestructive: true,
                isEnabled: { rows in rows.contains(where: { row in activityStore.connections.contains { $0.id == row.id } }) }
            ) { _ in
                requestCloseSelectedConnections()
            },
            .init("复制地址") { rows in
                let addresses = rows.map(\.addressText).filter { $0.isEmpty == false }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(addresses.joined(separator: "\n"), forType: .string)
            },
            .init("查看规则", isEnabled: { $0.count == 1 }) { rows in
                guard let connection = rows.first?.connection else { return }
                focusRuleInMain(connection)
            },
            .init("定位 Provider", isEnabled: { $0.count == 1 }) { _ in
                focusResourcesInMain()
            }
        ]
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
