import SwiftUI

struct PoliciesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedRowID: String?
    @State private var searchText = ""
    @State private var sortMode: PolicySortMode = .group

    private var allRows: [PolicyTableRow] {
        store.proxyGroups.flatMap { group in
            group.all.map { PolicyTableRow(group: group, node: $0) }
        }
    }

    private var rows: [PolicyTableRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? allRows : allRows.filter { row in
            row.group.name.localizedCaseInsensitiveContains(query)
                || row.group.now.localizedCaseInsensitiveContains(query)
                || row.node.name.localizedCaseInsensitiveContains(query)
                || row.node.type.localizedCaseInsensitiveContains(query)
        }

        return filtered.sorted { lhs, rhs in
            switch sortMode {
            case .group:
                if lhs.group.name == rhs.group.name {
                    return lhs.node.name.localizedCaseInsensitiveCompare(rhs.node.name) == .orderedAscending
                }
                return lhs.group.name.localizedCaseInsensitiveCompare(rhs.group.name) == .orderedAscending
            case .proxy:
                return lhs.node.name.localizedCaseInsensitiveCompare(rhs.node.name) == .orderedAscending
            case .delay:
                return (lhs.node.delay ?? Int.max) < (rhs.node.delay ?? Int.max)
            }
        }
    }

    private var selectedRow: PolicyTableRow? {
        guard let selectedRowID else { return nil }
        return rows.first { $0.id == selectedRowID } ?? allRows.first { $0.id == selectedRowID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("策略")
                        .font(.largeTitle.bold())
                    Text("使用 SwiftUI 操作和 AppKit NSTableView 展示密集策略组。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("刷新") {
                    Task { await store.refreshController() }
                }
            }

            HStack {
                TextField("搜索策略组、当前节点或代理", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 340)

                Picker("排序", selection: $sortMode) {
                    Text("策略组").tag(PolicySortMode.group)
                    Text("节点").tag(PolicySortMode.proxy)
                    Text("延迟").tag(PolicySortMode.delay)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Spacer()

                Button("使用选中节点") {
                    if let selectedRow {
                        Task { await store.selectProxy(group: selectedRow.group.name, proxy: selectedRow.node.name) }
                    }
                }
                .disabled(selectedRow == nil)

                Button("测试延迟") {
                    if let selectedRow {
                        Task { await store.testProxyDelay(group: selectedRow.group.name, proxy: selectedRow.node.name) }
                    }
                }
                .disabled(selectedRow == nil)

                Button("测试当前组") {
                    if let selectedRow {
                        Task { await store.testGroupDelay(selectedRow.group) }
                    }
                }
                .disabled(selectedRow == nil)

                Button("测试全部") {
                    Task { await store.testAllProxyDelays() }
                }
            }

            Text(store.delayTestStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            AppKitTable(
                rows: rows,
                selection: $selectedRowID,
                columns: [
                    .init(title: "策略组", width: 190) { $0.group.name },
                    .init(title: "当前", width: 190) { $0.group.now },
                    .init(title: "节点", width: 280) { row in
                        (row.group.now == row.node.name ? "* " : "") + row.node.name
                    },
                    .init(title: "类型", width: 100) { $0.node.type },
                    .init(title: "延迟", width: 90) { row in
                        if let delay = row.node.delay, delay > 0 {
                            return "\(delay) ms"
                        }
                        return "-"
                    }
                ]
            )
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView("没有策略组", systemImage: "switch.2", description: Text("启动 mihomo 并刷新 Controller。"))
                }
            }
        }
        .padding(24)
        .navigationTitle("策略")
    }
}

private enum PolicySortMode: String, Hashable {
    case group
    case proxy
    case delay
}
