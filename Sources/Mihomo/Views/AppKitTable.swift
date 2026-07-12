import AppKit
import SwiftUI

struct AppKitTableColumn<Row> {
    let title: String
    let width: CGFloat
    let value: (Row) -> String
    let textColor: ((Row) -> NSColor?)?
    let checked: ((Row) -> Bool)?
    let toggle: ((Row) -> Void)?

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
        self.checked = nil
        self.toggle = nil
    }

    init(title: String, width: CGFloat, checked: @escaping (Row) -> Bool, toggle: @escaping (Row) -> Void) {
        self.title = title
        self.width = width
        self.value = { checked($0) ? "已启用" : "已禁用" }
        self.textColor = nil
        self.checked = checked
        self.toggle = toggle
    }
}

struct AppKitTable<Row: Identifiable & Hashable>: NSViewRepresentable where Row.ID: Hashable {
    var rows: [Row]
    @Binding var selection: Row.ID?
    var columns: [AppKitTableColumn<Row>]
    var onDoubleClick: ((Row) -> Void)?
    var hasHorizontalScroller: Bool
    var allowsParentScrollPassthrough: Bool
    var borderType: NSBorderType
    var contextMenuTitle: String?
    var onContextMenu: ((Row) -> Void)?

    init(
        rows: [Row],
        selection: Binding<Row.ID?>,
        columns: [AppKitTableColumn<Row>],
        onDoubleClick: ((Row) -> Void)? = nil,
        hasHorizontalScroller: Bool = true,
        allowsParentScrollPassthrough: Bool = false,
        borderType: NSBorderType = .bezelBorder,
        contextMenuTitle: String? = nil,
        onContextMenu: ((Row) -> Void)? = nil
    ) {
        self.rows = rows
        self._selection = selection
        self.columns = columns
        self.onDoubleClick = onDoubleClick
        self.hasHorizontalScroller = hasHorizontalScroller
        self.allowsParentScrollPassthrough = allowsParentScrollPassthrough
        self.borderType = borderType
        self.contextMenuTitle = contextMenuTitle
        self.onContextMenu = onContextMenu
    }

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
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.selectionHighlightStyle = .regular
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .textBackgroundColor
        if contextMenuTitle != nil {
            let menu = NSMenu()
            menu.delegate = context.coordinator
            tableView.menu = menu
        }
        tableView.onActivateSelection = { [weak coordinator = context.coordinator, weak tableView] in
            guard let coordinator, let tableView else { return }
            coordinator.activateSelection(on: tableView)
        }

        let scrollView = AppKitTableScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = hasHorizontalScroller
        scrollView.allowsParentScrollPassthrough = allowsParentScrollPassthrough
        scrollView.autohidesScrollers = true
        scrollView.borderType = borderType
        scrollView.documentView = tableView

        context.coordinator.configureColumns(on: tableView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.parent = self
        scrollView.hasHorizontalScroller = hasHorizontalScroller
        scrollView.borderType = borderType
        (scrollView as? AppKitTableScrollView)?.allowsParentScrollPassthrough = allowsParentScrollPassthrough
        context.coordinator.configureColumns(on: tableView)
        context.coordinator.reloadDataIfNeeded(on: tableView)
        context.coordinator.applySelection(on: tableView)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: AppKitTable
        private var columnSignature: [String] = []
        private var lastRows: [Row] = []
        private var rowSignature: [String] = []
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
            let value = column.value(currentRow)
            if let checked = column.checked {
                let identifier = NSUserInterfaceItemIdentifier("MihomoCheckboxCell-\(columnIndex)")
                let button = tableView.makeView(withIdentifier: identifier, owner: self) as? NSButton ?? makeCheckbox(identifier: identifier)
                button.state = checked(currentRow) ? .on : .off
                button.tag = row
                button.setAccessibilityLabel(column.title.isEmpty ? "启用规则" : column.title)
                button.setAccessibilityValue(button.state == .on ? "已启用" : "已禁用")
                return button
            }
            cell.textField?.stringValue = value
            cell.textField?.textColor = column.textColor?(currentRow) ?? .labelColor
            cell.setAccessibilityLabel("\(column.title)：\(value)")
            return cell
        }

        @objc private func toggleCheckbox(_ sender: NSButton) {
            guard sender.tag >= 0, sender.tag < parent.rows.count,
                  let columnIndex = sender.identifier?.rawValue.split(separator: "-").last.flatMap({ Int($0) }),
                  columnIndex < parent.columns.count else { return }
            parent.columns[columnIndex].toggle?(parent.rows[sender.tag])
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let title = parent.contextMenuTitle, parent.onContextMenu != nil else { return }
            let item = NSMenuItem(title: title, action: #selector(runContextAction), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        @objc private func runContextAction() {
            guard let tableView = currentTableView,
                  tableView.clickedRow >= 0, tableView.clickedRow < parent.rows.count else { return }
            parent.onContextMenu?(parent.rows[tableView.clickedRow])
        }

        private weak var currentTableView: NSTableView?

        @objc func clicked(_ sender: NSTableView) {
            let row = sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow
            guard row >= 0, row < parent.rows.count else { return }
            parent.selection = parent.rows[row].id
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            activateSelection(on: sender)
        }

        func activateSelection(on tableView: NSTableView) {
            let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
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
            currentTableView = tableView
            let nextSignature = parent.columns.map { "\($0.title):\($0.width)" }
            tableView.setAccessibilityLabel("数据表：\(parent.columns.map(\.title).joined(separator: "、"))")
            tableView.setAccessibilityHelp("使用方向键选择行；支持详情的表格可按 Return、Enter 或空格打开所选行。")
            guard nextSignature != columnSignature else { return }

            tableView.tableColumns.forEach { tableView.removeTableColumn($0) }
            for (index, column) in parent.columns.enumerated() {
                let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column-\(index)"))
                tableColumn.title = column.title
                tableColumn.width = column.width
                tableColumn.minWidth = min(column.width, 80)
                tableColumn.resizingMask = .userResizingMask
                tableColumn.headerCell.font = .systemFont(ofSize: 12, weight: .semibold)
                tableColumn.headerCell.textColor = .secondaryLabelColor
                tableView.addTableColumn(tableColumn)
            }
            columnSignature = nextSignature
            lastRows = []
            rowSignature = []
        }

        func reloadDataIfNeeded(on tableView: NSTableView) {
            guard parent.rows != lastRows || rowSignature.isEmpty else { return }

            let nextSignature = parent.rows.map { row in
                let values = parent.columns.map { $0.value(row) }.joined(separator: "\u{1f}")
                return "\(row.id)\u{1e}\(values)"
            }
            guard nextSignature != rowSignature else {
                lastRows = parent.rows
                return
            }
            lastRows = parent.rows
            rowSignature = nextSignature
            tableView.reloadData()
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
            textField.font = .systemFont(ofSize: 13)
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.setAccessibilityElement(false)

            cell.textField = textField
            cell.addSubview(textField)

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])

            return cell
        }

        private func makeCheckbox(identifier: NSUserInterfaceItemIdentifier) -> NSButton {
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleCheckbox(_:)))
            button.identifier = identifier
            button.setButtonType(.switch)
            return button
        }
    }
}

final class AppKitAccessibleTableView: NSTableView {
    var onActivateSelection: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isActivationKey = event.keyCode == 36 || event.keyCode == 76 || event.charactersIgnoringModifiers == " "
        if isActivationKey, selectedRow >= 0, let onActivateSelection {
            onActivateSelection()
            return
        }
        super.keyDown(with: event)
    }
}

private final class AppKitTableScrollView: NSScrollView {
    var allowsParentScrollPassthrough = false

    override func scrollWheel(with event: NSEvent) {
        guard allowsParentScrollPassthrough else {
            super.scrollWheel(with: event)
            return
        }

        guard shouldPassVerticalScrollToParent(event), let nextResponder else {
            super.scrollWheel(with: event)
            return
        }

        nextResponder.scrollWheel(with: event)
    }

    private func shouldPassVerticalScrollToParent(_ event: NSEvent) -> Bool {
        guard abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else { return false }

        let visibleHeight = contentView.bounds.height
        let contentHeight = tableContentHeight
        guard contentHeight > visibleHeight + 1 else { return true }

        let originY = contentView.bounds.origin.y
        let maxY = max(0, contentHeight - visibleHeight)

        if originY <= 1, event.scrollingDeltaY > 0 {
            return true
        }
        if originY >= maxY - 1, event.scrollingDeltaY < 0 {
            return true
        }
        return false
    }

    private var tableContentHeight: CGFloat {
        guard let tableView = documentView as? NSTableView else {
            return documentView?.bounds.height ?? 0
        }

        let headerHeight = tableView.headerView?.frame.height ?? 0
        let rowStride = tableView.rowHeight + tableView.intercellSpacing.height
        return headerHeight + CGFloat(tableView.numberOfRows) * rowStride
    }
}
