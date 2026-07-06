import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isLogOverlayPresented = false

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedSection) {
                Section("Mihomo") {
                    ForEach(AppSection.allCases.filter { $0 != .settings }) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }

                Section("配置") {
                    Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage)
                        .tag(AppSection.settings)
                }
            }
            .navigationTitle("Mihomo")
            .listStyle(.sidebar)
        } detail: {
            ZStack(alignment: .topLeading) {
                DetailSwitchView(section: store.selectedSection)

                if isLogOverlayPresented {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            isLogOverlayPresented = false
                        }
                        .zIndex(1)
                }

                GlobalLogOverlay(
                    isPresented: $isLogOverlayPresented,
                    latestLog: store.logs.last,
                    logs: Array(store.logs.suffix(8)),
                    clearLogs: store.clearVisibleLogs
                )
                .padding(.leading, 20)
                .padding(.top, 10)
                .zIndex(2)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("模式", selection: Binding(
                    get: { store.currentMode },
                    set: { mode in Task { await store.setMode(mode) } }
                )) {
                    Text("规则").tag("rule")
                    Text("全局").tag("global")
                    Text("直连").tag("direct")
                }
                .pickerStyle(.segmented)
                .frame(width: 184)

                GlobalQuickControlsView()
            }
        }
        .background(WindowIdentifierView(identifier: AppWindowIdentifier.main))
    }
}

private struct GlobalLogOverlay: View {
    @Binding var isPresented: Bool
    var latestLog: LogEntry?
    var logs: [LogEntry]
    var clearLogs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isPresented {
                expandedPanel
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
            } else {
                collapsedPill
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.18), value: isPresented)
    }

    private var collapsedPill: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(levelColor(latestLog?.level))
                    .frame(width: 8, height: 8)

                Text(levelTitle(latestLog?.level))
                    .fontWeight(.semibold)
                    .foregroundStyle(levelColor(latestLog?.level))

                Text(latestLog?.message ?? "暂无事件")
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: 420, alignment: .leading)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help("显示最近日志")
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("事件")
                    .font(.headline)
                Spacer()
                Button("全部清除") {
                    clearLogs()
                    isPresented = false
                }
                .disabled(logs.isEmpty)

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .help("关闭事件")
            }

            if logs.isEmpty {
                ContentUnavailableView("暂无事件", systemImage: "checkmark.circle")
                    .frame(width: 520, height: 160)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(logs.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(levelColor(entry.level))
                                    .frame(width: 7, height: 7)
                                Text(levelTitle(entry.level))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(levelColor(entry.level))
                                Text(Formatters.shortDate.string(from: entry.date))
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(width: 560, alignment: .leading)
            }
        }
        .font(.callout)
        .padding(16)
        .frame(maxWidth: 620, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8)
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
}

private struct GlobalQuickControlsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 6) {
            ToolbarStateButton(
                title: "核心",
                systemImage: store.isCoreRunning ? "stop.fill" : "play.fill",
                isOn: store.isCoreRunning
            ) {
                Task { await store.toggleCore() }
            }

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
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .imageScale(.small)
                Circle()
                    .fill(isOn ? Color.green : Color.secondary.opacity(0.55))
                    .frame(width: 6, height: 6)
                Text(title)
            }
            .font(.callout.weight(.medium))
            .frame(minWidth: 58)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("\(title)\(isOn ? "已启用" : "未启用")")
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
