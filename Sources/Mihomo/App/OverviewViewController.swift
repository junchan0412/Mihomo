import AppKit

@MainActor
final class OverviewViewController: StackPageViewController {
    override func build(in stack: NSStackView) {
        addHeader("Overview", subtitle: store.activeProfile?.name ?? "No active profile", to: stack)

        let grid = NSGridView(views: [
            [
                card("Core", store.coreStatus, image: "cpu", good: store.isCoreRunning),
                card("Controller", store.coreVersion, image: "point.3.connected.trianglepath.dotted", good: store.coreVersion != "unknown"),
                card("System Proxy", store.systemProxyEnabled ? "Enabled" : "Disabled", image: "network", good: store.systemProxyEnabled)
            ],
            [
                card("TUN", store.settings.tunEnabled ? "Configured" : "Off", image: "lock.shield", good: store.settings.tunEnabled),
                card("Download", Formatters.rate(store.downloadRate), image: "arrow.down", good: true),
                card("Upload", Formatters.rate(store.uploadRate), image: "arrow.up", good: true)
            ]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.columnSpacing = 12
        grid.rowSpacing = 12
        stack.addArrangedSubview(grid)
        grid.widthAnchor.constraint(greaterThanOrEqualToConstant: 760).isActive = true

        let (actionsBox, actions) = UI.box(title: "Quick Actions")
        let row = UI.stack(.horizontal, spacing: 10)
        row.addArrangedSubview(UI.button(store.isCoreRunning ? "Stop Core" : "Start Core", target: self, action: #selector(toggleCore)))
        row.addArrangedSubview(UI.button(store.systemProxyEnabled ? "Disable System Proxy" : "Enable System Proxy", target: self, action: #selector(toggleProxy)))
        row.addArrangedSubview(UI.button("Refresh", target: self, action: #selector(refreshController)))
        row.addArrangedSubview(UI.button("Diagnostics", target: self, action: #selector(runDiagnostics)))
        actions.addArrangedSubview(row)
        stack.addArrangedSubview(actionsBox)
        actionsBox.widthAnchor.constraint(greaterThanOrEqualToConstant: 760).isActive = true

        let (logBox, logStack) = UI.box(title: "Recent Logs")
        for entry in store.logs.suffix(8) {
            logStack.addArrangedSubview(UI.label("[\(Formatters.logTime.string(from: entry.date))] \(entry.level.uppercased()) \(entry.message)", font: .monospacedSystemFont(ofSize: 12, weight: .regular), color: .secondaryLabelColor))
        }
        if store.logs.isEmpty {
            logStack.addArrangedSubview(UI.subtitle("No logs yet."))
        }
        stack.addArrangedSubview(logBox)
        logBox.widthAnchor.constraint(greaterThanOrEqualToConstant: 760).isActive = true
    }

    private func card(_ title: String, _ value: String, image: String, good: Bool) -> NSView {
        let (box, content) = UI.box(title: "")
        let row = UI.stack(.horizontal, spacing: 8)
        let icon = NSImageView(image: NSImage(systemSymbolName: image, accessibilityDescription: nil) ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        row.addArrangedSubview(icon)
        row.addArrangedSubview(UI.label(title, font: .systemFont(ofSize: 13), color: .secondaryLabelColor))
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = (good ? NSColor.systemGreen : NSColor.secondaryLabelColor).cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        row.addArrangedSubview(dot)
        content.addArrangedSubview(row)
        content.addArrangedSubview(UI.label(value, font: .boldSystemFont(ofSize: 18)))
        box.widthAnchor.constraint(equalToConstant: 240).isActive = true
        return box
    }

    @objc private func toggleCore() { Task { await store.toggleCore() } }
    @objc private func toggleProxy() { Task { await store.toggleSystemProxy() } }
    @objc private func refreshController() { Task { await store.refreshController() } }
    @objc private func runDiagnostics() { Task { await store.runDiagnostics() } }
}
