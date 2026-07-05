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
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    Task { await store.shutdown() }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Mihomo") {
                Button(store.isCoreRunning ? "停止核心" : "启动核心") {
                    Task { await store.toggleCore() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("重启核心") {
                    Task { await store.restartCore() }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Button("刷新 Controller") {
                    Task { await store.refreshController() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button(store.systemProxyEnabled ? "关闭系统代理" : "开启系统代理") {
                    Task { await store.toggleSystemProxy() }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("刷新所有订阅") {
                    Task { await store.refreshAllRemoteProfiles() }
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Button("测试全部节点延迟") {
                    Task { await store.testAllProxyDelays() }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button(store.logsPaused ? "继续日志" : "暂停日志") {
                    store.toggleLogPause()
                }
                .keyboardShortcut("p", modifiers: [.command, .option])

                Button("运行诊断") {
                    Task { await store.runDiagnostics() }
                }
                .keyboardShortcut("d", modifiers: [.command])

                Button("进入轻量模式") {
                    store.enterLightweightMode()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
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
