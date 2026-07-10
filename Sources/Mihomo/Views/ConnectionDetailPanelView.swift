import SwiftUI

struct ConnectionDetailPanelView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var activityStore: RuntimeActivityStore
    @State private var tab: ConnectionDetailTab = .summary

    private var connection: ConnectionItem? {
        guard let id = store.connectionDetailConnectionID else { return nil }
        return activityStore.connections.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("连接详情")
                        .font(.title3.bold())
                    Text(connection?.host ?? "未选择连接")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Picker("视图", selection: $tab) {
                    ForEach(ConnectionDetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                .labelsHidden()
            }
            .padding(16)

            Divider()

            ConnectionInspectorView(connection: connection, tab: tab) { connection in
                Task { await store.closeConnection(connection.id) }
            } focusRule: { connection in
                store.focusRule(for: connection)
            } focusResources: {
                store.selectedSection = .resources
            }
        }
        .frame(minWidth: 520, minHeight: 520)
    }
}

private enum ConnectionDetailTab: String, CaseIterable, Identifiable {
    case summary
    case rule
    case route

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: return "摘要"
        case .rule: return "规则"
        case .route: return "链路"
        }
    }
}

private struct ConnectionInspectorView: View {
    var connection: ConnectionItem?
    var tab: ConnectionDetailTab = .summary
    var close: (ConnectionItem) -> Void
    var focusRule: (ConnectionItem) -> Void = { _ in }
    var focusResources: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let connection {
                Text("连接详情")
                    .font(.headline)
                HStack(spacing: 10) {
                    TrafficValueTile(title: "下载", value: Formatters.bytes(connection.download), systemImage: "arrow.down", color: .blue)
                    TrafficValueTile(title: "上传", value: Formatters.bytes(connection.upload), systemImage: "arrow.up", color: .green)
                }

                switch tab {
                case .summary:
                    DetailRow(title: "主机", value: connection.host)
                    DetailRow(title: "进程", value: connection.process)
                    DetailRow(title: "网络", value: connection.network)
                    if let start = connection.start {
                        DetailRow(title: "开始时间", value: Formatters.shortDate.string(from: start))
                    }
                case .rule:
                    DetailRow(title: "规则", value: connection.rule)
                    DetailRow(title: "规则类型", value: connection.ruleType.isEmpty ? "-" : connection.ruleType)
                    DetailRow(title: "规则内容", value: connection.rulePayload.isEmpty ? "-" : connection.rulePayload)
                case .route:
                    DetailRow(title: "链路", value: connection.chain.isEmpty ? "-" : connection.chain)
                    DetailRow(title: "出站", value: connection.chain.components(separatedBy: " -> ").last ?? "-")
                }

                Spacer()

                HStack(spacing: 8) {
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

private struct TrafficValueTile: View {
    var title: String
    var value: String
    var systemImage: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DetailRow: View {
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
