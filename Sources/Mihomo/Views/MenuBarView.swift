import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack {
            Text(store.isCoreRunning ? "Mihomo Running" : "Mihomo Stopped")
            if let profile = store.activeProfile {
                Text(Formatters.trimmedMenuText(profile.name))
            }

            Divider()

            Button("Open Mihomo") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            SettingsLink {
                Text("Settings")
            }

            Divider()

            Button(store.isCoreRunning ? "Stop Core" : "Start Core") {
                Task { await store.toggleCore() }
            }

            Button(store.systemProxyEnabled ? "Proxy Off" : "Proxy On") {
                Task { await store.toggleSystemProxy() }
            }

            Menu("Mode") {
                modeButton("Rule", mode: "rule")
                modeButton("Global", mode: "global")
                modeButton("Direct", mode: "direct")
            }

            Button("Refresh") {
                Task { await store.refreshController() }
            }

            Button("Diagnostics") {
                Task { await store.runDiagnostics() }
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("Quit Mihomo") {
                NSApp.terminate(nil)
            }
        }
    }

    private func modeButton(_ title: String, mode: String) -> some View {
        Button {
            Task { await store.setMode(mode) }
        } label: {
            if store.currentMode == mode {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}
