import AppKit
import SwiftUI

struct YAMLHighlightTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.setText(text)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text
        else { return }
        context.coordinator.setText(text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: YAMLHighlightTextEditor
        weak var textView: NSTextView?
        private var isApplyingHighlight = false

        init(_ parent: YAMLHighlightTextEditor) {
            self.parent = parent
        }

        func setText(_ text: String) {
            guard let textView else { return }
            isApplyingHighlight = true
            textView.string = text
            highlight(textView)
            isApplyingHighlight = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            guard isApplyingHighlight == false else { return }
            highlight(textView)
        }

        private func highlight(_ textView: NSTextView) {
            let selectedRanges = textView.selectedRanges
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            guard let storage = textView.textStorage else { return }

            isApplyingHighlight = true
            storage.beginEditing()
            storage.setAttributes(baseAttributes, range: fullRange)
            applyLineHighlights(in: storage, text: textView.string)
            storage.endEditing()
            textView.selectedRanges = selectedRanges
            isApplyingHighlight = false
        }

        private var baseAttributes: [NSAttributedString.Key: Any] {
            [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        }

        private func applyLineHighlights(in storage: NSTextStorage, text: String) {
            let nsText = text as NSString
            nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
                let line = nsText.substring(with: range)
                self.highlightLine(line, lineRange: range, storage: storage)
            }
        }

        private func highlightLine(_ line: String, lineRange: NSRange, storage: NSTextStorage) {
            let nsLine = line as NSString
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#") {
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: lineRange)
                return
            }

            if let commentRange = line.range(of: #"(^|\s)#.*$"#, options: .regularExpression) {
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: nsRange(commentRange, in: line, offset: lineRange.location))
            }

            if let keyRange = line.range(of: #"^\s*-?\s*("[^"]+"|'[^']+'|[A-Za-z0-9_.@/$-]+)\s*:"#,
                                         options: .regularExpression) {
                storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: nsRange(keyRange, in: line, offset: lineRange.location))
            }

            for pattern in [
                #"\b(true|false|null|yes|no|on|off)\b"#,
                #"(?<![A-Za-z0-9_.-])-?\d+(\.\d+)?\b"#,
                #"&[A-Za-z0-9_-]+|\*[A-Za-z0-9_-]+|<<:"#,
                #"https?://[^\s'"]+"#
            ] {
                apply(pattern: pattern, in: line, lineRange: lineRange, storage: storage)
            }

            if trimmed.hasPrefix("- ") {
                let dashRange = nsLine.range(of: "-")
                if dashRange.location != NSNotFound {
                    let markerRange = NSRange(location: lineRange.location + dashRange.location, length: 1)
                    storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: markerRange)
                }
            }
        }

        private func apply(pattern: String, in line: String, lineRange: NSRange, storage: NSTextStorage) {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
            let nsLine = line as NSString
            let color: NSColor
            if pattern.contains("http") {
                color = .systemBlue
            } else if pattern.contains("&") {
                color = .systemPink
            } else if pattern.contains("\\d") {
                color = .systemPurple
            } else {
                color = .systemGreen
            }

            expression.enumerateMatches(in: line, range: NSRange(location: 0, length: nsLine.length)) { match, _, _ in
                guard let match else { return }
                storage.addAttribute(
                    .foregroundColor,
                    value: color,
                    range: NSRange(location: lineRange.location + match.range.location, length: match.range.length)
                )
            }
        }

        private func nsRange(_ range: Range<String.Index>, in text: String, offset: Int) -> NSRange {
            let base = NSRange(range, in: text)
            return NSRange(location: offset + base.location, length: base.length)
        }
    }
}
