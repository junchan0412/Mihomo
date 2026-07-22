import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var openMainWindow: (() -> Void)?
    weak var store: AppStore?

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

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(dockItem("显示主窗口", action: #selector(showMainWindowFromDock)))
        menu.addItem(.separator())

        let coreTitle = store?.isCoreRunning == true ? "停止核心" : "启动核心"
        menu.addItem(dockItem(coreTitle, action: #selector(toggleCoreFromDock)))

        let proxyTitle = store?.systemProxyEnabled == true ? "关闭系统代理" : "开启系统代理"
        let proxyItem = dockItem(proxyTitle, action: #selector(toggleSystemProxyFromDock))
        proxyItem.isEnabled = store?.isCoreRunning == true || store?.systemProxyEnabled == true
        menu.addItem(proxyItem)
        menu.addItem(.separator())

        menu.addItem(modeDockItem("规则模式", mode: "rule"))
        menu.addItem(modeDockItem("全局模式", mode: "global"))
        menu.addItem(modeDockItem("直连模式", mode: "direct"))
        return menu
    }

    @objc private func showMainWindowFromDock() {
        store?.isLightweightModeActive = false
        openMainWindow?()
    }

    @objc private func toggleCoreFromDock() {
        guard let store else { return }
        Task { await store.toggleCore() }
    }

    @objc private func toggleSystemProxyFromDock() {
        guard let store else { return }
        Task { await store.toggleSystemProxy() }
    }

    @objc private func setModeFromDock(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String, let store else { return }
        Task { await store.setMode(mode) }
    }

    private func dockItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func modeDockItem(_ title: String, mode: String) -> NSMenuItem {
        let item = dockItem(title, action: #selector(setModeFromDock(_:)))
        item.representedObject = mode
        item.state = store?.currentMode == mode ? .on : .off
        item.isEnabled = store?.isCoreRunning == true
        return item
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
                .environmentObject(store.logStore)
                .environmentObject(store.activityStore)
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
                .background(MainWindowOpenBridge(store: store, appDelegate: appDelegate))
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            MihomoCommands(store: store)
        }

        WindowGroup("配置编辑器", for: UUID.self) { $profileID in
            if let profileID {
                ProfileEditorWindowView(profileID: profileID)
                    .environmentObject(store)
                    .frame(minWidth: 860, minHeight: 620)
            } else {
                ContentUnavailableView("未选择配置", systemImage: "doc.text.magnifyingglass")
            }
        }
        .defaultSize(width: 980, height: 720)

        WindowGroup("覆写编辑器", for: ConfigFragmentEditorRoute.self) { $route in
            if let route {
                ConfigFragmentEditorWindowView(route: route)
                    .environmentObject(store)
                    .frame(minWidth: 720, minHeight: 620)
            } else {
                ContentUnavailableView("未选择覆写", systemImage: "doc.text.magnifyingglass")
            }
        }
        .defaultSize(width: 840, height: 720)

        WindowGroup("覆写快速查看", for: ConfigFragmentPreviewRoute.self) { $route in
            if let route {
                ConfigFragmentPreviewWindowView(route: route)
                    .environmentObject(store)
                    .frame(minWidth: 760, minHeight: 560)
            } else {
                ContentUnavailableView("未选择覆写", systemImage: "doc.text.magnifyingglass")
            }
        }
        .defaultSize(width: 920, height: 720)

        Window("连接", id: "connections") {
            ActivityView()
                .environmentObject(store)
                .environmentObject(store.activityStore)
                .frame(minWidth: 1080, minHeight: 660)
                .background(WindowIdentifierView(identifier: AppWindowIdentifier.connections))
        }
        .defaultSize(width: 1420, height: 820)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)

        Window("连接详情", id: "connection-detail") {
            ConnectionDetailPanelView()
                .environmentObject(store)
                .environmentObject(store.activityStore)
                .frame(minWidth: 340, minHeight: 420)
        }
        .defaultSize(width: 380, height: 520)

        Window("软件更新", id: "software-update") {
            SoftwareUpdateWindowView()
                .environmentObject(store)
                .frame(minWidth: 700, minHeight: 560)
        }
        .defaultSize(width: 760, height: 640)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(store.logStore)
        } label: {
            MenuBarStatusLabel(store: store, activityStore: store.activityStore)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject var store: AppStore
    @ObservedObject var activityStore: RuntimeActivityStore

    var body: some View {
        HStack(spacing: 4) {
            MenuBarTrafficMark(mode: store.currentMode)

            if store.settings.showMenuBarTrafficRates {
                VStack(alignment: .trailing, spacing: -2) {
                    Text(Formatters.rate(activityStore.uploadRate))
                    Text(Formatters.rate(activityStore.downloadRate))
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .monospacedDigit()
                .frame(minWidth: 42, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(MihomoUI.Motion.quick, value: activityStore.uploadRate)
                .animation(MihomoUI.Motion.quick, value: activityStore.downloadRate)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "上传 \(Formatters.rate(activityStore.uploadRate))，下载 \(Formatters.rate(activityStore.downloadRate))"
                )
            }
        }
        .accessibilityLabel("Mihomo · \(modeAccessibilityTitle) · \(store.menuBarTitle)")
    }

    private var modeAccessibilityTitle: String {
        switch store.currentMode {
        case "global": return "全局模式"
        case "direct": return "直连模式"
        default: return "规则模式"
        }
    }
}

private struct MenuBarTrafficMark: View {
    let mode: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MihomoMarkShape()
                .stroke(
                    LinearGradient(
                        colors: [.cyan, .blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(
                        lineWidth: 2,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: 14, height: 14)
                .padding(1)

            Text(MenuBarPresentation.modeLetter(for: mode))
                .font(.system(size: 5.5, weight: .bold, design: .rounded))
                .foregroundStyle(modeColor)
                .frame(width: 6, height: 6)
                .background(
                    Circle().fill(Color(nsColor: .controlBackgroundColor))
                )
        }
        .frame(width: 20, height: 18)
        .accessibilityHidden(true)
    }

    private var modeColor: Color {
        switch mode.lowercased() {
        case "global": return .blue
        case "direct": return .green
        default: return .orange
        }
    }
}

enum MenuBarPresentation {
    static func modeLetter(for mode: String) -> String {
        switch mode.lowercased() {
        case "global": return "G"
        case "direct": return "D"
        default: return "R"
        }
    }
}

private struct MainWindowOpenBridge: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: AppStore
    let appDelegate: AppDelegate

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                appDelegate.store = store
                appDelegate.openMainWindow = {
                    store.isLightweightModeActive = false
                    MainWindowPresenter.present(openWindow: openWindow)
                }
            }
    }
}
