import AppKit
import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var selectedLevel = "全部"

    private var levels: [String] {
        ["全部"] + Array(Set(store.logs.map { $0.level.uppercased() })).sorted()
    }

    private var filteredLogs: [LogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.logs.filter { entry in
            let levelMatches = selectedLevel == "全部" || entry.level.uppercased() == selectedLevel
            let textMatches = query.isEmpty || entry.message.localizedCaseInsensitiveContains(query)
            return levelMatches && textMatches
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("日志")
                        .font(.largeTitle.bold())
                    Text("高频日志使用 AppKit NSTextView 渲染，并同步落盘到用户日志目录。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("打开日志文件") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.appLogFile])
                }
            }

            HStack {
                TextField("过滤日志内容", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                Picker("等级", selection: $selectedLevel) {
                    ForEach(levels, id: \.self) { level in
                        Text(level).tag(level)
                    }
                }
                .frame(width: 180)

                Spacer()

                Text("\(filteredLogs.count) / \(store.logs.count)")
                    .foregroundStyle(.secondary)
            }

            AppKitLogView(entries: filteredLogs)
                .frame(minHeight: 560)
        }
        .padding(24)
        .navigationTitle("日志")
    }
}
