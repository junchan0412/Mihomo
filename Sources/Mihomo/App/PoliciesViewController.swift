import AppKit

private struct PolicyRow {
    var group: ProxyGroup
    var node: ProxyNode
}

@MainActor
final class PoliciesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, RefreshableContent {
    private let store: AppStore
    private let tableView = NSTableView()
    private var rows: [PolicyRow] = []

    init(store: AppStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        let stack = UI.stack(.vertical, spacing: 14)
        view.addSubview(stack)
        stack.pinEdges(to: view, inset: 24)
        stack.addArrangedSubview(UI.title("Policies"))
        stack.addArrangedSubview(UI.subtitle("Policy groups and selectable proxies from the mihomo controller."))

        let buttons = UI.stack(.horizontal, spacing: 8)
        buttons.addArrangedSubview(UI.button("Use Selected", target: self, action: #selector(useSelected)))
        buttons.addArrangedSubview(UI.button("Refresh", target: self, action: #selector(refreshController)))
        stack.addArrangedSubview(buttons)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        tableView.addTableColumn(column("group", "Group", 180))
        tableView.addTableColumn(column("current", "Current", 180))
        tableView.addTableColumn(column("proxy", "Proxy", 260))
        tableView.addTableColumn(column("type", "Type", 90))
        tableView.addTableColumn(column("delay", "Delay", 80))
        tableView.delegate = self
        tableView.dataSource = self
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 850).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 520).isActive = true
        refresh()
    }

    func refresh() {
        rows = store.proxyGroups.flatMap { group in group.all.map { PolicyRow(group: group, node: $0) } }
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = rows[row]
        let cell = TextCellView()
        switch tableColumn?.identifier.rawValue {
        case "group": cell.label.stringValue = item.group.name
        case "current": cell.label.stringValue = item.group.now
        case "proxy": cell.label.stringValue = (item.group.now == item.node.name ? "✓ " : "") + item.node.name
        case "type": cell.label.stringValue = item.node.type
        case "delay":
            if let delay = item.node.delay, delay > 0 { cell.label.stringValue = "\(delay) ms" } else { cell.label.stringValue = "-" }
        default: cell.label.stringValue = ""
        }
        return cell
    }

    private func column(_ id: String, _ title: String, _ width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        return column
    }

    @objc private func useSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < rows.count else { return }
        let item = rows[row]
        Task { await store.selectProxy(group: item.group.name, proxy: item.node.name) }
    }

    @objc private func refreshController() {
        Task { await store.refreshController() }
    }
}
