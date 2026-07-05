import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedConnectionID: String?
    @State private var filterText = ""
    @State private var inspectorVisible = true

    private var filteredConnections: [ConnectionItem] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return store.connections }
        return store.connections.filter { connection in
            [connection.host, connection.process, connection.network, connection.rule, connection.chain]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var selectedConnection: ConnectionItem? {
        guard let selectedConnectionID else { return nil }
        return store.connections.first { $0.id == selectedConnectionID }
    }

    var body: some View {
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
            }

            GroupBox("实时流量") {
                TrafficGraphView(samples: store.trafficSamples)
                    .frame(height: 140)
            }

            HStack {
                TextField("按域名、进程、规则或链路过滤", text: $filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)

                Toggle("详情", isOn: $inspectorVisible)
                    .toggleStyle(.switch)

                Spacer()
            }

            AppKitTable(
                rows: filteredConnections,
                selection: $selectedConnectionID,
                columns: [
                    .init(title: "主机", width: 230) { $0.host },
                    .init(title: "进程", width: 170) { $0.process },
                    .init(title: "规则", width: 170) { $0.rule },
                    .init(title: "链路", width: 280) { $0.chain.isEmpty ? "-" : $0.chain },
                    .init(title: "流量", width: 190) { "\($0.download.byteString) ↓  \($0.upload.byteString) ↑" }
                ]
            )
            .overlay {
                if filteredConnections.isEmpty {
                    ContentUnavailableView("没有连接", systemImage: "waveform.path.ecg")
                }
            }
        }
        .padding(24)
        .navigationTitle("活动")
        .inspector(isPresented: $inspectorVisible) {
            ConnectionInspectorView(connection: selectedConnection) { connection in
                Task { await store.closeConnection(connection.id) }
            }
        }
    }
}

struct ConnectionInspectorView: View {
    var connection: ConnectionItem?
    var close: (ConnectionItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let connection {
                Text("连接详情")
                    .font(.headline)
                DetailRow(title: "主机", value: connection.host)
                DetailRow(title: "进程", value: connection.process)
                DetailRow(title: "网络", value: connection.network)
                DetailRow(title: "规则", value: connection.rule)
                DetailRow(title: "链路", value: connection.chain.isEmpty ? "-" : connection.chain)
                DetailRow(title: "下载", value: Formatters.bytes(connection.download))
                DetailRow(title: "上传", value: Formatters.bytes(connection.upload))
                if let start = connection.start {
                    DetailRow(title: "开始时间", value: Formatters.shortDate.string(from: start))
                }

                Spacer()

                Button("关闭此连接") {
                    close(connection)
                }
                .buttonStyle(.borderedProminent)
            } else {
                ContentUnavailableView("未选择连接", systemImage: "sidebar.right")
            }
        }
        .padding()
        .frame(minWidth: 260, alignment: .leading)
    }
}

struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Int64 {
    var byteString: String { Formatters.bytes(self) }
}
