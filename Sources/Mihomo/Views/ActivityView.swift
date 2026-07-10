import AppKit
import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedRowID: String?
    @State private var filterText = ""
    @State private var grouping: ConnectionSidebarGrouping = .client
    @State private var selectedFilterID = ActivityConnectionFilter.allID
    @State private var moduleTab: ActivityModuleTab = .recent
    @State private var detailTab: ActivityConnectionDetailTab = .general

    private var sidebarItems: [ActivityConnectionFilter] {
        ActivityConnectionFilter.items(for: store.connections, grouping: grouping)
    }

    private var scopedConnections: [ConnectionItem] {
        guard let selectedFilter = sidebarItems.first(where: { $0.id == selectedFilterID }) else {
            return store.connections
        }
        return store.connections.filter { selectedFilter.matches($0) }
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
            .map(ConnectionTableRow.init(connection:))
    }

    private var selectedConnection: ConnectionItem? {
        guard let selectedRowID,
              let row = tableRows.first(where: { $0.id == selectedRowID })
        else { return nil }
        return row.connection
    }

    var body: some View {
        let rows = tableRows

        HStack(spacing: 0) {
            ActivityConnectionSidebar(
                grouping: $grouping,
                selectedFilterID: $selectedFilterID,
                items: sidebarItems
            )
            .frame(width: 260)

            Divider()

            VStack(spacing: 0) {
                connectionHeader(rowCount: rows.count)

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
                        focusRule: { connection in
                            store.focusRule(for: connection)
                        },
                        focusResources: {
                            store.selectedSection = .resources
                        }
                    )
                    .frame(height: 292)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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

    private func connectionHeader(rowCount: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                moduleTabs
                    .frame(maxWidth: 720, alignment: .leading)

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
            switch tab {
            case .recent, .active:
                moduleTab = tab
            case .dns:
                store.selectedSection = .advanced
            case .traffic:
                store.selectedSection = .overview
            case .logs:
                store.selectedSection = .logs
            case .devices:
                break
            }
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
            Button("清空") {
                selectedRowID = nil
                Task { await store.closeAllConnections() }
            }
            .disabled(store.connections.isEmpty)

            Button("重新载入") {
                Task { await store.refreshController() }
            }

            Button("关闭连接") {
                guard let selectedConnection else { return }
                selectedRowID = nil
                Task { await store.closeConnection(selectedConnection.id) }
            }
            .disabled(selectedConnection == nil)

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
                .init(title: "ID", width: 92, textColor: { $0.statusColor }) { $0.idText },
                .init(title: "时间", width: 86) { $0.timeText },
                .init(title: "客户端", width: 220) { $0.clientText },
                .init(title: "规则", width: 220) { $0.ruleText },
                .init(title: "策略", width: 220) { $0.policyText },
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
    }
}

private enum ConnectionSidebarGrouping: String, CaseIterable, Identifiable {
    case client
    case host

    var id: String { rawValue }

    var title: String {
        switch self {
        case .client: return "按客户端"
        case .host: return "按主机名"
        }
    }

    var sectionTitle: String {
        switch self {
        case .client: return "本地程序"
        case .host: return "远程主机"
        }
    }
}

private enum ActivityModuleTab: String, CaseIterable, Identifiable {
    case recent
    case active
    case dns
    case devices
    case traffic
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "最近的请求"
        case .active: return "活动连接"
        case .dns: return "DNS"
        case .devices: return "设备"
        case .traffic: return "流量统计"
        case .logs: return "日志簿"
        }
    }

    var isEnabled: Bool {
        self != .devices
    }
}

private struct ActivityModuleTabs: View {
    var selection: ActivityModuleTab
    var select: (ActivityModuleTab) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ActivityModuleTab.allCases) { tab in
                Button {
                    select(tab)
                } label: {
                    Text(tab.title)
                        .font(MihomoUI.Fonts.bodyMedium)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == tab ? MihomoUI.mutedFill : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!tab.isEnabled)
                .help(tab.title)
            }
        }
        .padding(4)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
    }
}

private struct ActivityConnectionFilter: Identifiable, Hashable {
    static let allID = "all"

    var id: String
    var title: String
    var detail: String
    var count: Int
    var upload: Int64
    var download: Int64
    var kind: Kind
    var representative: ConnectionItem?

    enum Kind: Hashable {
        case all
        case client(String)
        case host(String)
    }

    static func items(for connections: [ConnectionItem], grouping: ConnectionSidebarGrouping) -> [ActivityConnectionFilter] {
        let uploadTotal = connections.reduce(Int64(0)) { $0 + $1.upload }
        let downloadTotal = connections.reduce(Int64(0)) { $0 + $1.download }
        let all = ActivityConnectionFilter(
            id: allID,
            title: grouping == .client ? "所有客户端" : "所有主机名",
            detail: "\(Formatters.bytes(downloadTotal)) ↓  \(Formatters.bytes(uploadTotal)) ↑",
            count: connections.count,
            upload: uploadTotal,
            download: downloadTotal,
            kind: .all,
            representative: connections.first
        )

        let grouped = Dictionary(grouping: connections) { connection in
            grouping == .client ? connection.clientGroupingKey : connection.hostGroupingKey
        }

        let filters = grouped.map { key, values in
            let upload = values.reduce(Int64(0)) { $0 + $1.upload }
            let download = values.reduce(Int64(0)) { $0 + $1.download }
            return ActivityConnectionFilter(
                id: "\(grouping.rawValue):\(key)",
                title: key,
                detail: "\(Formatters.bytes(download)) ↓  \(Formatters.bytes(upload)) ↑",
                count: values.count,
                upload: upload,
                download: download,
                kind: grouping == .client ? .client(key) : .host(key),
                representative: values.first
            )
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return [all] + filters
    }

    func matches(_ connection: ConnectionItem) -> Bool {
        switch kind {
        case .all:
            return true
        case .client(let key):
            return connection.clientGroupingKey == key
        case .host(let key):
            return connection.hostGroupingKey == key
        }
    }
}

private struct ActivityConnectionSidebar: View {
    @Binding var grouping: ConnectionSidebarGrouping
    @Binding var selectedFilterID: String
    var items: [ActivityConnectionFilter]

    private var selectedFilter: ActivityConnectionFilter? {
        items.first { $0.id == selectedFilterID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("分组", selection: $grouping) {
                ForEach(ConnectionSidebarGrouping.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 7) {
                Text("请求")
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)

                if let all = items.first {
                    ActivityConnectionFilterRow(
                        item: all,
                        grouping: grouping,
                        isSelected: selectedFilterID == all.id
                    ) {
                        selectedFilterID = all.id
                    }
                    .padding(.horizontal, 10)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(grouping.sectionTitle)
                        .font(MihomoUI.Fonts.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.tertiary)
                        .imageScale(.small)
                }
                .padding(.horizontal, 18)

                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(items.dropFirst()) { item in
                            ActivityConnectionFilterRow(
                                item: item,
                                grouping: grouping,
                                isSelected: selectedFilterID == item.id
                            ) {
                                selectedFilterID = item.id
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .onChange(of: items) {
            guard selectedFilter == nil else { return }
            selectedFilterID = ActivityConnectionFilter.allID
        }
    }
}

private struct ActivityConnectionFilterRow: View {
    var item: ActivityConnectionFilter
    var grouping: ConnectionSidebarGrouping
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ActivityConnectionFilterIcon(item: item, grouping: grouping)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(MihomoUI.Fonts.bodyMedium)
                        .lineLimit(1)
                    Text(item.detail)
                        .font(MihomoUI.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text("\(item.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(item.title)
    }
}

private struct ActivityConnectionFilterIcon: View {
    var item: ActivityConnectionFilter
    var grouping: ConnectionSidebarGrouping

    var body: some View {
        Group {
            if case .all = item.kind {
                Image(systemName: grouping == .client ? "person.3.fill" : "globe")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            } else if grouping == .client, let icon = item.representative?.processIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: grouping == .client ? "app.dashed" : "network")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
        .padding(2)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private enum ActivityConnectionDetailTab: String, CaseIterable, Identifiable {
    case general
    case routing
    case address
    case process

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .routing: return "规则 & 链路"
        case .address: return "地址"
        case .process: return "进程"
        }
    }
}

private struct ConnectionTableRow: Identifiable, Hashable {
    var connection: ConnectionItem

    var id: String { connection.id }

    var idText: String {
        "● \(connection.id)"
    }

    var timeText: String {
        guard let start = connection.start else { return "-" }
        return Formatters.logTime.string(from: start)
    }

    var clientText: String {
        connection.processName
    }

    var ruleText: String {
        let type = connection.ruleType.isEmpty ? connection.rule : connection.ruleType
        let payload = connection.rulePayload
        if payload.isEmpty || payload == "-" {
            return type.isEmpty ? "-" : type
        }
        return "\(type) \(payload)"
    }

    var policyText: String {
        let last = connection.chain.components(separatedBy: " -> ").last ?? ""
        return last.isEmpty ? "DIRECT" : last
    }

    var uploadText: String {
        Formatters.bytes(connection.upload)
    }

    var downloadText: String {
        Formatters.bytes(connection.download)
    }

    var durationText: String {
        guard let start = connection.start else { return "-" }
        return Self.durationText(from: Date().timeIntervalSince(start))
    }

    var methodText: String {
        let text = connection.metadataType.isEmpty ? connection.network : connection.metadataType
        return text.isEmpty ? "-" : text.uppercased()
    }

    var addressText: String {
        connection.remoteEndpoint
    }

    var statusColor: NSColor {
        .systemGreen
    }

    private static func durationText(from interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 {
            return "\(seconds) s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) m"
        }
        return "\(minutes / 60) h"
    }
}

private struct ConnectionInlineDetailView: View {
    let connection: ConnectionItem
    @Binding var tab: ActivityConnectionDetailTab
    var close: (ConnectionItem) -> Void
    var focusRule: (ConnectionItem) -> Void
    var focusResources: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 158), spacing: 8, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            tabPicker
            detailGrid
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MihomoUI.pageBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MihomoUI.cardStroke)
                .frame(height: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))

                if let icon = connection.processIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .padding(3)
                } else {
                    Image(systemName: "network")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(connection.processName)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    ConnectionBadge(connection.displayMethod, tint: .green)
                    Text(connection.remoteEndpoint)
                        .font(MihomoUI.Fonts.bodyMedium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            ConnectionBadge("活跃", tint: .green)

            Button {
                close(connection)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("关闭此连接")
        }
    }

    private var tabPicker: some View {
        HStack {
            Picker("连接详情", selection: $tab) {
                ForEach(ActivityConnectionDetailTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 410)

            Spacer()

            Button {
                focusRule(connection)
            } label: {
                Label("查看规则", systemImage: "list.bullet.rectangle")
            }
            .disabled(connection.ruleType.isEmpty && connection.rule.isEmpty)

            Button {
                focusResources()
            } label: {
                Label("Provider", systemImage: "shippingbox")
            }
        }
        .controlSize(.small)
        .font(MihomoUI.Fonts.bodyMedium)
    }

    @ViewBuilder
    private var detailGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(cards) { card in
                    ConnectionDetailCard(card: card)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var cards: [ConnectionDetailCardModel] {
        switch tab {
        case .general:
            return [
                .init(title: "HTTP", rows: [
                    ("方法", connection.displayMethod),
                    ("状态码", "N/A")
                ]),
                .init(title: "总流量", rows: [
                    ("上传", Formatters.bytes(connection.upload)),
                    ("下载", Formatters.bytes(connection.download))
                ]),
                .init(title: "规则", rows: [
                    ("规则", connection.ruleDisplay),
                    ("策略", connection.policyDisplay)
                ]),
                .init(title: "远程地址", rows: [
                    ("远程地址", connection.remoteEndpoint),
                    ("目标 IP", connection.destinationIPDisplay),
                    ("目标端口", connection.destinationPortDisplay)
                ]),
                .init(title: "客户端地址", rows: [
                    ("出站地址", connection.sourceIPDisplay),
                    ("客户端地址", connection.sourceEndpoint)
                ]),
                .init(title: "时间", rows: [
                    ("开始时间", connection.startText),
                    ("时长", connection.durationText)
                ]),
                .init(title: "进程", rows: [
                    ("名称", connection.processName),
                    ("路径", connection.processPathDisplay)
                ]),
                .init(title: "杂项", rows: [
                    ("连接 ID", connection.id),
                    ("主机名", connection.hostDisplay),
                    ("网络", connection.networkDisplay)
                ])
            ]
        case .routing:
            return [
                .init(title: "规则", rows: [
                    ("类型", connection.ruleTypeDisplay),
                    ("内容", connection.rulePayloadDisplay),
                    ("完整", connection.ruleDisplay)
                ]),
                .init(title: "策略链", rows: [
                    ("链路", connection.chainDisplay),
                    ("出站", connection.policyDisplay)
                ]),
                .init(title: "Provider", rows: [
                    ("类型", connection.ruleTypeDisplay),
                    ("名称", connection.rulePayloadDisplay)
                ])
            ]
        case .address:
            return [
                .init(title: "客户端地址", rows: [
                    ("源地址", connection.sourceEndpoint),
                    ("源 IP", connection.sourceIPDisplay),
                    ("源端口", connection.sourcePortDisplay)
                ]),
                .init(title: "远程地址", rows: [
                    ("主机名", connection.hostDisplay),
                    ("目标 IP", connection.destinationIPDisplay),
                    ("目标端口", connection.destinationPortDisplay)
                ]),
                .init(title: "远程目标", rows: [
                    ("地址", connection.remoteDestinationDisplay),
                    ("展示", connection.remoteEndpoint)
                ])
            ]
        case .process:
            return [
                .init(title: "客户端", rows: [
                    ("进程", connection.processName),
                    ("路径", connection.processPathDisplay)
                ]),
                .init(title: "连接", rows: [
                    ("ID", connection.id),
                    ("开始", connection.startText),
                    ("时长", connection.durationText)
                ]),
                .init(title: "传输", rows: [
                    ("上传", Formatters.bytes(connection.upload)),
                    ("下载", Formatters.bytes(connection.download)),
                    ("合计", Formatters.bytes(connection.upload + connection.download))
                ])
            ]
        }
    }
}

private struct ConnectionBadge: View {
    var title: String
    var tint: Color

    init(_ title: String, tint: Color) {
        self.title = title
        self.tint = tint
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct ConnectionDetailCardModel: Identifiable {
    var id: String { title }
    var title: String
    var rows: [(String, String)]
}

private struct ConnectionDetailCard: View {
    var card: ConnectionDetailCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(card.title)
                .font(MihomoUI.Fonts.caption)
                .foregroundStyle(.secondary)

            ForEach(card.rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(row.0)：")
                        .foregroundStyle(.secondary)
                    Text(row.1.isEmpty ? "-" : row.1)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
        }
        .font(MihomoUI.Fonts.body)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .padding(10)
        .background(MihomoUI.mutedFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension ConnectionItem {
    var processName: String {
        if process.isEmpty || process == "-" {
            return processPathDisplay == "-" ? "未知客户端" : URL(fileURLWithPath: processPathDisplay).lastPathComponent
        }
        if process.contains("/") {
            return URL(fileURLWithPath: process).lastPathComponent
        }
        return process
    }

    var processPathDisplay: String {
        if processPath.isEmpty {
            return process.contains("/") ? process : "-"
        }
        return processPath
    }

    var clientGroupingKey: String {
        processName
    }

    var hostGroupingKey: String {
        if hostDisplay != "-" {
            return hostDisplay
        }
        let remoteHost = remoteEndpoint.split(separator: ":").first.map(String.init) ?? ""
        return remoteHost.isEmpty ? "未知主机" : remoteHost
    }

    var processIcon: NSImage? {
        guard let path = processIconPath else { return nil }
        return ConnectionProcessIconCache.icon(for: path)
    }

    private var processIconPath: String? {
        let path = processPathDisplay
        guard path != "-" && path.isEmpty == false else { return nil }

        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if let appIndex = parts.firstIndex(where: { $0.hasSuffix(".app") }) {
            let appPath = parts.prefix(appIndex + 1).joined(separator: "/")
            if FileManager.default.fileExists(atPath: appPath) {
                return appPath
            }
        }

        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    var hostDisplay: String {
        host.isEmpty ? "-" : host
    }

    var networkDisplay: String {
        network.isEmpty ? "-" : network.uppercased()
    }

    var displayMethod: String {
        let value = metadataType.isEmpty ? network : metadataType
        return value.isEmpty ? "-" : value.uppercased()
    }

    var ruleTypeDisplay: String {
        ruleType.isEmpty ? "-" : ruleType
    }

    var rulePayloadDisplay: String {
        rulePayload.isEmpty ? "-" : rulePayload
    }

    var ruleDisplay: String {
        if rule.isEmpty || rule == "-" {
            return [ruleType, rulePayload].filter { !$0.isEmpty }.joined(separator: " ").nilIfEmpty ?? "-"
        }
        return rule
    }

    var chainDisplay: String {
        chain.isEmpty ? "-" : chain
    }

    var policyDisplay: String {
        let policy = chain.components(separatedBy: " -> ").last ?? ""
        return policy.isEmpty ? "DIRECT" : policy
    }

    var sourceIPDisplay: String {
        sourceIP.isEmpty ? "-" : sourceIP
    }

    var sourcePortDisplay: String {
        sourcePort.isEmpty ? "-" : sourcePort
    }

    var destinationIPDisplay: String {
        destinationIP.isEmpty ? "-" : destinationIP
    }

    var destinationPortDisplay: String {
        destinationPort.isEmpty ? "-" : destinationPort
    }

    var remoteDestinationDisplay: String {
        remoteDestination.isEmpty ? "-" : remoteDestination
    }

    var sourceEndpoint: String {
        endpoint(host: sourceIP, port: sourcePort)
    }

    var remoteEndpoint: String {
        if remoteDestination.isEmpty == false {
            return remoteDestination
        }
        return endpoint(host: hostDisplay == "-" ? destinationIP : hostDisplay, port: destinationPort)
    }

    var startText: String {
        guard let start else { return "-" }
        return Formatters.shortDate.string(from: start)
    }

    var durationText: String {
        guard let start else { return "-" }
        let seconds = max(0, Int(Date().timeIntervalSince(start).rounded()))
        if seconds < 60 {
            return "\(seconds) s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) m"
        }
        return "\(minutes / 60) h"
    }

    private func endpoint(host: String, port: String) -> String {
        let cleanHost = host.isEmpty ? "-" : host
        guard port.isEmpty == false, cleanHost != "-" else {
            return cleanHost
        }
        return "\(cleanHost):\(port)"
    }
}

private enum ConnectionProcessIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
