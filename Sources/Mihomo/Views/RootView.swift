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

                Section("Configuration") {
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
                Picker("Mode", selection: Binding(
                    get: { store.currentMode },
                    set: { mode in Task { await store.setMode(mode) } }
                )) {
                    Text("Rule").tag("rule")
                    Text("Global").tag("global")
                    Text("Direct").tag("direct")
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Button {
                    Task { await store.toggleSystemProxy() }
                } label: {
                    Label(store.systemProxyEnabled ? "Proxy On" : "Proxy Off", systemImage: "network")
                }

                Button {
                    Task { await store.toggleCore() }
                } label: {
                    Label(store.isCoreRunning ? "Stop" : "Start", systemImage: store.isCoreRunning ? "stop.fill" : "play.fill")
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
