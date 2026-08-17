import SwiftUI

enum ResourceWorkspaceLayoutMetrics {
    static let contentMinHeight: CGFloat = 560
}

struct ExternalResourceRow: Identifiable, Hashable {
    var provider: ProviderItem
    var latestRecord: ProviderUpdateRecord?
    private var fileExists: Bool

    init(
        provider: ProviderItem,
        latestRecord: ProviderUpdateRecord?,
        fileExists: Bool? = nil
    ) {
        self.provider = provider
        self.latestRecord = latestRecord
        self.fileExists = false
        self.fileExists = fileExists ?? resolvedPath.map {
            FileManager.default.fileExists(atPath: $0)
        } ?? false
    }

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
            return fileExists ? "本地就绪" : "本地文件缺失"
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
    var canRefresh: Bool { provider.canRefreshResource }
    var updateActionTitle: String { hasRemoteURL ? "下载更新" : "重新载入" }

    var detailText: String {
        [
            redactedProviderDetail,
            "路径：\(pathText)"
        ]
        .filter { $0.isEmpty == false && $0 != "-" }
        .joined(separator: " · ")
    }

    private var redactedProviderDetail: String {
        let detail = provider.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let remote = provider.remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              remote.isEmpty == false
        else { return detail }
        return detail.replacingOccurrences(
            of: remote,
            with: URLDisplayText.redactingSensitiveComponents(remote)
        )
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

    private static func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitized = value.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
        let name = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return name.isEmpty ? "provider" : name
    }
}

struct ResourceTablePresentation {
    var allRows: [ExternalResourceRow]
    var visibleRows: [ExternalResourceRow]
    var proxyCount: Int
    var ruleCount: Int
    var unreadyCount: Int
    var refreshableCount: Int

    static func make(
        providers: [ProviderItem],
        latestRecords: [String: ProviderUpdateRecord],
        historyKey: (ProviderItem) -> String,
        searchText: String,
        showsOnlyUnready: Bool,
        kindFilter: String? = nil
    ) -> ResourceTablePresentation {
        let rows = providers.compactMap { provider -> ExternalResourceRow? in
            if let kindFilter,
               provider.kind.caseInsensitiveCompare(kindFilter) != .orderedSame {
                return nil
            }
            return ExternalResourceRow(
                provider: provider,
                latestRecord: latestRecords[historyKey(provider)]
            )
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var proxyCount = 0
        var ruleCount = 0
        var unreadyCount = 0
        var refreshableCount = 0
        var visibleRows: [ExternalResourceRow] = []
        visibleRows.reserveCapacity(rows.count)

        for row in rows {
            let isReady = row.isReady
            if row.provider.kind == "Proxy" { proxyCount += 1 }
            if row.provider.kind == "Rule" { ruleCount += 1 }
            if isReady == false { unreadyCount += 1 }
            if row.canRefresh { refreshableCount += 1 }

            guard showsOnlyUnready == false || isReady == false else { continue }
            guard query.isEmpty
                || row.nameText.localizedCaseInsensitiveContains(query)
                || row.typeText.localizedCaseInsensitiveContains(query)
                || row.pathText.localizedCaseInsensitiveContains(query)
            else { continue }
            visibleRows.append(row)
        }

        return ResourceTablePresentation(
            allRows: rows,
            visibleRows: visibleRows,
            proxyCount: proxyCount,
            ruleCount: ruleCount,
            unreadyCount: unreadyCount,
            refreshableCount: refreshableCount
        )
    }

    func selectedRows(for identifiers: Set<String>) -> [ExternalResourceRow] {
        allRows.filter { identifiers.contains($0.id) }
    }

    func selectedRow(for identifiers: Set<String>) -> ExternalResourceRow? {
        guard identifiers.count == 1, let identifier = identifiers.first else { return nil }
        return allRows.first { $0.id == identifier }
    }
}

enum ResourceWorkspace: String, CaseIterable, Identifiable {
    case configResources
    case nodeProviders
    case rules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .configResources: return "配置资源"
        case .nodeProviders: return "节点提供商"
        case .rules: return "规则"
        }
    }

    var systemImage: String {
        switch self {
        case .configResources: return "shippingbox"
        case .nodeProviders: return "point.3.connected.trianglepath.dotted"
        case .rules: return "list.bullet.clipboard"
        }
    }

    var providerKind: String? {
        switch self {
        case .configResources: return "Proxy"
        case .nodeProviders: return nil
        case .rules: return "Rule"
        }
    }

    var subtitle: String {
        switch self {
        case .configResources:
            return "查看当前配置声明的 Proxy Provider 与节点资源。"
        case .nodeProviders:
            return "独立保存节点订阅，并按 Profile 复选注入运行时配置。"
        case .rules:
            return "集中查看当前配置引用的 Rule Provider 与本地规则集。"
        }
    }
}

enum ExternalResourceStatusKind: Hashable {
    case ready
    case pending
    case failed
    case localOnly
}

struct ResourceCountBadge: View {
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

struct ProviderHistoryPane: View {
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
