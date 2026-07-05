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
                .frame(width: 220)

                Button {
                    Task { await store.toggleSystemProxy() }
                } label: {
                    Label(store.systemProxyEnabled ? "代理开启" : "代理关闭", systemImage: "network")
                }

                Button {
                    Task { await store.toggleCore() }
                } label: {
                    Label(store.isCoreRunning ? "停止" : "启动", systemImage: store.isCoreRunning ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
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
        case .logs:
            LogsView()
        case .diagnostics:
            DiagnosticsView()
        case .settings:
            SettingsRootView()
        }
    }
}
