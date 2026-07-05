import AppKit

@main
enum MihomoMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AppStore()
    private var mainWindowController: MainWindowController?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        setupMainMenu()
        mainWindowController = MainWindowController(store: store)
        statusBarController = StatusBarController(store: store)
        mainWindowController?.showWindow(nil)
        Task { await store.bootstrap() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Mihomo", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Mihomo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        let controlItem = NSMenuItem(title: "Control", action: nil, keyEquivalent: "")
        let controlMenu = NSMenu(title: "Control")
        controlMenu.addItem(NSMenuItem(title: "Start / Stop Core", action: #selector(MainWindowController.toggleCoreFromMenu), keyEquivalent: "r"))
        controlMenu.addItem(NSMenuItem(title: "Refresh Controller", action: #selector(MainWindowController.refreshFromMenu), keyEquivalent: "R"))
        controlMenu.addItem(NSMenuItem(title: "Run Diagnostics", action: #selector(MainWindowController.runDiagnosticsFromMenu), keyEquivalent: "d"))
        controlItem.submenu = controlMenu
        mainMenu.addItem(controlItem)

        NSApp.mainMenu = mainMenu
    }
}
