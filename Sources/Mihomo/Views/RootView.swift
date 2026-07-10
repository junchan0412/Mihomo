import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationSplitView {
            MihomoSidebarView(selection: $store.selectedSection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 236, max: 260)
        } detail: {
            DetailSwitchView(section: store.selectedSection)
                .id(store.selectedSection)
                .navigationTitle("")
                .transition(.opacity)
                .animation(.easeOut(duration: 0.12), value: store.selectedSection)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                GlobalLogMenu(
                    latestLog: store.logs.last,
                    logs: Array(store.logs.suffix(8)),
                    clearLogs: store.clearVisibleLogs,
                    openFullLog: {
                        store.selectedSection = .logs
                    }
                )
                .frame(width: 260, alignment: .leading)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                GlobalQuickControlsView()

                Picker("模式", selection: Binding(
                    get: { store.currentMode },
                    set: { mode in Task { await store.setMode(mode) } }
                )) {
                    Text("规则").tag("rule")
                    Text("全局").tag("global")
                    Text("直连").tag("direct")
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
        }
        .background(WindowIdentifierView(identifier: AppWindowIdentifier.main))
    }
}

private struct GlobalLogMenu: View {
    var latestLog: LogEntry?
    var logs: [LogEntry]
    var clearLogs: () -> Void
    var openFullLog: () -> Void

    var body: some View {
        Menu {
            if logs.isEmpty {
                Text("暂无事件")
            } else {
                ForEach(logs.reversed()) { entry in
                    Text(logMenuTitle(for: entry))
                }
            }

            Divider()

            Button("打开日志") {
                openFullLog()
            }

            Button("全部清除") {
                clearLogs()
            }
            .disabled(logs.isEmpty)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .imageScale(.small)
                Circle()
                    .fill(levelColor(latestLog?.level))
                    .frame(width: 6, height: 6)
                Text(levelTitle(latestLog?.level))
                Text(Formatters.trimmedMenuText(latestLog?.message ?? "暂无事件", limit: 32))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(MihomoUI.Fonts.bodyMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.button)
        .controlSize(.small)
        .help("显示最近日志")
    }

    private func levelTitle(_ level: String?) -> String {
        switch level?.lowercased() {
        case "error": return "错误"
        case "warning", "warn": return "警告"
        case "debug": return "调试"
        case "info": return "信息"
        default: return "状态"
        }
    }

    private func levelColor(_ level: String?) -> Color {
        switch level?.lowercased() {
        case "error": return .red
        case "warning", "warn": return .orange
        case "debug": return .secondary
        case "info": return .green
        default: return .secondary
        }
    }

    private func logMenuTitle(for entry: LogEntry) -> String {
        let message = Formatters.trimmedMenuText(entry.message, limit: 36)
        return "\(levelTitle(entry.level)) \(Formatters.shortDate.string(from: entry.date)) \(message)"
    }
}

private struct GlobalQuickControlsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 6) {
            ToolbarStateButton(
                title: "代理",
                systemImage: "network",
                isOn: store.systemProxyEnabled
            ) {
                Task { await store.toggleSystemProxy() }
            }

            ToolbarStateButton(
                title: "TUN",
                systemImage: "lock.shield",
                isOn: store.settings.tunEnabled
            ) {
                Task { await store.setTunEnabled(!store.settings.tunEnabled) }
            }
        }
    }
}

private struct ToolbarStateButton: View {
    var title: String
    var systemImage: String
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .imageScale(.small)
                Circle()
                    .fill(isOn ? Color.green : Color.secondary.opacity(0.55))
                    .frame(width: 6, height: 6)
                Text(title)
            }
            .font(MihomoUI.Fonts.bodyMedium)
            .frame(minWidth: title == "代理" ? 54 : 46)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("\(title == "代理" ? "系统代理" : title)\(isOn ? "已启用" : "未启用")")
    }
}

struct DetailSwitchView: View {
    let section: AppSection

    var body: some View {
        switch section {
        case .overview:
            OverviewView()
        case .networkSecurity:
            NetworkSecurityView()
        case .activity:
            ActivityView()
        case .policies:
            PoliciesView()
        case .profiles:
            ProfilesView()
        case .rules:
            RulesView()
        case .resources:
            ResourcesView()
        case .advanced:
            AdvancedView()
        case .logs:
            LogsView()
        case .diagnostics:
            DiagnosticsView()
        case .settings:
            SettingsRootView()
        }
    }
}
