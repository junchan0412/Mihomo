import AppKit
import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var logStore: LogStore
    @State private var searchText = ""
    @State private var selectedCategory: LogCategory = .all

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

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(MihomoUI.Fonts.body)
            }
            .padding(.horizontal, 12)
            .frame(width: 280, height: 34)
            .background(MihomoUI.mutedFill, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MihomoUI.cardStroke, lineWidth: 1)
            }

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
            selection: .constant(nil),
            columns: [
                .init(title: "时间", width: 160) { $0.time },
                .init(title: "分类", width: 110, textColor: { $0.category.color }) { $0.category.title },
                .init(title: "标题", width: 360) { $0.title },
                .init(title: "详情", width: 680) { $0.detail }
            ],
            hasHorizontalScroller: true,
            borderType: .noBorder
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
                store.clearVisibleLogs()
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
}
