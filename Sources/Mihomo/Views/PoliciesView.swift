import SwiftUI

struct PoliciesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedRowID: String?

    private var rows: [PolicyTableRow] {
        store.proxyGroups.flatMap { group in
            group.all.map { PolicyTableRow(group: group, node: $0) }
        }
    }

    private var selectedRow: PolicyTableRow? {
        guard let selectedRowID else { return nil }
        return rows.first { $0.id == selectedRowID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Policies")
                        .font(.largeTitle.bold())
                    Text("SwiftUI actions with an AppKit NSTableView for dense policy groups.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    Task { await store.refreshController() }
                }
            }

            HStack {
                Button("Use Selected") {
                    if let selectedRow {
                        Task { await store.selectProxy(group: selectedRow.group.name, proxy: selectedRow.node.name) }
                    }
                }
                .disabled(selectedRow == nil)

                Button("Test Delay") {
                    if let selectedRow {
                        Task { await store.testProxyDelay(group: selectedRow.group.name, proxy: selectedRow.node.name) }
                    }
                }
                .disabled(selectedRow == nil)

                Spacer()
            }

            AppKitTable(
                rows: rows,
                selection: $selectedRowID,
                columns: [
                    .init(title: "Group", width: 190) { $0.group.name },
                    .init(title: "Current", width: 190) { $0.group.now },
                    .init(title: "Proxy", width: 280) { row in
                        (row.group.now == row.node.name ? "* " : "") + row.node.name
                    },
                    .init(title: "Type", width: 100) { $0.node.type },
                    .init(title: "Delay", width: 90) { row in
                        if let delay = row.node.delay, delay > 0 {
                            return "\(delay) ms"
                        }
                        return "-"
                    }
                ]
            )
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView("No Policy Groups", systemImage: "switch.2", description: Text("Start mihomo and refresh the controller."))
                }
            }
        }
        .padding(24)
        .navigationTitle("Policies")
    }
}
