import AppKit
import SwiftUI

struct ActivityView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AppStore
    @State private var selectedRowID: String?
    @State private var filterText = ""
    @State private var groupMode: ConnectionGroupMode = .none

    private var filteredConnections: [ConnectionItem] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return store.connections }
        return store.connections.filter { connection in
            [connection.host, connection.process, connection.network, connection.rule, connection.chain]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var tableRows: [ConnectionTableRow] {
        guard groupMode != .none else {
            return filteredConnections.map(ConnectionTableRow.connection)
        }

        let grouped = Dictionary(grouping: filteredConnections) { groupMode.groupKey(for: $0) }
        return grouped.keys.sorted().flatMap { key -> [ConnectionTableRow] in
            let connections = grouped[key] ?? []
            let download = connections.reduce(Int64(0)) { $0 + $1.download }
            let upload = connections.reduce(Int64(0)) { $0 + $1.upload }
            let header = ConnectionTableRow.group(title: key, count: connections.count, download: download, upload: upload)
            return [header] + connections.map(ConnectionTableRow.connection)
        }
    }

    private var selectedConnection: ConnectionItem? {
        guard let selectedRowID,
              let row = tableRows.first(where: { $0.id == selectedRowID })
        else { return nil }
        return row.connection
    }

    var body: some View {
        let rows = tableRows

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("活动")
                        .font(.largeTitle.bold())
                    Text("\(store.connections.count) 个连接 · ↓ \(Formatters.rate(store.downloadRate)) · ↑ \(Formatters.rate(store.uploadRate))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("刷新") {
                    Task { await store.refreshController() }
                }
                Button("关闭全部") {
                    Task { await store.closeAllConnections() }
                }
            }

            HStack(spacing: 12) {
                StatusCard(title: "连接", value: "\(store.connections.count)", systemImage: "link", isGood: true)
                StatusCard(title: "下载", value: Formatters.rate(store.downloadRate), systemImage: "arrow.down", isGood: true)
                StatusCard(title: "上传", value: Formatters.rate(store.uploadRate), systemImage: "arrow.up", isGood: true)
                StatusCard(title: "事件流", value: store.controllerEventStreamStatus, systemImage: "bolt.horizontal", isGood: store.controllerEventStreamStatus == "实时")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("实时流量")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                TrafficGraphView(samples: store.trafficSamples)
                    .frame(height: 170)
                    .padding(10)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                TextField("按域名、进程、规则或链路过滤", text: $filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)

                Picker("分组", selection: $groupMode) {
                    ForEach(ConnectionGroupMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                if selectedConnection != nil {
                    Button {
                        selectedRowID = nil
                    } label: {
                        Label("收起详情", systemImage: "sidebar.right")
                    }
                }

                Spacer()
            }

            connectionTable(rows: rows)
                .frame(minHeight: 260, maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("活动")
        .onChange(of: selectedRowID) {
            if let selectedConnection {
                store.connectionDetailConnectionID = selectedConnection.id
                openWindow(id: "connection-detail")
            }
        }
    }

    private func connectionTable(rows: [ConnectionTableRow]) -> some View {
        AppKitTable(
            rows: rows,
            selection: $selectedRowID,
            columns: [
                .init(title: "主机/分组", width: 230) { $0.hostText },
                .init(title: "进程", width: 150) { $0.processText },
                .init(title: "规则", width: 180) { $0.ruleText },
                .init(title: "链路", width: 240) { $0.chainText }
            ],
            onDoubleClick: { row in
                if let connection = row.connection {
                    store.connectionDetailConnectionID = connection.id
                    openWindow(id: "connection-detail")
                }
            },
            hasHorizontalScroller: false
        )
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView("没有连接", systemImage: "waveform.path.ecg")
            }
        }
    }
}

private enum ConnectionGroupMode: String, CaseIterable, Identifiable {
    case none
    case process
    case rule
    case chain
    case network

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "不分组"
        case .process: return "进程"
        case .rule: return "规则"
        case .chain: return "链路"
        case .network: return "网络"
        }
    }

    func groupKey(for connection: ConnectionItem) -> String {
        switch self {
        case .none: return ""
        case .process: return connection.process.isEmpty ? "-" : connection.process
        case .rule: return connection.rule.isEmpty ? "-" : connection.rule
        case .chain: return connection.chain.isEmpty ? "-" : connection.chain
        case .network: return connection.network.isEmpty ? "-" : connection.network
        }
    }
}

private struct ConnectionTableRow: Identifiable, Hashable {
    var id: String
    var connection: ConnectionItem?
    var groupTitle: String?
    var groupCount = 0
    var groupDownload: Int64 = 0
    var groupUpload: Int64 = 0

    static func connection(_ connection: ConnectionItem) -> ConnectionTableRow {
        ConnectionTableRow(id: "connection-\(connection.id)", connection: connection)
    }

    static func group(title: String, count: Int, download: Int64, upload: Int64) -> ConnectionTableRow {
        ConnectionTableRow(
            id: "group-\(title)",
            connection: nil,
            groupTitle: title,
            groupCount: count,
            groupDownload: download,
            groupUpload: upload
        )
    }

    var hostText: String {
        if let groupTitle {
            return "▸ \(groupTitle)（\(groupCount)）"
        }
        return connection?.host ?? "-"
    }

    var processText: String {
        groupTitle == nil ? (connection?.process ?? "-") : ""
    }

    var ruleText: String {
        groupTitle == nil ? (connection?.rule ?? "-") : ""
    }

    var chainText: String {
        guard groupTitle == nil else { return "" }
        return connection?.chain.isEmpty == false ? connection?.chain ?? "-" : "-"
    }

    var trafficText: String {
        if groupTitle != nil {
            return "\(Formatters.bytes(groupDownload)) ↓  \(Formatters.bytes(groupUpload)) ↑"
        }
        guard let connection else { return "-" }
        return "\(Formatters.bytes(connection.download)) ↓  \(Formatters.bytes(connection.upload)) ↑"
    }
}
