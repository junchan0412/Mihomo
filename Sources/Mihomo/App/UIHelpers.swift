import AppKit

@MainActor
enum UI {
    static func label(_ text: String, font: NSFont = .systemFont(ofSize: 13), color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    static func title(_ text: String) -> NSTextField {
        label(text, font: .boldSystemFont(ofSize: 28))
    }

    static func subtitle(_ text: String) -> NSTextField {
        label(text, font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
    }

    static func button(_ title: String, target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        return button
    }

    static func stack(_ orientation: NSUserInterfaceLayoutOrientation = .vertical, spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = orientation
        stack.spacing = spacing
        stack.alignment = orientation == .vertical ? .leading : .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    static func box(title: String) -> (NSBox, NSStackView) {
        let box = NSBox()
        box.title = title
        box.boxType = .primary
        box.translatesAutoresizingMaskIntoConstraints = false
        let stack = UI.stack(.vertical, spacing: 8)
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        box.contentView = stack
        return (box, stack)
    }
}

extension NSView {
    func pinEdges(to parent: NSView, inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
        ])
    }

    func removeAllSubviews() {
        subviews.forEach { $0.removeFromSuperview() }
    }
}

@MainActor
protocol RefreshableContent: AnyObject {
    func refresh()
}

@MainActor
final class TextCellView: NSTableCellView {
    let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
