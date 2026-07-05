import AppKit

@MainActor
final class LogsViewController: NSViewController, RefreshableContent {
    private let store: AppStore
    private let textView = NSTextView()

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
        stack.addArrangedSubview(UI.title("Logs"))
        stack.addArrangedSubview(UI.subtitle("Runtime and controller events captured by the app."))
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        scroll.documentView = textView
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 900).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 560).isActive = true
        refresh()
    }

    func refresh() {
        textView.string = store.logs.map { "[\(Formatters.logTime.string(from: $0.date))] \($0.level.uppercased()) \($0.message)" }.joined(separator: "\n")
        textView.scrollToEndOfDocument(nil)
    }
}
