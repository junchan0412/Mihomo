import AppKit
import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var activityStore: RuntimeActivityStore
    @State private var selectedRowID: String?
    @State private var filterText = ""
    @State private var grouping: ConnectionSidebarGrouping = .client
    @State private var selectedFilterID = ActivityConnectionFilter.allID
    @State private var moduleTab: ActivityModuleTab = .recent
    @State private var detailTab: ActivityConnectionDetailTab = .general
    @State private var dnsFilter: ActivityDNSFilter = .all
    @State private var trafficGrouping: ActivityTrafficGrouping = .policy

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
            .map { connection in
                ConnectionTableRow(
                    connection: connection,
                    isActive: activityStore.connections.contains { $0.id == connection.id }
                )
            }
    }

    private var selectedConnection: ConnectionItem? {
        guard let selectedRowID,
              let row = tableRows.first(where: { $0.id == selectedRowID })
        else { return nil }
        return row.connection
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
        .navigationTitle("活动")
        .onChange(of: selectedRowID) {
            store.connectionDetailConnectionID = selectedConnection?.id
        }
        .onChange(of: grouping) {
            selectedFilterID = ActivityConnectionFilter.allID
            selectedRowID = nil
        }
        .onChange(of: selectedFilterID) {
            selectedRowID = nil
        }
        .onChange(of: filterText) {
            if selectedConnection == nil {
                selectedRowID = nil
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

                connectionSearchField

                connectionCount(rowCount)
            }

            VStack(spacing: 8) {
                moduleTabs
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    connectionSearchField
                    Spacer(minLength: 8)
                    connectionCount(rowCount)
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
            selectedRowID = nil
            filterText = ""
        }
    }

    @ViewBuilder
    private func moduleContent(rows: [ConnectionTableRow]) -> some View {
        switch moduleTab {
        case .recent, .active:
            connectionTable(rows: rows)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            activityActionBar
            if let selectedConnection {
                ConnectionInlineDetailView(
                    connection: selectedConnection,
                    tab: $detailTab,
                    close: { connection in
                        selectedRowID = nil
                        Task { await store.closeConnection(connection.id) }
                    },
                    focusRule: { store.focusRule(for: $0) },
                    focusResources: { store.selectedSection = .resources }
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

    private var connectionSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索", text: $filterText)
                .textFieldStyle(.plain)
                .font(MihomoUI.Fonts.body)
        }
        .padding(.horizontal, 12)
        .frame(width: 240, height: 34)
        .background(MihomoUI.mutedFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
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
                selectedRowID = nil
                if moduleTab == .recent {
                    activityStore.clearRecentConnections()
                } else {
                    Task { await store.closeAllConnections() }
                }
            }
            .disabled(connectionSource.isEmpty)

            Button("重新载入") {
                Task { await store.refreshController() }
            }

            Button("关闭连接") {
                guard let selectedConnection else { return }
                selectedRowID = nil
                Task { await store.closeConnection(selectedConnection.id) }
            }
            .disabled(!selectedConnectionIsActive)

            Button("查看规则") {
                guard let selectedConnection else { return }
                store.focusRule(for: selectedConnection)
            }
            .disabled(selectedConnection == nil)

            Button("Provider") {
                store.selectedSection = .resources
            }
            .disabled(selectedConnection == nil)

            Spacer()

            Image(systemName: selectedConnection == nil ? "chevron.down" : "chevron.up")
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)
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
            selection: $selectedRowID,
            columns: [
                .init(title: "ID", width: 74, textColor: { $0.statusColor }) { $0.idText },
                .init(title: "时间", width: 86) { $0.timeText },
                .init(title: "客户端", width: 150) { $0.clientText },
                .init(title: "规则", width: 220) { $0.ruleText },
                .init(title: "策略", width: 150) { $0.policyText },
                .init(title: "上传", width: 78) { $0.uploadText },
                .init(title: "下载", width: 78) { $0.downloadText },
                .init(title: "时长", width: 78) { $0.durationText },
                .init(title: "方法", width: 82) { $0.methodText },
                .init(title: "地址", width: 300) { $0.addressText }
            ],
            onDoubleClick: { row in
                selectedRowID = row.id
            },
            hasHorizontalScroller: true,
            borderType: .noBorder
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
}
