import AppKit
import SwiftUI

struct ActivityView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AppStore
    @State private var selectedRowID: String?
    @State private var filterText = ""
    @State private var panelMode: ConnectionPanelMode = .active

    private var filteredConnections: [ConnectionItem] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return store.connections }
        return store.connections.filter { connection in
            [connection.host, connection.process, connection.network, connection.rule, connection.chain]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var tableRows: [ConnectionTableRow] {
        panelMode == .active ? filteredConnections.map(ConnectionTableRow.connection) : []
    }

    private var selectedConnection: ConnectionItem? {
        guard let selectedRowID,
              let row = tableRows.first(where: { $0.id == selectedRowID })
        else { return nil }
        return row.connection
    }

    var body: some View {
        let rows = tableRows

        VStack(spacing: 0) {
            connectionToolbar(rowCount: rows.count)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))

            connectionTable(rows: rows)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("活动")
        .onChange(of: selectedRowID) {
            if let selectedConnection {
                store.connectionDetailConnectionID = selectedConnection.id
                openWindow(id: "connection-detail")
            }
        }
    }

    private func connectionToolbar(rowCount: Int) -> some View {
        HStack(spacing: 12) {
            Picker("连接状态", selection: $panelMode) {
                ForEach(ConnectionPanelMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)

            Text("\(rowCount)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 36, alignment: .leading)
                .foregroundStyle(.secondary)

            Spacer(minLength: 20)

            Button {
                selectedRowID = nil
                Task { await store.closeAllConnections() }
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled(store.connections.isEmpty)
            .help("关闭全部连接")

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("过滤主机、进程、规则...", text: $filterText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(width: 430, height: 38)
            .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func connectionTable(rows: [ConnectionTableRow]) -> some View {
        AppKitTable(
            rows: rows,
            selection: $selectedRowID,
            columns: [
                .init(title: "进程", width: 210) { $0.processText },
                .init(title: "主机", width: 320) { $0.hostText },
                .init(title: "类型", width: 160) { $0.networkText },
                .init(title: "规则", width: 220) { $0.ruleText },
                .init(title: "代理链", width: 320) { $0.chainText },
                .init(title: "↑ 速度", width: 170) { $0.trafficText }
            ],
            onDoubleClick: { row in
                if let connection = row.connection {
                    store.connectionDetailConnectionID = connection.id
                    openWindow(id: "connection-detail")
                }
            },
            hasHorizontalScroller: true,
            borderType: .noBorder
        )
    }
}

private enum ConnectionPanelMode: String, CaseIterable, Identifiable {
    case active
    case closed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "活跃"
        case .closed: return "已关闭"
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

    var networkText: String {
        groupTitle == nil ? (connection?.network ?? "-") : ""
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
