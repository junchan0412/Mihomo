import AppKit

@MainActor
final class DiagnosticsViewController: StackPageViewController {
    override func build(in stack: NSStackView) {
        addHeader("Diagnostics", subtitle: "Check binary, runtime config, network services, and controller reachability.", to: stack)
        stack.addArrangedSubview(UI.button("Run Diagnostics", target: self, action: #selector(runDiagnostics)))

        if store.diagnostics.isEmpty {
            stack.addArrangedSubview(UI.subtitle("No diagnostics yet."))
            return
        }

        for item in store.diagnostics {
            let (box, content) = UI.box(title: item.title)
            let line = UI.stack(.horizontal, spacing: 8)
            let icon = NSImageView(image: NSImage(systemSymbolName: symbol(for: item.state), accessibilityDescription: nil) ?? NSImage())
            icon.contentTintColor = color(for: item.state)
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
            line.addArrangedSubview(icon)
            line.addArrangedSubview(UI.label(item.detail, color: .secondaryLabelColor))
            content.addArrangedSubview(line)
            stack.addArrangedSubview(box)
            box.widthAnchor.constraint(greaterThanOrEqualToConstant: 760).isActive = true
        }
    }

    private func symbol(for state: DiagnosticState) -> String {
        switch state {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private func color(for state: DiagnosticState) -> NSColor {
        switch state {
        case .ok: return .systemGreen
        case .warning: return .systemOrange
        case .failed: return .systemRed
        }
    }

    @objc private func runDiagnostics() { Task { await store.runDiagnostics() } }
}
