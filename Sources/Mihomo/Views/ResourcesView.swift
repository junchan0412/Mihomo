import AppKit
import SwiftUI

struct ResourcesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedResourceID: String?
    @State private var showsOnlyUnready = false

    private var latestRecords: [String: ProviderUpdateRecord] {
        var records: [String: ProviderUpdateRecord] = [:]
        for record in store.providerUpdateHistory {
            let key = "\(record.providerKind)-\(record.providerName)"
            if records[key] == nil {
                records[key] = record
            }
        }
        return records
    }

    private var allRows: [ExternalResourceRow] {
        let records = latestRecords
        return store.providers.map { provider in
            ExternalResourceRow(provider: provider, latestRecord: records[provider.id])
        }
    }

    private var visibleRows: [ExternalResourceRow] {
        showsOnlyUnready ? allRows.filter { $0.isReady == false } : allRows
    }

    private var selectedRow: ExternalResourceRow? {
        guard let selectedResourceID else { return nil }
        return allRows.first { $0.id == selectedResourceID }
    }

    private var refreshableCount: Int {
        allRows.filter(\.canRefresh).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            resourceTablePane
            selectedResourcePane
        }
        .padding(.horizontal, MihomoUI.pageHorizontalPadding)
        .padding(.vertical, MihomoUI.pageVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("资源")
        .onAppear {
            store.refreshConfigArtifacts()
            ensureSelection()
        }
        .onChange(of: store.providers) {
            ensureSelection()
        }
        .onChange(of: showsOnlyUnready) {
            ensureSelection()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("外部资源")
                    .font(MihomoUI.Fonts.pageTitle)
                Text("统一管理配置引用的 Proxy Provider、Rule Provider、本地规则集与 Geo 数据。")
                    .font(MihomoUI.Fonts.pageSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                ResourceCountBadge(title: "Proxy", value: allRows.filter { $0.provider.kind == "Proxy" }.count)
                ResourceCountBadge(title: "Rule", value: allRows.filter { $0.provider.kind == "Rule" }.count)
                ResourceCountBadge(title: "未就绪", value: allRows.filter { $0.isReady == false }.count)
                Divider().frame(height: 22)
                Text("并发").foregroundStyle(.secondary)
                Stepper(value: resourceConcurrency, in: 1...12) {
                    Text("\(store.settings.resourceUpdateMaxConcurrent)").monospacedDigit().frame(width: 24)
                }
                .help("同时更新的 Provider 数量")
            }
        }
    }

    private var resourceConcurrency: Binding<Int> {
        Binding(
            get: { store.settings.resourceUpdateMaxConcurrent },
            set: { value in
                var updated = store.settings
                updated.resourceUpdateMaxConcurrent = value
                Task { await store.saveSettings(updated) }
            }
        )
    }

    private var resourceTablePane: some View {
        VStack(spacing: 0) {
            AppKitTable(
                rows: visibleRows,
                selection: $selectedResourceID,
                columns: [
                    .init(title: "名称", width: 160) { $0.nameText },
                    .init(title: "类型", width: 150) { $0.typeText },
                    .init(title: "最后更新", width: 150) { $0.lastUpdatedText },
                    .init(title: "状态", width: 150, textColor: statusTextColor) { $0.statusText },
                    .init(title: "路径", width: 420) { $0.pathText }
                ],
                onDoubleClick: handleDoubleClick,
                hasHorizontalScroller: true,
                contextMenuTitle: "更新此资源",
                onContextMenu: { row in
                    selectedResourceID = row.id
                    Task { await store.refreshProviderResource(row.provider) }
                }
            )
            .frame(minHeight: 360, maxHeight: .infinity)
            .overlay {
                if visibleRows.isEmpty {
                    ContentUnavailableView(
                        showsOnlyUnready ? "没有未就绪资源" : "没有外部资源",
                        systemImage: "shippingbox",
                        description: Text(showsOnlyUnready ? "当前本地与远程资源均已就绪。" : "当前配置没有声明 Provider 或本地规则集。")
                    )
                }
            }

            Divider()

            bottomBar
        }
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Toggle("仅显示未就绪的项目", isOn: $showsOnlyUnready)
                .toggleStyle(.checkbox)

            Text("\(visibleRows.count)/\(allRows.count) 项")
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 16)

            Text(store.resourceUpdateStatus)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer()

            Button {
                Task { await store.updateAllExternalResources() }
            } label: {
                Label("全部更新", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(refreshableCount == 0)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var selectedResourcePane: some View {
        Group {
            if let selectedRow {
                let history = store.providerUpdateHistory(for: selectedRow.provider)
                let rollbackRecord = store.latestProviderRollbackRecord(for: selectedRow.provider)
                VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label(selectedRow.provider.name, systemImage: selectedRow.provider.kind == "Proxy" ? "point.3.connected.trianglepath.dotted" : "list.bullet.clipboard")
                        .font(.headline)
                        .lineLimit(1)

                    Text(selectedRow.detailText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        Task { await store.rollbackProviderResource(selectedRow.provider) }
                    } label: {
                        Label("回滚", systemImage: "arrow.uturn.backward.circle")
                    }
                    .disabled(rollbackRecord == nil)
                    .help(rollbackRecord?.backupPath ?? "没有可用备份")

                    Button {
                        Task { await store.refreshProviderResource(selectedRow.provider) }
                    } label: {
                        Label(selectedRow.updateActionTitle, systemImage: selectedRow.canDownload ? "arrow.down.circle" : "arrow.clockwise")
                    }
                    .disabled(selectedRow.canRefresh == false)
                }

                ProviderHistoryPane(records: Array(history.prefix(6)))
            }
            } else {
                ContentUnavailableView(
                    showsOnlyUnready ? "没有需要处理的资源" : "选择一个资源",
                    systemImage: "shippingbox",
                    description: Text(showsOnlyUnready ? "关闭过滤可以查看全部资源。" : "选择资源后可查看路径、更新与回滚历史。")
                )
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
    }

    private func ensureSelection() {
        let rows = visibleRows
        guard rows.isEmpty == false else {
            selectedResourceID = nil
            return
        }
        if let selectedResourceID, rows.contains(where: { $0.id == selectedResourceID }) {
            return
        }
        selectedResourceID = rows.first?.id
    }

    private func handleDoubleClick(_ row: ExternalResourceRow) {
        guard row.canRefresh else { return }
        Task { await store.refreshProviderResource(row.provider) }
    }

    private func statusTextColor(_ row: ExternalResourceRow) -> NSColor? {
        switch row.statusKind {
        case .ready:
            return .systemGreen
        case .pending:
            return .systemOrange
        case .failed:
            return .systemRed
        case .localOnly:
            return .secondaryLabelColor
        }
    }
}
