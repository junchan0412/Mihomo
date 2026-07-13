import AppKit

final class AppKitAccessibleTableView: NSTableView {
    var onActivateSelection: (() -> Void)?
    var onPreviewSelection: (() -> Void)?
    var onDeleteSelection: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            guard selectedRow >= 0, let onActivateSelection else {
                super.keyDown(with: event)
                return
            }
            onActivateSelection()
            return
        }

        if event.charactersIgnoringModifiers == " " {
            guard selectedRow >= 0, let onPreviewSelection else {
                super.keyDown(with: event)
                return
            }
            onPreviewSelection()
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            guard selectedRow >= 0, let onDeleteSelection else {
                super.keyDown(with: event)
                return
            }
            onDeleteSelection()
            return
        }

        super.keyDown(with: event)
    }
}

final class AppKitTableScrollView: NSScrollView {
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
