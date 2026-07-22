import AppKit
import SwiftUI

struct AppKitTableColumn<Row> {
    let title: String
    let width: CGFloat
    let value: (Row) -> String
    let image: ((Row) -> NSImage?)?
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
        image = nil
        checked = nil
        toggle = nil
    }

    init(
        title: String,
        width: CGFloat,
        image: @escaping (Row) -> NSImage?,
        textColor: ((Row) -> NSColor?)? = nil,
        value: @escaping (Row) -> String
    ) {
        self.title = title
        self.width = width
        self.image = image
        self.textColor = textColor
        self.value = value
        checked = nil
        toggle = nil
    }

    init(title: String, width: CGFloat, checked: @escaping (Row) -> Bool, toggle: @escaping (Row) -> Void) {
        self.title = title
        self.width = width
        value = { checked($0) ? "已启用" : "已禁用" }
        image = nil
        textColor = nil
        self.checked = checked
        self.toggle = toggle
    }
}

struct AppKitTableContextAction<Row> {
    let title: String
    let isDestructive: Bool
    let isEnabled: ([Row]) -> Bool
    let action: ([Row]) -> Void

    init(
        _ title: String,
        isDestructive: Bool = false,
        isEnabled: @escaping ([Row]) -> Bool = { _ in true },
        action: @escaping ([Row]) -> Void
    ) {
        self.title = title
        self.isDestructive = isDestructive
        self.isEnabled = isEnabled
        self.action = action
    }
}

struct AppKitTable<Row: Identifiable & Hashable>: NSViewRepresentable where Row.ID: Hashable {
    var rows: [Row]
    @Binding var selection: Set<Row.ID>
    var columns: [AppKitTableColumn<Row>]
    var allowsMultipleSelection: Bool
    var onDoubleClick: ((Row) -> Void)?
    var onActivate: (([Row]) -> Void)?
    var onPreview: (([Row]) -> Void)?
    var onDelete: (([Row]) -> Void)?
    var hasHorizontalScroller: Bool
    var allowsParentScrollPassthrough: Bool
    var borderType: NSBorderType
    var contextMenuActions: [AppKitTableContextAction<Row>]

    init(
        rows: [Row],
        selection: Binding<Row.ID?>,
        columns: [AppKitTableColumn<Row>],
        onDoubleClick: ((Row) -> Void)? = nil,
        onActivate: (([Row]) -> Void)? = nil,
        onPreview: (([Row]) -> Void)? = nil,
        onDelete: (([Row]) -> Void)? = nil,
        hasHorizontalScroller: Bool = true,
        allowsParentScrollPassthrough: Bool = false,
        borderType: NSBorderType = .bezelBorder,
        contextMenuTitle: String? = nil,
        onContextMenu: ((Row) -> Void)? = nil,
        contextMenuActions: [AppKitTableContextAction<Row>] = []
    ) {
        self.rows = rows
        _selection = Binding(
            get: { selection.wrappedValue.map { Set([$0]) } ?? [] },
            set: { selection.wrappedValue = $0.first }
        )
        self.columns = columns
        allowsMultipleSelection = false
        self.onDoubleClick = onDoubleClick
        self.onActivate = onActivate
        self.onPreview = onPreview
        self.onDelete = onDelete
        self.hasHorizontalScroller = hasHorizontalScroller
        self.allowsParentScrollPassthrough = allowsParentScrollPassthrough
        self.borderType = borderType
        self.contextMenuActions = contextMenuActions
        if let contextMenuTitle, let onContextMenu {
            self.contextMenuActions.append(
                AppKitTableContextAction(contextMenuTitle) { selectedRows in
                    guard let row = selectedRows.first else { return }
                    onContextMenu(row)
                }
            )
        }
    }

    init(
        rows: [Row],
        selection: Binding<Set<Row.ID>>,
        columns: [AppKitTableColumn<Row>],
        allowsMultipleSelection: Bool = true,
        onDoubleClick: ((Row) -> Void)? = nil,
        onActivate: (([Row]) -> Void)? = nil,
        onPreview: (([Row]) -> Void)? = nil,
        onDelete: (([Row]) -> Void)? = nil,
        hasHorizontalScroller: Bool = true,
        allowsParentScrollPassthrough: Bool = false,
        borderType: NSBorderType = .bezelBorder,
        contextMenuActions: [AppKitTableContextAction<Row>] = []
    ) {
        self.rows = rows
        _selection = selection
        self.columns = columns
        self.allowsMultipleSelection = allowsMultipleSelection
        self.onDoubleClick = onDoubleClick
        self.onActivate = onActivate
        self.onPreview = onPreview
        self.onDelete = onDelete
        self.hasHorizontalScroller = hasHorizontalScroller
        self.allowsParentScrollPassthrough = allowsParentScrollPassthrough
        self.borderType = borderType
        self.contextMenuActions = contextMenuActions
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
        tableView.allowsMultipleSelection = allowsMultipleSelection
        tableView.allowsEmptySelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.selectionHighlightStyle = .regular
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .textBackgroundColor
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
        scrollView.documentView = tableView

        context.coordinator.configureColumns(on: tableView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.parent = self
        tableView.allowsMultipleSelection = allowsMultipleSelection
        scrollView.hasHorizontalScroller = hasHorizontalScroller
        scrollView.borderType = borderType
        (scrollView as? AppKitTableScrollView)?.allowsParentScrollPassthrough = allowsParentScrollPassthrough
        context.coordinator.configureContextMenu(on: tableView)
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
        private weak var currentTableView: NSTableView?

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

            let currentRow = parent.rows[row]
            let column = parent.columns[columnIndex]
            let identifier = NSUserInterfaceItemIdentifier(
                "MihomoTableCell-\(columnIndex)-\(column.image == nil ? "text" : "image")"
            )
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? makeCell(identifier: identifier, includesImage: column.image != nil)
            let value = column.value(currentRow)
            if let checked = column.checked {
                let identifier = NSUserInterfaceItemIdentifier("MihomoCheckboxCell-\(columnIndex)")
                let button = tableView.makeView(withIdentifier: identifier, owner: self) as? NSButton
                    ?? makeCheckbox(identifier: identifier)
                button.state = checked(currentRow) ? .on : .off
                button.tag = row
                button.setAccessibilityLabel(column.title.isEmpty ? "启用规则" : column.title)
                button.setAccessibilityValue(button.state == .on ? "已启用" : "已禁用")
                return button
            }
            cell.textField?.stringValue = value
            cell.textField?.textColor = column.textColor?(currentRow) ?? .labelColor
            cell.imageView?.image = column.image?(currentRow)
            cell.imageView?.isHidden = cell.imageView?.image == nil
            cell.setAccessibilityLabel("\(column.title)：\(value)")
            return cell
        }

        @objc private func toggleCheckbox(_ sender: NSButton) {
            guard sender.tag >= 0, sender.tag < parent.rows.count,
                  let columnIndex = sender.identifier?.rawValue.split(separator: "-").last.flatMap({ Int($0) }),
                  columnIndex < parent.columns.count
            else { return }
            parent.columns[columnIndex].toggle?(parent.rows[sender.tag])
        }

        func configureContextMenu(on tableView: NSTableView) {
            currentTableView = tableView
            if parent.contextMenuActions.isEmpty {
                tableView.menu = nil
            } else if tableView.menu == nil {
                let menu = NSMenu()
                menu.delegate = self
                tableView.menu = menu
            }
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView = currentTableView else { return }
            selectClickedRowIfNeeded(on: tableView)
            let selectedRows = selectedRows(on: tableView)

            for (index, action) in parent.contextMenuActions.enumerated() {
                let item = NSMenuItem(title: action.title, action: #selector(runContextAction(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.isEnabled = action.isEnabled(selectedRows)
                if action.isDestructive {
                    item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
                }
                menu.addItem(item)
            }
        }

        @objc private func runContextAction(_ sender: NSMenuItem) {
            guard let tableView = currentTableView,
                  parent.contextMenuActions.indices.contains(sender.tag)
            else { return }
            let rows = selectedRows(on: tableView)
            parent.contextMenuActions[sender.tag].action(rows)
        }

        @objc func clicked(_ sender: NSTableView) {
            synchronizeSelection(from: sender)
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let rowIndex = sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow
            guard rowIndex >= 0, rowIndex < parent.rows.count else { return }
            parent.onDoubleClick?(parent.rows[rowIndex])
            activateSelection(on: sender)
        }

        func activateSelection(on tableView: NSTableView) {
            let rows = selectedRows(on: tableView)
            guard rows.isEmpty == false else { return }
            if let onActivate = parent.onActivate {
                onActivate(rows)
            } else if let first = rows.first {
                parent.onDoubleClick?(first)
            }
        }

        func previewSelection(on tableView: NSTableView) {
            let rows = selectedRows(on: tableView)
            guard rows.isEmpty == false else { return }
            if let onPreview = parent.onPreview {
                onPreview(rows)
            } else {
                activateSelection(on: tableView)
            }
        }

        func deleteSelection(on tableView: NSTableView) {
            let rows = selectedRows(on: tableView)
            guard rows.isEmpty == false else { return }
            parent.onDelete?(rows)
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard isApplyingSelection == false,
                  let tableView = notification.object as? NSTableView
            else { return }
            synchronizeSelection(from: tableView)
        }

        func configureColumns(on tableView: NSTableView) {
            currentTableView = tableView
            let nextSignature = parent.columns.map { "\($0.title):\($0.width)" }
            tableView.setAccessibilityLabel("数据表：\(parent.columns.map(\.title).joined(separator: "、"))")
            let selectionHelp = parent.allowsMultipleSelection ? "可使用 Command 或 Shift 选择多行。" : ""
            tableView.setAccessibilityHelp("使用方向键选择行；Return 打开，空格预览，Delete 删除。\(selectionHelp)")
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

            let previousSignature = rowSignature
            let previousRows = lastRows
            lastRows = parent.rows
            rowSignature = nextSignature

            // Prefer in-place row reloads when the set of IDs is stable.
            // This keeps scroll position and selection visually smooth under high-frequency traffic updates.
            if previousSignature.isEmpty == false,
               previousRows.count == parent.rows.count,
               zip(previousRows, parent.rows).allSatisfy({ $0.id == $1.id }) {
                var changed = IndexSet()
                for index in previousSignature.indices where previousSignature[index] != nextSignature[index] {
                    changed.insert(index)
                }
                if changed.isEmpty {
                    return
                }
                let columns = IndexSet(integersIn: 0..<max(tableView.numberOfColumns, 0))
                if columns.isEmpty {
                    tableView.reloadData()
                } else {
                    tableView.reloadData(forRowIndexes: changed, columnIndexes: columns)
                }
                return
            }

            tableView.reloadData()
        }

        func applySelection(on tableView: NSTableView) {
            isApplyingSelection = true
            defer { isApplyingSelection = false }

            let indexes = IndexSet(parent.rows.indices.filter { parent.selection.contains(parent.rows[$0].id) })
            if tableView.selectedRowIndexes != indexes {
                tableView.selectRowIndexes(indexes, byExtendingSelection: false)
            }
        }

        private func synchronizeSelection(from tableView: NSTableView) {
            parent.selection = Set(tableView.selectedRowIndexes.compactMap { index in
                guard parent.rows.indices.contains(index) else { return nil }
                return parent.rows[index].id
            })
        }

        private func selectClickedRowIfNeeded(on tableView: NSTableView) {
            let clickedRow = tableView.clickedRow
            guard clickedRow >= 0, clickedRow < parent.rows.count,
                  tableView.selectedRowIndexes.contains(clickedRow) == false
            else { return }
            tableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            synchronizeSelection(from: tableView)
        }

        private func selectedRows(on tableView: NSTableView) -> [Row] {
            tableView.selectedRowIndexes.compactMap { index in
                guard parent.rows.indices.contains(index) else { return nil }
                return parent.rows[index]
            }
        }

        private func makeCell(identifier: NSUserInterfaceItemIdentifier, includesImage: Bool) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingTail
            textField.usesSingleLineMode = true
            textField.font = .systemFont(ofSize: NSFont.systemFontSize)
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.setAccessibilityElement(false)

            cell.textField = textField
            cell.addSubview(textField)

            if includesImage {
                let imageView = NSImageView()
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.setAccessibilityElement(false)
                cell.imageView = imageView
                cell.addSubview(imageView)

                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 7),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 18),
                    imageView.heightAnchor.constraint(equalToConstant: 18),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            } else {
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }

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
