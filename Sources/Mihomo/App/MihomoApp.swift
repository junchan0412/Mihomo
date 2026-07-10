import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var openMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if MainWindowPresenter.presentExisting() {
            return false
        }
        openMainWindow?()
        return openMainWindow == nil
    }
}

@main
struct MihomoApp: App {
    @Environment(\.openWindow) private var openWindow
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
                .onOpenURL { url in
                    Task { await store.handleDeepLink(url) }
                }
                .background(MainWindowOpenBridge(openWindow: openWindow, appDelegate: appDelegate))
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("控制") {
                Button("显示主窗口") {
                    MainWindowPresenter.present(openWindow: openWindow)
                }
                .keyboardShortcut("m", modifiers: [.command])

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

                Button(store.settings.tunEnabled ? "关闭 TUN" : "开启 TUN") {
                    Task { await store.setTunEnabled(!store.settings.tunEnabled) }
                }
                .keyboardShortcut("t", modifiers: [.command, .option])

                Button(store.settings.autoSetSystemDNS ? "关闭系统 DNS 接管" : "开启系统 DNS 接管") {
                    var updated = store.settings
                    updated.autoSetSystemDNS.toggle()
                    Task { await store.saveSettings(updated) }
                }
                .keyboardShortcut("n", modifiers: [.command, .option])

                Button("刷新所有订阅") {
                    Task { await store.refreshAllRemoteProfiles() }
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Button("检查更新...") {
                    openWindow(id: "software-update")
                    Task { await store.checkForSoftwareUpdate() }
                }
                .keyboardShortcut("u", modifiers: [.command, .option])

                if let update = store.availableUpdate {
                    Button("安装更新 \(update.version)") {
                        Task { await store.installSoftwareUpdate() }
                    }
                }

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

                Button("导出诊断包") {
                    store.exportDiagnosticBundle()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])

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

        WindowGroup("配置编辑器", id: "profile-editor") {
            ProfileEditorWindowView()
                .environmentObject(store)
                .frame(minWidth: 860, minHeight: 620)
        }
        .defaultSize(width: 980, height: 720)

        Window("连接详情", id: "connection-detail") {
            ConnectionDetailPanelView()
                .environmentObject(store)
                .frame(minWidth: 340, minHeight: 420)
        }
        .defaultSize(width: 380, height: 520)

        Window("软件更新", id: "software-update") {
            SoftwareUpdateWindowView()
                .environmentObject(store)
                .frame(minWidth: 460, minHeight: 360)
        }
        .defaultSize(width: 520, height: 420)

        WindowGroup("覆写管理", id: "fragments-editor") {
            ConfigFragmentsWindowView()
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 860, height: 640)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
        } label: {
            Text(store.menuBarTitle)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MainWindowOpenBridge: View {
    let openWindow: OpenWindowAction
    let appDelegate: AppDelegate

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                appDelegate.openMainWindow = {
                    MainWindowPresenter.present(openWindow: openWindow)
                }
            }
    }
}
