import AppKit

@MainActor
class StackPageViewController: NSViewController, RefreshableContent {
    let store: AppStore
    let scrollView = NSScrollView()
    let stack = NSStackView()

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
        scrollView.hasVerticalScroller = true
        stack.orientation = .vertical
        stack.spacing = 16
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        scrollView.documentView = stack
        view.addSubview(scrollView)
        scrollView.pinEdges(to: view)
        refresh()
    }

    func refresh() {
        guard isViewLoaded else { return }
        stack.removeAllSubviews()
        build(in: stack)
    }

    func build(in stack: NSStackView) {}

    func addHeader(_ title: String, subtitle: String? = nil, to stack: NSStackView) {
        stack.addArrangedSubview(UI.title(title))
        if let subtitle {
            stack.addArrangedSubview(UI.subtitle(subtitle))
        }
    }
}
