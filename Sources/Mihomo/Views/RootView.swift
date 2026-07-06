import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

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
            DetailSwitchView(section: store.selectedSection)
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
