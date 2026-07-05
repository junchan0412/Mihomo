import AppKit

@MainActor
final class SettingsViewController: StackPageViewController {
    private let mihomoPath = NSTextField()
    private let controllerHost = NSTextField()
    private let controllerPort = NSTextField()
    private let mixedPort = NSTextField()
    private let socksPort = NSTextField()
    private let allowLAN = NSButton(checkboxWithTitle: "Allow LAN access", target: nil, action: nil)
    private let tunEnabled = NSButton(checkboxWithTitle: "Generate TUN configuration", target: nil, action: nil)
    private let autoStart = NSButton(checkboxWithTitle: "Start core when app launches", target: nil, action: nil)
    private let closeConnections = NSButton(checkboxWithTitle: "Close connections after policy switch", target: nil, action: nil)
    private let logLevel = NSPopUpButton()

    override func build(in stack: NSStackView) {
        addHeader("Settings", subtitle: "Core path, controller port, network takeover, and runtime options.", to: stack)
        fillFields()

        let (coreBox, core) = UI.box(title: "Core")
        core.addArrangedSubview(row("mihomo path", mihomoPath, button: UI.button("Choose...", target: self, action: #selector(chooseBinary))))
        logLevel.removeAllItems()
        logLevel.addItems(withTitles: ["info", "warning", "error", "debug"])
        logLevel.selectItem(withTitle: store.settings.logLevel)
        core.addArrangedSubview(row("log level", logLevel))
        core.addArrangedSubview(autoStart)
        stack.addArrangedSubview(coreBox)

        let (controllerBox, controller) = UI.box(title: "Controller")
        controller.addArrangedSubview(row("host", controllerHost))
        controller.addArrangedSubview(row("controller port", controllerPort))
        controller.addArrangedSubview(row("mixed port", mixedPort))
        controller.addArrangedSubview(row("socks port", socksPort))
        controller.addArrangedSubview(allowLAN)
        stack.addArrangedSubview(controllerBox)

        let (networkBox, network) = UI.box(title: "Network Takeover")
        network.addArrangedSubview(tunEnabled)
        network.addArrangedSubview(closeConnections)
        stack.addArrangedSubview(networkBox)

        stack.addArrangedSubview(UI.button("Save Settings", target: self, action: #selector(save)))
        for box in [coreBox, controllerBox, networkBox] {
            box.widthAnchor.constraint(greaterThanOrEqualToConstant: 760).isActive = true
        }
    }

    private func fillFields() {
        mihomoPath.stringValue = store.settings.mihomoPath
        controllerHost.stringValue = store.settings.controllerHost
        controllerPort.stringValue = "\(store.settings.controllerPort)"
        mixedPort.stringValue = "\(store.settings.mixedPort)"
        socksPort.stringValue = "\(store.settings.socksPort)"
        allowLAN.state = store.settings.allowLAN ? .on : .off
        tunEnabled.state = store.settings.tunEnabled ? .on : .off
        autoStart.state = store.settings.autoStartCore ? .on : .off
        closeConnections.state = store.settings.closeConnectionsOnPolicyChange ? .on : .off
    }

    private func row(_ title: String, _ control: NSView, button: NSButton? = nil) -> NSView {
        let row = UI.stack(.horizontal, spacing: 8)
        let label = UI.label(title, color: .secondaryLabelColor)
        label.widthAnchor.constraint(equalToConstant: 130).isActive = true
        row.addArrangedSubview(label)
        control.widthAnchor.constraint(equalToConstant: 420).isActive = true
        row.addArrangedSubview(control)
        if let button { row.addArrangedSubview(button) }
        return row
    }

    @objc private func chooseBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            mihomoPath.stringValue = url.path
        }
    }

    @objc private func save() {
        var settings = store.settings
        settings.mihomoPath = mihomoPath.stringValue
        settings.controllerHost = controllerHost.stringValue.isEmpty ? "127.0.0.1" : controllerHost.stringValue
        settings.controllerPort = Int(controllerPort.stringValue) ?? settings.controllerPort
        settings.mixedPort = Int(mixedPort.stringValue) ?? settings.mixedPort
        settings.socksPort = Int(socksPort.stringValue) ?? settings.socksPort
        settings.allowLAN = allowLAN.state == .on
        settings.tunEnabled = tunEnabled.state == .on
        settings.autoStartCore = autoStart.state == .on
        settings.closeConnectionsOnPolicyChange = closeConnections.state == .on
        settings.logLevel = logLevel.titleOfSelectedItem ?? "info"
        Task { await store.saveSettings(settings) }
    }
}
