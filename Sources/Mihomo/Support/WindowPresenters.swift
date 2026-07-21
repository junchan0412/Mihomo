import AppKit
import SwiftUI

enum AppWindowIdentifier {
    static let main = NSUserInterfaceItemIdentifier("dev.codex.Mihomo.main-window")
    static let connections = NSUserInterfaceItemIdentifier("dev.codex.Mihomo.connections-window")
}

struct WindowIdentifierView: NSViewRepresentable {
    var identifier: NSUserInterfaceItemIdentifier

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        applyIdentifier(from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        applyIdentifier(from: view)
    }

    private func applyIdentifier(from view: NSView) {
        DispatchQueue.main.async {
            view.window?.identifier = identifier
        }
    }
}

enum MainWindowPresenter {
    @discardableResult
    static func presentExisting() -> Bool {
        guard let window = NSApp.windows.first(where: { $0.identifier == AppWindowIdentifier.main }) else {
            return false
        }
        NSApp.unhide(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    static func present(openWindow: OpenWindowAction) {
        if presentExisting() == false {
            openWindow(id: "main")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                _ = presentExisting()
            }
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
