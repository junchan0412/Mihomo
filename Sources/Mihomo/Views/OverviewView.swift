import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Overview")
                            .font(.largeTitle.bold())
                        Text(store.activeProfile?.name ?? "No active profile")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Run Diagnostics") {
                        Task { await store.runDiagnostics() }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    StatusCard(title: "Core", value: store.coreStatus, systemImage: "cpu", isGood: store.isCoreRunning)
                    StatusCard(title: "Controller", value: store.coreVersion, systemImage: "point.3.connected.trianglepath.dotted", isGood: store.coreVersion != "unknown")
                    StatusCard(title: "System Proxy", value: store.systemProxyEnabled ? "Enabled" : "Disabled", systemImage: "network", isGood: store.systemProxyEnabled)
                    StatusCard(title: "TUN", value: store.settings.tunEnabled ? "Configured" : "Off", systemImage: "lock.shield", isGood: store.settings.tunEnabled)
                    StatusCard(title: "Download", value: Formatters.rate(store.downloadRate), systemImage: "arrow.down", isGood: true)
                    StatusCard(title: "Upload", value: Formatters.rate(store.uploadRate), systemImage: "arrow.up", isGood: true)
                }

                GroupBox("Quick Actions") {
                    HStack {
                        Button(store.isCoreRunning ? "Stop Core" : "Start Core") {
                            Task { await store.toggleCore() }
                        }
                        .buttonStyle(.borderedProminent)

                        Button(store.systemProxyEnabled ? "Disable System Proxy" : "Enable System Proxy") {
                            Task { await store.toggleSystemProxy() }
                        }

                        Button("Refresh") {
                            Task { await store.refreshController() }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Recent Logs") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.logs.suffix(8)) { entry in
                            HStack(alignment: .firstTextBaseline) {
                                Text(Formatters.logTime.string(from: entry.date))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 64, alignment: .leading)
                                Text(entry.level.uppercased())
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 62, alignment: .leading)
                                Text(entry.message)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        if store.logs.isEmpty {
                            Text("No logs yet.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Overview")
    }
}

struct StatusCard: View {
    let title: String
    let value: String
    let systemImage: String
    let isGood: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.title3)
                    Spacer()
                    Circle()
                        .fill(isGood ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}
