import AppKit

@MainActor
final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private let store: AppStore
    private let splitViewController = NSSplitViewController()
    private let sidebarController: SidebarViewController
    private var contentController: NSViewController?
    private var observerID: UUID?

    init(store: AppStore) {
        self.store = store
        self.sidebarController = SidebarViewController(store: store)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Mihomo"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        super.init(window: window)

        sidebarController.onSelect = { [weak self] section in
            self?.store.selectedSection = section
            self?.show(section)
        }

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = 190
        sidebarItem.maximumThickness = 260
        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: NSViewController()))
        window.contentViewController = splitViewController

        let toolbar = NSToolbar(identifier: "MihomoToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar

        observerID = store.observe { [weak self] in
            self?.sidebarController.refresh()
            (self?.contentController as? RefreshableContent)?.refresh()
            self?.window?.toolbar?.validateVisibleItems()
        }
        show(.overview)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observerID {
            Task { @MainActor [store] in store.removeObserver(observerID) }
        }
    }

    private func show(_ section: AppSection) {
        let controller: NSViewController
        switch section {
        case .overview: controller = OverviewViewController(store: store)
        case .activity: controller = ActivityViewController(store: store)
        case .policies: controller = PoliciesViewController(store: store)
        case .profiles: controller = ProfilesViewController(store: store)
        case .logs: controller = LogsViewController(store: store)
        case .diagnostics: controller = DiagnosticsViewController(store: store)
        case .settings: controller = SettingsViewController(store: store)
        }
        contentController = controller
        splitViewController.splitViewItems[1].viewController = controller
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleCore, .systemProxy, .modeRule, .modeGlobal, .modeDirect, .diagnostics, .refresh, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleCore, .systemProxy, .flexibleSpace, .modeRule, .modeGlobal, .modeDirect, .diagnostics, .refresh]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self
        switch itemIdentifier {
        case .toggleCore:
            item.label = store.isCoreRunning ? "Stop" : "Start"
            item.image = NSImage(systemSymbolName: store.isCoreRunning ? "stop.fill" : "play.fill", accessibilityDescription: nil)
            item.action = #selector(toggleCore)
        case .systemProxy:
            item.label = store.systemProxyEnabled ? "Proxy On" : "Proxy Off"
            item.image = NSImage(systemSymbolName: "network", accessibilityDescription: nil)
            item.action = #selector(toggleSystemProxy)
        case .modeRule:
            item.label = "Rule"
            item.image = NSImage(systemSymbolName: store.currentMode == "rule" ? "checkmark.circle.fill" : "circle", accessibilityDescription: nil)
            item.action = #selector(modeRule)
        case .modeGlobal:
            item.label = "Global"
            item.image = NSImage(systemSymbolName: store.currentMode == "global" ? "checkmark.circle.fill" : "circle", accessibilityDescription: nil)
            item.action = #selector(modeGlobal)
        case .modeDirect:
            item.label = "Direct"
            item.image = NSImage(systemSymbolName: store.currentMode == "direct" ? "checkmark.circle.fill" : "circle", accessibilityDescription: nil)
            item.action = #selector(modeDirect)
        case .diagnostics:
            item.label = "Diagnostics"
            item.image = NSImage(systemSymbolName: "stethoscope", accessibilityDescription: nil)
            item.action = #selector(runDiagnostics)
        case .refresh:
            item.label = "Refresh"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
            item.action = #selector(refresh)
        default:
            return nil
        }
        return item
    }

    @objc private func toggleCore() { Task { await store.toggleCore() } }
    @objc private func toggleSystemProxy() { Task { await store.toggleSystemProxy() } }
    @objc private func modeRule() { Task { await store.setMode("rule") } }
    @objc private func modeGlobal() { Task { await store.setMode("global") } }
    @objc private func modeDirect() { Task { await store.setMode("direct") } }
    @objc private func refresh() { Task { await store.refreshController() } }
    @objc private func runDiagnostics() { Task { await store.runDiagnostics() } }

    @objc func toggleCoreFromMenu() { toggleCore() }
    @objc func refreshFromMenu() { refresh() }
    @objc func runDiagnosticsFromMenu() { runDiagnostics() }
}

private extension NSToolbarItem.Identifier {
    static let toggleCore = NSToolbarItem.Identifier("toggleCore")
    static let systemProxy = NSToolbarItem.Identifier("systemProxy")
    static let modeRule = NSToolbarItem.Identifier("modeRule")
    static let modeGlobal = NSToolbarItem.Identifier("modeGlobal")
    static let modeDirect = NSToolbarItem.Identifier("modeDirect")
    static let diagnostics = NSToolbarItem.Identifier("diagnostics")
    static let refresh = NSToolbarItem.Identifier("refresh")
}
