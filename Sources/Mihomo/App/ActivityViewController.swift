import AppKit

@MainActor
final class ActivityViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, RefreshableContent {
    private let store: AppStore
    private let tableView = NSTableView()
    private let summary = UI.subtitle("")

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
        stack.addArrangedSubview(UI.title("Activity"))
        stack.addArrangedSubview(summary)
        let buttonRow = UI.stack(.horizontal, spacing: 8)
        buttonRow.addArrangedSubview(UI.button("Refresh", target: self, action: #selector(refreshController)))
        buttonRow.addArrangedSubview(UI.button("Close All Connections", target: self, action: #selector(closeAllConnections)))
        stack.addArrangedSubview(buttonRow)

        let scroll = NSScrollView()
        tableView.addTableColumn(column("host", "Host", 220))
        tableView.addTableColumn(column("process", "Process", 160))
        tableView.addTableColumn(column("rule", "Rule", 160))
        tableView.addTableColumn(column("chain", "Chain", 260))
        tableView.addTableColumn(column("traffic", "Traffic", 170))
        tableView.delegate = self
        tableView.dataSource = self
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 920).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 520).isActive = true
        refresh()
    }

    func refresh() {
        summary.stringValue = "\(store.connections.count) connections  ·  ↓ \(Formatters.rate(store.downloadRate))  ·  ↑ \(Formatters.rate(store.uploadRate))"
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { store.connections.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = store.connections[row]
        let cell = TextCellView()
        switch tableColumn?.identifier.rawValue {
        case "host": cell.label.stringValue = item.host
        case "process": cell.label.stringValue = item.process
        case "rule": cell.label.stringValue = item.rule
        case "chain": cell.label.stringValue = item.chain.isEmpty ? "-" : item.chain
        case "traffic": cell.label.stringValue = "\(Formatters.bytes(item.download)) ↓  \(Formatters.bytes(item.upload)) ↑"
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

    @objc private func refreshController() { Task { await store.refreshController() } }
    @objc private func closeAllConnections() { Task { await store.closeAllConnections() } }
}
