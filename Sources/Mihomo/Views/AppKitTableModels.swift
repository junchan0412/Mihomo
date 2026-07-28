import AppKit

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
