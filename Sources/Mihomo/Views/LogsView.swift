import AppKit
import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var logStore: LogStore
    @State private var searchText = ""
    @FocusState private var searchIsFocused: Bool
    @State private var selectedCategory: LogCategory = .all
    @State private var selectedRowIDs: Set<UUID> = []
    @State private var confirmsClear = false

    private var rows: [LogPresentationRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return logStore.entries.reversed()
            .map(LogPresentationRow.init(entry:))
            .filter { row in
                selectedCategory.matches(row.category)
                    && (query.isEmpty
                        || row.title.localizedCaseInsensitiveContains(query)
                        || row.detail.localizedCaseInsensitiveContains(query)
                        || row.category.title.localizedCaseInsensitiveContains(query)
                        || row.level.localizedCaseInsensitiveContains(query))
            }
    }

    var body: some View {
        HStack(spacing: 0) {
            LogCategorySidebar(selection: $selectedCategory)
                .frame(width: 210)

            Divider()

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
        .onChange(of: rows) {
            selectedRowIDs.formIntersection(Set(rows.map(\.id)))
        }
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
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MihomoUI.cardStroke).frame(height: 1)
        }
    }

    private var logTable: some View {
        AppKitTable(
            rows: rows,
            selection: $selectedRowIDs,
            columns: [
                .init(title: "时间", width: 160) { $0.time },
                .init(title: "分类", width: 110, textColor: { $0.category.color }) { $0.category.title },
                .init(title: "标题", width: 360) { $0.title },
                .init(title: "详情", width: 680) { $0.detail }
            ],
            allowsMultipleSelection: true,
            onActivate: { copyRows($0) },
            onPreview: { copyRows($0) },
            hasHorizontalScroller: true,
            borderType: .noBorder,
            contextMenuActions: [
                .init("复制") { copyRows($0) },
                .init("按此分类过滤", isEnabled: { $0.count == 1 }) { selected in
                    guard let row = selected.first else { return }
                    selectedCategory = row.category
                }
            ]
        )
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(
                    "暂无日志",
                    systemImage: "terminal",
                    description: Text(searchText.isEmpty ? "新的运行事件会显示在这里。" : "没有符合当前筛选条件的日志。")
                )
            }
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
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle().fill(MihomoUI.cardStroke).frame(height: 1)
        }
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
