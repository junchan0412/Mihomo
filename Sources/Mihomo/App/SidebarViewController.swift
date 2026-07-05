import AppKit

@MainActor
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: ((AppSection) -> Void)?

    private let store: AppStore
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let sections = AppSection.allCases

    init(store: AppStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        tableView.headerView = nil
        tableView.rowHeight = 34
        tableView.style = .sourceList
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section")))
        tableView.dataSource = self
        tableView.delegate = self
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        view.addSubview(scrollView)
        scrollView.pinEdges(to: view)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        selectCurrent()
    }

    func refresh() {
        tableView.reloadData()
        selectCurrent()
    }

    private func selectCurrent() {
        if let row = sections.firstIndex(of: store.selectedSection), tableView.selectedRow != row {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let section = sections[row]
        let cell = NSTableCellView()
        let image = NSImageView(image: NSImage(systemSymbolName: section.systemImage, accessibilityDescription: nil) ?? NSImage())
        let title = UI.label(section.title, font: .systemFont(ofSize: 13, weight: .medium))
        image.translatesAutoresizingMaskIntoConstraints = false
        title.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(image)
        cell.addSubview(title)
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 18),
            title.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 8),
            title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < sections.count else { return }
        onSelect?(sections[row])
    }
}
