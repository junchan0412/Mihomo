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

private struct ExternalResourceRow: Identifiable, Hashable {
    var provider: ProviderItem
    var latestRecord: ProviderUpdateRecord?

    var id: String { provider.id }
    var nameText: String { provider.name }

    var typeText: String {
        let providerType = provider.providerType.trimmingCharacters(in: .whitespacesAndNewlines)
        return providerType.isEmpty ? provider.kind : "\(provider.kind) / \(providerType)"
    }

    var lastUpdatedText: String {
        latestRecord.map { Formatters.shortDate.string(from: $0.date) } ?? "未更新"
    }

    var pathText: String {
        resolvedPath ?? configuredPath ?? "-"
    }

    var statusText: String {
        switch statusKind {
        case .ready:
            return "就绪"
        case .pending:
            return hasRemoteURL ? "待下载" : "缺少路径"
        case .failed:
            let message = latestRecord?.message.trimmingCharacters(in: .whitespacesAndNewlines) ?? "更新失败"
            return "失败：\(message)"
        case .localOnly:
            return fileExists ? "本地就绪" : "无远程 URL"
        }
    }

    var statusKind: ExternalResourceStatusKind {
        if latestRecord?.succeeded == false {
            return .failed
        }
        if fileExists || latestRecord?.succeeded == true {
            return .ready
        }
        if hasRemoteURL {
            return .pending
        }
        return .localOnly
    }

    var isReady: Bool {
        switch statusKind {
        case .ready, .localOnly:
            return fileExists || latestRecord?.succeeded == true
        case .pending, .failed:
            return false
        }
    }

    var canDownload: Bool { hasRemoteURL }

    var detailText: String {
        [
            provider.detail,
            provider.remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines),
            "路径：\(pathText)"
        ]
        .compactMap { value in
            guard let value, value.isEmpty == false, value != "-" else { return nil }
            return value
        }
        .joined(separator: " · ")
    }

    private var hasRemoteURL: Bool {
        provider.remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var configuredPath: String? {
        if let path = provider.path?.trimmingCharacters(in: .whitespacesAndNewlines),
           path.isEmpty == false {
            return path
        }
        guard hasRemoteURL else { return nil }
        let directory = provider.kind == "Proxy" ? "proxy_providers" : "rule_providers"
        return "\(directory)/\(Self.safeFileName(provider.name)).yaml"
    }

    private var resolvedPath: String? {
        guard let configuredPath else { return nil }
        if configuredPath.hasPrefix("/") {
            return configuredPath
        }
        return AppPaths.runtimeDirectory.appendingPathComponent(configuredPath).path
    }

    private var fileExists: Bool {
        guard let resolvedPath else { return false }
        return FileManager.default.fileExists(atPath: resolvedPath)
    }

    private static func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitized = value.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
        let name = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return name.isEmpty ? "provider" : name
    }
}

private enum ExternalResourceStatusKind: Hashable {
    case ready
    case pending
    case failed
    case localOnly
}

private struct ResourceCountBadge: View {
    var title: String
    var value: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .fontWeight(.semibold)
        }
        .font(.callout)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.35), in: Capsule())
    }
}

private struct ProviderHistoryPane: View {
    var records: [ProviderUpdateRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("更新历史", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(records.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if records.isEmpty {
                Text("暂无更新记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        ProviderHistoryRow(record: record)
                        if index < records.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct ProviderHistoryRow: View {
    var record: ProviderUpdateRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(record.succeeded ? .green : .red)
                .frame(width: 16)

            Text(Formatters.shortDate.string(from: record.date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)

            Text(record.action)
                .font(.caption.weight(.medium))
                .frame(width: 64, alignment: .leading)

            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.vertical, 5)
    }

    private var detailText: String {
        let pathDetail: String
        if let restored = record.restoredFromPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           restored.isEmpty == false {
            pathDetail = "恢复：\(restored)"
        } else if let backup = record.backupPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  backup.isEmpty == false {
            pathDetail = "备份：\(backup)"
        } else {
            pathDetail = "路径：\(record.targetPath)"
        }
        return "\(record.message) · \(pathDetail)"
    }
}
