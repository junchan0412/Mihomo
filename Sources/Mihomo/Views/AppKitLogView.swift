import AppKit
import SwiftUI

struct AppKitLogView: NSViewRepresentable {
    var entries: [LogEntry]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        Self.configure(textView)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.setAccessibilityLabel("应用日志")
        scrollView.setAccessibilityHelp("可选择和复制的实时日志。")
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard context.coordinator.lastEntries != entries else { return }

        let nextText = renderedText
        context.coordinator.lastEntries = entries
        guard context.coordinator.lastRenderedText != nextText else { return }

        textView.string = nextText
        context.coordinator.lastRenderedText = nextText
        let end = NSRange(location: textView.string.utf16.count, length: 0)
        textView.scrollRangeToVisible(end)
    }

    private var renderedText: String {
        entries.map { entry in
            let timestamp = Formatters.logTime.string(from: entry.date)
            return "\(timestamp) [\(entry.level.uppercased())] \(entry.message)"
        }
        .joined(separator: "\n")
    }

    static func configure(_ textView: NSTextView) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.setAccessibilityRole(.textArea)
        textView.setAccessibilityLabel("应用日志")
        textView.setAccessibilityHelp("只读日志文本，可使用标准键盘快捷键选择和复制。")
    }

    final class Coordinator {
        var lastEntries: [LogEntry] = []
        var lastRenderedText = ""
    }
}
