import AppKit
import UniformTypeIdentifiers

@MainActor
final class ProfilesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, RefreshableContent {
    private let store: AppStore
    private let tableView = NSTableView()
    private let remoteName = NSTextField()
    private let remoteURL = NSTextField()

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
        stack.addArrangedSubview(UI.title("Profiles"))
        stack.addArrangedSubview(UI.subtitle("Import local YAML or remote subscriptions, then choose the active runtime profile."))

        let form = UI.stack(.horizontal, spacing: 8)
        remoteName.placeholderString = "Name"
        remoteURL.placeholderString = "Subscription URL"
        remoteName.widthAnchor.constraint(equalToConstant: 160).isActive = true
        remoteURL.widthAnchor.constraint(equalToConstant: 360).isActive = true
        form.addArrangedSubview(remoteName)
        form.addArrangedSubview(remoteURL)
        form.addArrangedSubview(UI.button("Import Remote", target: self, action: #selector(importRemote)))
        form.addArrangedSubview(UI.button("Import Local...", target: self, action: #selector(importLocal)))
        form.addArrangedSubview(UI.button("Activate", target: self, action: #selector(activateSelected)))
        form.addArrangedSubview(UI.button("Refresh", target: self, action: #selector(refreshSelected)))
        stack.addArrangedSubview(form)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        tableView.addTableColumn(column("name", "Name", 240))
        tableView.addTableColumn(column("type", "Type", 80))
        tableView.addTableColumn(column("updated", "Updated", 150))
        tableView.addTableColumn(column("usage", "Usage", 180))
        tableView.delegate = self
        tableView.dataSource = self
        scroll.documentView = tableView
        stack.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true
        scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 820).isActive = true
    }

    func refresh() {
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { store.profiles.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let profile = store.profiles[row]
        let cell = TextCellView()
        switch tableColumn?.identifier.rawValue {
        case "name":
            cell.label.stringValue = (profile.id == store.settings.activeProfileID ? "✓ " : "") + profile.name
        case "type":
            cell.label.stringValue = profile.source.rawValue.capitalized
        case "updated":
            cell.label.stringValue = Formatters.shortDate.string(from: profile.updatedAt)
        case "usage":
            if let total = profile.total {
                let used = (profile.uploadUsed ?? 0) + (profile.downloadUsed ?? 0)
                cell.label.stringValue = "\(Formatters.bytes(used)) / \(Formatters.bytes(total))"
            } else {
                cell.label.stringValue = "-"
            }
        default:
            cell.label.stringValue = ""
        }
        return cell
    }

    private func column(_ id: String, _ title: String, _ width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        return column
    }

    @objc private func importRemote() {
        store.newRemoteName = remoteName.stringValue
        store.newRemoteURL = remoteURL.stringValue
        Task { await store.addRemoteProfile() }
        remoteName.stringValue = ""
        remoteURL.stringValue = ""
    }

    @objc private func importLocal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.yaml, .text]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.importLocalProfile(url: url) }
        }
    }

    @objc private func activateSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < store.profiles.count else { return }
        Task { await store.setActiveProfile(store.profiles[row]) }
    }

    @objc private func refreshSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < store.profiles.count else { return }
        Task { await store.refreshProfile(store.profiles[row]) }
    }
}

private extension UTType {
    static let yaml = UTType(filenameExtension: "yaml") ?? .text
}
