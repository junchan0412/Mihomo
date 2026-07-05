import AppKit

@MainActor
final class StatusBarController {
    private let store: AppStore
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var observerID: UUID?

    init(store: AppStore) {
        self.store = store
        observerID = store.observe { [weak self] in self?.refresh() }
        refresh()
    }

    deinit {
        if let observerID {
            Task { @MainActor [store] in store.removeObserver(observerID) }
        }
    }

    private func refresh() {
        item.button?.title = store.menuBarTitle
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: store.isCoreRunning ? "Stop Core" : "Start Core", action: #selector(toggleCore), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: store.systemProxyEnabled ? "Disable Proxy" : "Enable Proxy", action: #selector(toggleProxy), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Mode: \(store.currentMode)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Rule Mode", action: #selector(modeRule), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Global Mode", action: #selector(modeGlobal), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Direct Mode", action: #selector(modeDirect), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshController), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Diagnostics", action: #selector(runDiagnostics), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for menuItem in menu.items {
            menuItem.target = self
        }
        item.menu = menu
    }

    @objc private func toggleCore() { Task { await store.toggleCore() } }
    @objc private func toggleProxy() { Task { await store.toggleSystemProxy() } }
    @objc private func modeRule() { Task { await store.setMode("rule") } }
    @objc private func modeGlobal() { Task { await store.setMode("global") } }
    @objc private func modeDirect() { Task { await store.setMode("direct") } }
    @objc private func refreshController() { Task { await store.refreshController() } }
    @objc private func runDiagnostics() { Task { await store.runDiagnostics() } }
}
