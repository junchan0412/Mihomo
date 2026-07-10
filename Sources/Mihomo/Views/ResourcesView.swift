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

    private var downloadableCount: Int {
        allRows.filter(\.canDownload).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            resourceTablePane
            selectedResourcePane
        }
        .padding(24)
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
                    .font(.largeTitle.bold())
                Text("从其他文件或 URL 加载 Proxy Provider、Rule Provider 与 Geo 数据。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                ResourceCountBadge(title: "Proxy", value: allRows.filter { $0.provider.kind == "Proxy" }.count)
                ResourceCountBadge(title: "Rule", value: allRows.filter { $0.provider.kind == "Rule" }.count)
                ResourceCountBadge(title: "未就绪", value: allRows.filter { $0.isReady == false }.count)
            }
        }
    }

    private var resourceTablePane: some View {
        VStack(spacing: 0) {
            AppKitTable(
                rows: visibleRows,
                selection: $selectedResourceID,
                columns: [
                    .init(title: "名称", width: 220) { $0.nameText },
                    .init(title: "类型", width: 150) { $0.typeText },
                    .init(title: "最后更新", width: 150) { $0.lastUpdatedText },
                    .init(title: "路径", width: 360) { $0.pathText },
                    .init(title: "状态", width: 180, textColor: statusTextColor) { $0.statusText }
                ],
                onDoubleClick: handleDoubleClick,
                hasHorizontalScroller: true
            )
            .frame(minHeight: 360, maxHeight: .infinity)
            .overlay {
                if visibleRows.isEmpty {
                    ContentUnavailableView(
                        showsOnlyUnready ? "没有未就绪资源" : "没有外部资源",
                        systemImage: "shippingbox",
                        description: Text(showsOnlyUnready ? "当前 Provider 均已就绪。" : "本地配置未声明 Provider，或 Controller 当前不可用。")
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
                store.refreshConfigArtifacts()
            } label: {
                Label("本地解析", systemImage: "doc.text.magnifyingglass")
            }

            Button {
                Task { await store.refreshProvidersFromController() }
            } label: {
                Label("Controller", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(store.isCoreRunning == false)

            Button {
                Task { await store.updateAllExternalResources() }
            } label: {
                Label("全部更新", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(downloadableCount == 0)

            Button {
                store.selectedSection = .overview
            } label: {
                Label("完成", systemImage: "checkmark")
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var selectedResourcePane: some View {
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
                        Task { await store.updateProviderResource(selectedRow.provider) }
                    } label: {
                        Label("下载", systemImage: "arrow.down.circle")
                    }
                    .disabled(selectedRow.canDownload == false)

                    Button {
                        Task { await store.updateProvider(selectedRow.provider) }
                    } label: {
                        Label("Controller", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isCoreRunning == false)
                }

                ProviderHistoryPane(records: Array(history.prefix(6)))
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
        }
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
        guard row.canDownload else { return }
        Task { await store.updateProviderResource(row.provider) }
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
