import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct MihomoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("Mihomo", id: "main") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 1080, minHeight: 700)
                .task {
                    await store.bootstrap()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Mihomo") {
                Button(store.isCoreRunning ? "Stop Core" : "Start Core") {
                    Task { await store.toggleCore() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Refresh Controller") {
                    Task { await store.refreshController() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Run Diagnostics") {
                    Task { await store.runDiagnostics() }
                }
                .keyboardShortcut("d", modifiers: [.command])
            }
        }

        Settings {
            SettingsRootView()
                .environmentObject(store)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
        } label: {
            Text(store.menuBarTitle)
        }
        .menuBarExtraStyle(.menu)
    }
}
