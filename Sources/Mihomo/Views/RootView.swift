import SwiftUI

struct RootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: AppStore
    @AppStorage("main.sidebar.visible") private var sidebarIsVisible = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @StateObject private var appIntentRouter = AppIntentRouter.shared

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MihomoSidebarView(selection: $store.selectedSection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 236, max: 260)
        } detail: {
            DetailSwitchView(section: store.selectedSection)
                .id(store.selectedSection)
                .navigationTitle("")
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: store.selectedSection)
        }
        .toolbar(id: "main") {
            ToolbarItem(id: "core-control", placement: .primaryAction) {
                ToolbarStateButton(
                    title: "核心",
                    accessibilityTitle: "核心",
                    accessibilityIdentifier: "toolbar.core",
                    systemImage: store.isCoreRunning ? "stop.fill" : "play.fill",
                    isOn: store.isCoreRunning
                ) {
                    Task { await store.toggleCore() }
                }
            }

            ToolbarItem(id: "system-proxy-control", placement: .primaryAction) {
                ToolbarStateButton(
                    title: "代理",
                    accessibilityTitle: "系统代理",
                    accessibilityIdentifier: "toolbar.system-proxy",
                    systemImage: "network",
                    isOn: store.systemProxyEnabled
                ) {
                    Task { await store.toggleSystemProxy() }
                }
            }

            ToolbarItem(id: "tun-control", placement: .primaryAction) {
                ToolbarStateButton(
                    title: "TUN",
                    accessibilityTitle: "TUN",
                    accessibilityIdentifier: "toolbar.tun",
                    systemImage: "lock.shield",
                    isOn: store.settings.tunEnabled
                ) {
                    Task { await store.setTunEnabled(!store.settings.tunEnabled) }
                }
            }

            ToolbarItem(id: "mode-control", placement: .principal) {
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

            ToolbarItem(id: "recent-logs", placement: .secondaryAction) {
                GlobalLogMenuHost()
                    .frame(width: 260, alignment: .leading)
            }
        }
        .toolbarRole(.editor)
        .background(WindowIdentifierView(identifier: AppWindowIdentifier.main))
        .onAppear {
            store.isLightweightModeActive = false
            columnVisibility = sidebarIsVisible ? .all : .detailOnly
        }
        .onChange(of: columnVisibility) {
            sidebarIsVisible = columnVisibility != .detailOnly
        }
        .onChange(of: appIntentRouter.pendingAction) {
            guard let action = appIntentRouter.pendingAction else { return }
            appIntentRouter.pendingAction = nil
            Task { await store.handleAppIntent(action) }
        }
    }
}

private struct GlobalLogMenuHost: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var logStore: LogStore

    var body: some View {
        GlobalLogMenu(
            latestLog: logStore.entries.last,
            logs: Array(logStore.entries.suffix(8)),
            clearLogs: store.clearVisibleLogs,
            openFullLog: {
                store.selectedSection = .logs
            }
        )
    }
}

private struct GlobalLogMenu: View {
    var latestLog: LogEntry?
    var logs: [LogEntry]
    var clearLogs: () -> Void
    var openFullLog: () -> Void
    @State private var confirmsClear = false

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
                confirmsClear = true
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
        .confirmationDialog("清空当前日志？", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("全部清除", role: .destructive) { clearLogs() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这只会清空当前界面的日志与缓冲；已落盘日志文件不会被删除。")
        }
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

private struct ToolbarStateButton: View {
    var title: String
    var accessibilityTitle: String
    var accessibilityIdentifier: String
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
            .frame(minWidth: title == "TUN" ? 46 : 54)
        }
        .id(accessibilityIdentifier)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(Text(accessibilityTitle))
        .accessibilityValue(Text(isOn ? "已启用" : "未启用"))
        .accessibilityIdentifier(accessibilityIdentifier)
        .help("\(accessibilityTitle)\(isOn ? "已启用" : "未启用")")
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
        case .overrides:
            OverridesView()
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
        }
    }
}
