import AppKit
import SwiftUI

struct AppKitTableColumn<Row> {
    let title: String
    let width: CGFloat
    let value: (Row) -> String
    let textColor: ((Row) -> NSColor?)?

    init(
        title: String,
        width: CGFloat,
        textColor: ((Row) -> NSColor?)? = nil,
        value: @escaping (Row) -> String
    ) {
        self.title = title
        self.width = width
        self.textColor = textColor
        self.value = value
    }
}

struct AppKitTable<Row: Identifiable>: NSViewRepresentable where Row.ID: Hashable {
    var rows: [Row]
    @Binding var selection: Row.ID?
    var columns: [AppKitTableColumn<Row>]
    var onDoubleClick: ((Row) -> Void)?
    var hasHorizontalScroller: Bool

    init(
        rows: [Row],
        selection: Binding<Row.ID?>,
        columns: [AppKitTableColumn<Row>],
        onDoubleClick: ((Row) -> Void)? = nil,
        hasHorizontalScroller: Bool = true
    ) {
        self.rows = rows
        self._selection = selection
        self.columns = columns
        self.onDoubleClick = onDoubleClick
        self.hasHorizontalScroller = hasHorizontalScroller
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.action = #selector(Coordinator.clicked(_:))
        tableView.doubleAction = #selector(Coordinator.doubleClicked(_:))
        tableView.headerView = NSTableHeaderView()
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.selectionHighlightStyle = .regular
        tableView.rowHeight = 26
        tableView.intercellSpacing = NSSize(width: 0, height: 2)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = hasHorizontalScroller
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView

        context.coordinator.configureColumns(on: tableView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.parent = self
        scrollView.hasHorizontalScroller = hasHorizontalScroller
        context.coordinator.configureColumns(on: tableView)
        tableView.reloadData()
        context.coordinator.applySelection(on: tableView)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: AppKitTable
        private var columnSignature: [String] = []
        private var isApplyingSelection = false

        init(_ parent: AppKitTable) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.rows.count,
                  let tableColumn,
                  let columnIndex = tableView.tableColumns.firstIndex(of: tableColumn),
                  columnIndex < parent.columns.count
            else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("MihomoTableCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? makeCell(identifier: identifier)
            let currentRow = parent.rows[row]
            let column = parent.columns[columnIndex]
            cell.textField?.stringValue = column.value(currentRow)
            cell.textField?.textColor = column.textColor?(currentRow) ?? .labelColor
            return cell
        }

        @objc func clicked(_ sender: NSTableView) {
            let row = sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow
            guard row >= 0, row < parent.rows.count else { return }
            parent.selection = parent.rows[row].id
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow
            guard row >= 0, row < parent.rows.count else { return }
            parent.selection = parent.rows[row].id
            parent.onDoubleClick?(parent.rows[row])
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            guard row >= 0, row < parent.rows.count else { return false }
            parent.selection = parent.rows[row].id
            return true
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection,
                  let tableView = notification.object as? NSTableView
            else { return }

            let selectedRow = tableView.selectedRow
            if selectedRow >= 0, selectedRow < parent.rows.count {
                parent.selection = parent.rows[selectedRow].id
            } else {
                parent.selection = nil
            }
        }

        func configureColumns(on tableView: NSTableView) {
            let nextSignature = parent.columns.map { "\($0.title):\($0.width)" }
            guard nextSignature != columnSignature else { return }

            tableView.tableColumns.forEach { tableView.removeTableColumn($0) }
            for (index, column) in parent.columns.enumerated() {
                let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column-\(index)"))
                tableColumn.title = column.title
                tableColumn.width = column.width
                tableColumn.minWidth = min(column.width, 80)
                tableColumn.resizingMask = .userResizingMask
                tableView.addTableColumn(tableColumn)
            }
            columnSignature = nextSignature
        }

        func applySelection(on tableView: NSTableView) {
            isApplyingSelection = true
            defer { isApplyingSelection = false }

            guard let selection = parent.selection,
                  let row = parent.rows.firstIndex(where: { $0.id == selection })
            else {
                tableView.deselectAll(nil)
                return
            }

            if tableView.selectedRow != row {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }

        private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingTail
            textField.usesSingleLineMode = true
            textField.font = .systemFont(ofSize: NSFont.systemFontSize)
            textField.translatesAutoresizingMaskIntoConstraints = false

            cell.textField = textField
            cell.addSubview(textField)

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])

            return cell
        }
    }
}
