import AppKit
import SwiftUI

struct ResourceEmptyState: Equatable {
    let title: String
    let systemImage: String
    let description: String

    init(searchText: String, showsOnlyUnready: Bool) {
        let hasQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if hasQuery {
            title = "没有匹配的资源"
            systemImage = "magnifyingglass"
            description = "请尝试其他搜索词。"
        } else if showsOnlyUnready {
            title = "没有未就绪资源"
            systemImage = "shippingbox"
            description = "当前本地与远程资源均已就绪。"
        } else {
            title = "没有外部资源"
            systemImage = "shippingbox"
            description = "当前配置没有声明 Provider 或本地规则集。"
        }
    }
}

struct ResourceTablePane: View {
    var presentation: ResourceTablePresentation
    @Binding var selectedResourceIDs: Set<String>
    @Binding var showsOnlyUnready: Bool
    var updateStatus: String
    var emptyState: ResourceEmptyState
    var selectedRows: [ExternalResourceRow]
    var rollbackableRows: [ExternalResourceRow]
    var selectedURLs: [URL]
    var isResourceUpdateInProgress: Bool
    var updateAll: () -> Void
    var refresh: ([ExternalResourceRow]) -> Void
    var preview: ([ExternalResourceRow]) -> Void
    var requestRollback: () -> Void
    @State private var selectionAnchor: String?

    var body: some View {
        VStack(spacing: 0) {
            if presentation.visibleRows.isEmpty {
                ContentUnavailableView(
                    emptyState.title,
                    systemImage: emptyState.systemImage,
                    description: Text(emptyState.description)
                )
                .frame(minHeight: 360, maxHeight: .infinity)
            } else {
                MihomoListSurface(minHeight: 360, maxHeight: .infinity) {
                    ForEach(presentation.visibleRows) { row in
                        resourceRow(row)
                    }
                }
            }

            bottomBar
        }
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
    }

    private func resourceRow(_ row: ExternalResourceRow) -> some View {
        MihomoSelectableRow(
            isSelected: selectedResourceIDs.contains(row.id),
            select: { select(row) },
            activate: {
                guard row.canRefresh, isResourceUpdateInProgress == false else { return }
                refresh([row])
            }
        ) {
            HStack(spacing: 12) {
                Image(systemName: statusSystemImage(for: row.statusKind))
                    .foregroundStyle(statusColor(for: row.statusKind))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(row.nameText)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        MihomoRowBadge(title: row.provider.kind, color: row.provider.kind == "Proxy" ? .blue : .purple)
                        if row.provider.providerType.isEmpty == false {
                            MihomoRowBadge(title: row.provider.providerType)
                        }
                    }
                    Text(row.detailText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(row.pathText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                MihomoRowMetadata(
                    primary: row.statusText,
                    secondary: row.lastUpdatedText,
                    primaryColor: statusColor(for: row.statusKind)
                )

                MihomoRowActions {
                    Button {
                        refresh([row])
                    } label: {
                        Image(systemName: row.canDownload ? "arrow.down.circle" : "arrow.clockwise")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .disabled(row.canRefresh == false || isResourceUpdateInProgress)
                    .help(row.updateActionTitle)

                    Menu {
                        Button(row.updateActionTitle) { refresh([row]) }
                            .disabled(row.canRefresh == false || isResourceUpdateInProgress)
                        Button("快速查看") { preview([row]) }
                            .disabled(row.pathText == "-")
                        Button("在 Finder 中显示") {
                            reveal(row)
                        }
                        Divider()
                        Button("回滚", role: .destructive) { requestRollback(for: row) }
                            .disabled(rollbackableRows.contains(where: { $0.id == row.id }) == false)
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 18, height: 18)
                    }
                    .menuStyle(.borderlessButton)
                    .help("更多操作")
                }
            }
        }
        .contextMenu {
            Button(row.updateActionTitle) { refresh([row]) }
                .disabled(row.canRefresh == false || isResourceUpdateInProgress)
            Button("快速查看") { preview([row]) }
            Divider()
            Button("回滚", role: .destructive) { requestRollback(for: row) }
                .disabled(rollbackableRows.contains(where: { $0.id == row.id }) == false)
        }
    }

    private func select(_ row: ExternalResourceRow) {
        let update = TableSelection.updated(
            selectedResourceIDs,
            clicking: row.id,
            visibleIDs: presentation.visibleRows.map(\.id),
            anchor: selectionAnchor,
            modifiers: NSEvent.modifierFlags
        )
        selectedResourceIDs = update.selection
        selectionAnchor = update.anchor
    }

    private func reveal(_ row: ExternalResourceRow) {
        guard row.pathText != "-" else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.pathText)])
    }

    private func requestRollback(for row: ExternalResourceRow) {
        selectedResourceIDs = [row.id]
        selectionAnchor = row.id
        requestRollback()
    }

    private func statusSystemImage(for status: ExternalResourceStatusKind) -> String {
        switch status {
        case .ready: return "checkmark.circle.fill"
        case .pending: return "arrow.down.circle"
        case .failed: return "xmark.octagon.fill"
        case .localOnly: return "doc.text"
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Toggle("仅显示未就绪的项目", isOn: $showsOnlyUnready)
                .toggleStyle(.checkbox)

            Text("\(presentation.visibleRows.count)/\(presentation.allRows.count) 项")
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 16)

            Text(updateStatus)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer()

            Button(action: updateAll) {
                Label("全部更新", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(presentation.refreshableCount == 0 || isResourceUpdateInProgress)

            Button {
                refresh(selectedRows)
            } label: {
                Label("更新所选", systemImage: "arrow.clockwise")
            }
            .disabled(selectedRows.contains(where: \.canRefresh) == false || isResourceUpdateInProgress)

            if selectedURLs.isEmpty == false {
                ShareLink(items: selectedURLs) {
                    Label("导出所选", systemImage: "square.and.arrow.up")
                }
                .help("导出所选资源文件的副本")
            }

            Button(action: requestRollback) {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .help("回滚所选资源")
            .disabled(rollbackableRows.isEmpty || isResourceUpdateInProgress)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func statusColor(for status: ExternalResourceStatusKind) -> Color {
        switch status {
        case .ready: return .green
        case .pending: return .orange
        case .failed: return .red
        case .localOnly: return .secondary
        }
    }

}
