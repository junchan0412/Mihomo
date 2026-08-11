import AppKit

extension AppKitTable {
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = AppKitAccessibleTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.action = #selector(Coordinator.clicked(_:))
        tableView.doubleAction = #selector(Coordinator.doubleClicked(_:))
        tableView.headerView = NSTableHeaderView()
        tableView.allowsMultipleSelection = allowsMultipleSelection
        tableView.allowsEmptySelection = true
        tableView.selectionHighlightStyle = .regular
        tableView.rowHeight = 28
        tableView.intercellSpacing = .zero
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = []
        tableView.backgroundColor = .controlBackgroundColor
        if contextMenuActions.isEmpty == false {
            let menu = NSMenu()
            menu.delegate = context.coordinator
            tableView.menu = menu
        }
        tableView.onActivateSelection = { [weak coordinator = context.coordinator, weak tableView] in
            guard let coordinator, let tableView else { return }
            coordinator.activateSelection(on: tableView)
        }
        tableView.onPreviewSelection = { [weak coordinator = context.coordinator, weak tableView] in
            guard let coordinator, let tableView else { return }
            coordinator.previewSelection(on: tableView)
        }
        tableView.onDeleteSelection = { [weak coordinator = context.coordinator, weak tableView] in
            guard let coordinator, let tableView else { return }
            coordinator.deleteSelection(on: tableView)
        }

        let scrollView = AppKitTableScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = hasHorizontalScroller
        scrollView.allowsParentScrollPassthrough = allowsParentScrollPassthrough
        scrollView.autohidesScrollers = true
        scrollView.borderType = borderType
        scrollView.drawsBackground = false
        scrollView.documentView = tableView

        context.coordinator.configureColumns(on: tableView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.parent = self
        tableView.allowsMultipleSelection = allowsMultipleSelection
        tableView.intercellSpacing = .zero
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = []
        tableView.backgroundColor = .controlBackgroundColor
        scrollView.hasHorizontalScroller = hasHorizontalScroller
        scrollView.borderType = borderType
        scrollView.drawsBackground = false
        (scrollView as? AppKitTableScrollView)?.allowsParentScrollPassthrough = allowsParentScrollPassthrough
        context.coordinator.configureContextMenu(on: tableView)
        context.coordinator.configureColumns(on: tableView)
        context.coordinator.reloadDataIfNeeded(on: tableView)
        context.coordinator.applySelection(on: tableView)
    }
}
