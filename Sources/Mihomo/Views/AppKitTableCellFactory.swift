import AppKit

enum AppKitTableCellFactory {
    static func makeCell(
        identifier: NSUserInterfaceItemIdentifier,
        includesImage: Bool
    ) -> NSTableCellView {
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

    static func makeCheckbox(
        identifier: NSUserInterfaceItemIdentifier,
        target: AnyObject?,
        action: Selector
    ) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: target, action: action)
        button.identifier = identifier
        button.setButtonType(.switch)
        return button
    }
}
