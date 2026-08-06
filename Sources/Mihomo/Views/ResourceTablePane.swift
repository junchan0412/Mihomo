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
    var contextMenuActions: [AppKitTableContextAction<ExternalResourceRow>]
    var updateAll: () -> Void
    var refresh: ([ExternalResourceRow]) -> Void
    var preview: ([ExternalResourceRow]) -> Void
    var requestRollback: () -> Void

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
                AppKitTable(
                    rows: presentation.visibleRows,
                    selection: $selectedResourceIDs,
                    columns: columns,
                    allowsMultipleSelection: true,
                    onDoubleClick: { row in
                        guard row.canRefresh, isResourceUpdateInProgress == false else { return }
                        refresh([row])
                    },
                    onActivate: { rows in
                        guard isResourceUpdateInProgress == false else { return }
                        refresh(rows)
                    },
                    onPreview: preview,
                    hasHorizontalScroller: true,
                    contextMenuActions: contextMenuActions
                )
                .frame(minHeight: 360, maxHeight: .infinity)
            }

            bottomBar
        }
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
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

    private var columns: [AppKitTableColumn<ExternalResourceRow>] {
        [
            .init(title: "名称", width: 160) { $0.nameText },
            .init(title: "类型", width: 150) { $0.typeText },
            .init(title: "最后更新", width: 150) { $0.lastUpdatedText },
            .init(title: "状态", width: 150, textColor: statusTextColor) { $0.statusText },
            .init(title: "路径", width: 420) { $0.pathText }
        ]
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
