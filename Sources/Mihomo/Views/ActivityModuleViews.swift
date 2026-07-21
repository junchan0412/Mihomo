import AppKit
import SwiftUI

enum ActivityDNSFilter: String, CaseIterable, Identifiable {
    case all
    case local
    case system
    case dynamic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .local: return "本地"
        case .system: return "系统"
        case .dynamic: return "动态"
        }
    }
}

enum ActivityTrafficGrouping: String, CaseIterable, Identifiable {
    case policy
    case process
    case networkAdapter
    case device
    case host

    var id: String { rawValue }

    var title: String {
        switch self {
        case .policy: return "策略"
        case .process: return "进程"
        case .networkAdapter: return "网络适配器"
        case .device: return "设备"
        case .host: return "主机名"
        }
    }

    var sampleKeyPath: KeyPath<PolicyTrafficSample, String> {
        switch self {
        case .policy: return \.policy
        case .process: return \.process
        case .networkAdapter: return \.network
        case .device: return \.source
        case .host: return \.host
        }
    }
}

struct ActivityDNSSidebar: View {
    @Binding var selection: ActivityDNSFilter

    var body: some View {
        ActivityTypeSidebar(
            title: "类型",
            items: ActivityDNSFilter.allCases,
            selection: $selection,
            label: \.title
        )
    }
}

struct ActivityTrafficSidebar: View {
    @Binding var selection: ActivityTrafficGrouping

    var body: some View {
        ActivityTypeSidebar(
            title: "类型",
            items: ActivityTrafficGrouping.allCases,
            selection: $selection,
            label: \.title
        )
    }
}

struct ActivityDNSView: View {
    @EnvironmentObject private var store: AppStore
    var connections: [ConnectionItem]
    var filter: ActivityDNSFilter
    var searchText: String

    private var rows: [ActivityDNSRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Dictionary(grouping: connections.filter { !$0.host.isEmpty }, by: \.host)
            .map { host, values in
                ActivityDNSRow(
                    kind: .dynamic,
                    host: host,
                    addresses: Array(Set(values.flatMap {
                        [$0.destinationIP, $0.remoteDestination].filter { !$0.isEmpty }
                    })).sorted(),
                    server: values.first?.sourceIP ?? "-"
                )
            }
            .filter { filter == .all || $0.kind == filter }
            .filter { row in
                guard !query.isEmpty else { return true }
                return row.host.localizedCaseInsensitiveContains(query)
                    || row.addresses.contains { $0.localizedCaseInsensitiveContains(query) }
                    || row.server.localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.host.localizedStandardCompare($1.host) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppKitTable(
                rows: rows,
                selection: .constant(nil),
                columns: [
                    .init(title: "类型", width: 82) { $0.kind.title },
                    .init(title: "域名", width: 300) { $0.host },
                    .init(title: "值", width: 460) { $0.addresses.isEmpty ? "-" : $0.addresses.joined(separator: ", ") },
                    .init(title: "DNS 服务器", width: 180) { $0.server },
                    .init(title: "注释", width: 160) { _ in "连接观测" }
                ],
                hasHorizontalScroller: true,
                borderType: .noBorder
            )
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView(
                        "暂无 DNS 记录",
                        systemImage: "network",
                        description: Text(dnsEmptyDescription)
                    )
                }
            }

            HStack(spacing: 8) {
                Button("重新载入") {
                    Task { await store.refreshController() }
                }
                Spacer()
                Text("显示 \(rows.count) 条\(filter.title) DNS 记录")
                    .foregroundStyle(.secondary)
            }
            .font(MihomoUI.Fonts.bodyMedium)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(.bar)
            .overlay(alignment: .top) {
                Rectangle().fill(MihomoUI.cardStroke).frame(height: 1)
            }
        }
    }

    private var dnsEmptyDescription: String {
        switch filter {
        case .all, .dynamic:
            return "核心返回连接后，这里会显示已观测到的域名与地址。"
        case .local:
            return "当前连接快照中没有本地 DNS 记录。"
        case .system:
            return "当前连接快照中没有系统 DNS 记录。"
        }
    }
}

struct ActivityTrafficStatisticsView: View {
    @EnvironmentObject private var activityStore: RuntimeActivityStore
    var grouping: ActivityTrafficGrouping
    var searchText: String

    private var rows: [ActivityTrafficRow] {
        let now = Date()
        let calendar = Calendar.current
        let windows = ActivityTrafficWindow.allCases.map { window in
            let start = window == .today
                ? calendar.startOfDay(for: now)
                : now.addingTimeInterval(-window.interval)
            return (window, totalsByName(since: start))
        }
        let names = Set(windows.flatMap { $0.1.keys })
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return names
            .filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
            .map { name in
                ActivityTrafficRow(
                    name: name,
                    values: Dictionary(uniqueKeysWithValues: windows.map { window, totals in
                        (window, totals[name] ?? ActivityTrafficValue())
                    })
                )
            }
            .sorted {
                $0.value(for: .today).total > $1.value(for: .today).total
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppKitTable(
                rows: rows,
                selection: .constant(nil),
                columns: [
                    .init(title: "名称", width: 108) { $0.name },
                    .init(title: "今天", width: 176) { $0.text(for: .today) },
                    .init(title: "5 分钟", width: 176) { $0.text(for: .fiveMinutes) },
                    .init(title: "15 分钟", width: 176) { $0.text(for: .fifteenMinutes) },
                    .init(title: "60 分钟", width: 176) { $0.text(for: .sixtyMinutes) },
                    .init(title: "6 小时", width: 176) { $0.text(for: .sixHours) },
                    .init(title: "12 小时", width: 176) { $0.text(for: .twelveHours) }
                ],
                hasHorizontalScroller: true,
                borderType: .noBorder
            )
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView(
                        "暂无流量统计",
                        systemImage: "chart.bar",
                        description: Text("流量会按\(grouping.title)聚合，并随连接数据自动刷新。")
                    )
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                Text("随连接数据自动刷新")
                Spacer()
                Text("\(rows.count) 个\(grouping.title)")
            }
            .font(MihomoUI.Fonts.bodyMedium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.bar)
            .overlay(alignment: .top) {
                Rectangle().fill(MihomoUI.cardStroke).frame(height: 1)
            }
        }
    }

    private func totalsByName(since date: Date) -> [String: ActivityTrafficValue] {
        Dictionary(uniqueKeysWithValues: activityStore
            .trafficTotals(since: date, key: grouping.sampleKeyPath)
            .map { total in
                (total.policy, ActivityTrafficValue(upload: total.uploadBytes, download: total.downloadBytes))
            })
    }
}

private struct ActivityTypeSidebar<Item: Identifiable & Hashable>: View {
    var title: String
    var items: [Item]
    @Binding var selection: Item
    var label: KeyPath<Item, String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(MihomoUI.Fonts.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.top, 18)

            ForEach(items) { item in
                Button {
                    selection = item
                } label: {
                    Text(item[keyPath: label])
                        .font(MihomoUI.Fonts.bodyMedium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == item ? MihomoUI.mutedFill : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.bar)
    }
}

private struct ActivityDNSRow: Identifiable, Hashable {
    var kind: ActivityDNSFilter
    var host: String
    var addresses: [String]
    var server: String
    var id: String { host }
}

private enum ActivityTrafficWindow: CaseIterable, Hashable {
    case today
    case fiveMinutes
    case fifteenMinutes
    case sixtyMinutes
    case sixHours
    case twelveHours

    var interval: TimeInterval {
        switch self {
        case .today: return 0
        case .fiveMinutes: return 5 * 60
        case .fifteenMinutes: return 15 * 60
        case .sixtyMinutes: return 60 * 60
        case .sixHours: return 6 * 60 * 60
        case .twelveHours: return 12 * 60 * 60
        }
    }
}

private struct ActivityTrafficValue: Hashable {
    var upload: Int64 = 0
    var download: Int64 = 0
    var total: Int64 { upload + download }
}

private struct ActivityTrafficRow: Identifiable, Hashable {
    var name: String
    var values: [ActivityTrafficWindow: ActivityTrafficValue]
    var id: String { name }

    func value(for window: ActivityTrafficWindow) -> ActivityTrafficValue {
        values[window] ?? ActivityTrafficValue()
    }

    func text(for window: ActivityTrafficWindow) -> String {
        let value = value(for: window)
        return "↑ \(Formatters.bytes(value.upload))  ↓ \(Formatters.bytes(value.download))"
    }
}
