import AppKit
import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var logStore: LogStore
    @State private var searchText = ""
    @FocusState private var searchIsFocused: Bool
    @State private var selectedCategory: LogCategory = .all
    @State private var selectedRowIDs: Set<UUID> = []
    @State private var selectionAnchor: UUID?
    @State private var allRows: [LogPresentationRow] = []
    @State private var rows: [LogPresentationRow] = []
    @State private var confirmsClear = false

    var body: some View {
        HStack(spacing: 0) {
            LogCategorySidebar(selection: $selectedCategory)
                .frame(width: 210)

            VStack(spacing: 0) {
                logHeader
                logTable
                logActionBar
            }
        }
        .background(MihomoUI.pageBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("日志")
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索日志")
        .compatibleSearchFocused($searchIsFocused)
        .focusedSceneValue(\.workspaceCommands, commandContext)
        .onReceive(logStore.$entries) { entries in
            let nextRows = LogPresentationRows.make(from: entries)
            allRows = nextRows
            applyFilter(to: nextRows)
        }
        .onChange(of: searchText) { applyFilter(to: allRows) }
        .onChange(of: selectedCategory) { applyFilter(to: allRows) }
        .confirmationDialog("清空当前日志？", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("全部清除", role: .destructive) {
                selectedRowIDs.removeAll()
                store.clearVisibleLogs()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这只会清空当前界面的日志与缓冲；已落盘日志文件不会被删除。")
        }
    }

    private var logHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("日志")
                    .font(MihomoUI.Fonts.pageTitle)
                Text("按类型浏览 App 与 Mihomo core 的运行事件")
                    .font(MihomoUI.Fonts.pageSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(rows.count)")
                .font(MihomoUI.Fonts.bodyMedium)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MihomoUI.pageBackground)
    }

    private var logTable: some View {
        Group {
            if rows.isEmpty {
                ContentUnavailableView(
                    logStore.entries.isEmpty ? "暂无日志" : "没有匹配的日志",
                    systemImage: logStore.entries.isEmpty ? "terminal" : "magnifyingglass",
                    description: Text(logStore.entries.isEmpty ? "新的运行事件会显示在这里。" : "请调整分类或尝试其他搜索词。")
                )
            } else {
                MihomoListSurface(minHeight: 0, maxHeight: .infinity) {
                    ForEach(rows) { row in
                        logRow(row)
                    }
                }
            }
        }
    }

    private func logRow(_ row: LogPresentationRow) -> some View {
        MihomoSelectableRow(
            isSelected: selectedRowIDs.contains(row.id),
            select: { select(row) },
            activate: { copyRows([row]) }
        ) {
            HStack(spacing: 12) {
                Image(systemName: levelSystemImage(row.level))
                    .foregroundStyle(levelColor(row.level))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(row.title)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        MihomoRowBadge(title: row.category.title, color: Color(nsColor: row.category.color))
                        MihomoRowBadge(title: row.level, color: levelColor(row.level))
                    }
                    Text(row.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                MihomoRowMetadata(
                    primary: row.time,
                    secondary: row.category.title,
                    primaryColor: levelColor(row.level)
                )

                MihomoRowActions {
                    Button { copyRows([row]) } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help("复制日志")

                    Menu {
                        Button("复制") { copyRows([row]) }
                        Button("按此分类过滤") { selectedCategory = row.category }
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
            Button("复制") { copyRows([row]) }
            Button("按此分类过滤") { selectedCategory = row.category }
        }
    }

    private func select(_ row: LogPresentationRow) {
        let update = TableSelection.updated(
            selectedRowIDs,
            clicking: row.id,
            visibleIDs: rows.map(\.id),
            anchor: selectionAnchor,
            modifiers: NSEvent.modifierFlags
        )
        selectedRowIDs = update.selection
        selectionAnchor = update.anchor
    }

    private func levelSystemImage(_ level: String) -> String {
        switch level.lowercased() {
        case "error": return "xmark.octagon.fill"
        case "warning", "warn": return "exclamationmark.triangle.fill"
        case "debug": return "ladybug.fill"
        default: return "info.circle.fill"
        }
    }

    private func levelColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "error": return .red
        case "warning", "warn": return .orange
        case "debug": return .secondary
        default: return .green
        }
    }

    private var logActionBar: some View {
        HStack(spacing: 8) {
            Button(logStore.isPaused ? "继续日志" : "暂停日志") {
                store.toggleLogPause()
            }

            Button("全部清除") {
                confirmsClear = true
            }
            .disabled(logStore.entries.isEmpty)

            Button("打开 App 日志") {
                NSWorkspace.shared.activateFileViewerSelecting([AppPaths.appLogFile])
            }

            Button("打开核心日志") {
                NSWorkspace.shared.activateFileViewerSelecting([AppPaths.coreLogFile])
            }

            Spacer()

            Text(logStatusText)
                .foregroundStyle(.secondary)
        }
        .font(MihomoUI.Fonts.bodyMedium)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(MihomoUI.pageBackground)
    }

    private var logStatusText: String {
        let retention = "保留 \(store.settings.logRetentionDays) 天 · 单文件 \(store.settings.logMaxFileSizeMB) MB"
        if logStore.isPaused {
            return "已暂停，缓冲 \(logStore.bufferedCount) 条 · \(retention)"
        }
        return retention
    }

    private var selectedRows: [LogPresentationRow] {
        rows.filter { selectedRowIDs.contains($0.id) }
    }

    private func applyFilter(to allRows: [LogPresentationRow]) {
        let nextRows = LogPresentationRows.filter(
            allRows,
            category: selectedCategory,
            query: searchText
        )
        rows = nextRows
        selectedRowIDs = TableSelection.reconciled(
            selectedRowIDs,
            visibleIDs: nextRows.map(\.id)
        )
    }

    private func copyRows(_ rows: [LogPresentationRow]) {
        guard rows.isEmpty == false else { return }
        let text = rows.map { "\($0.time) [\($0.level)] \($0.title) — \($0.detail)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var commandContext: WorkspaceCommandContext {
        WorkspaceCommandContext(
            search: {
                searchIsFocused = true
                MihomoSearchFocus.request()
            },
            refresh: { Task { await store.refreshController() } },
            activateSelection: searchIsFocused || selectedRows.isEmpty ? nil : { copyRows(selectedRows) },
            previewSelection: searchIsFocused || selectedRows.isEmpty ? nil : { copyRows(selectedRows) }
        )
    }
}
