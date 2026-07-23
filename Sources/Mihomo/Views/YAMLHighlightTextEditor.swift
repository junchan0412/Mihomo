import AppKit
import SwiftUI

struct YAMLHighlightTextEditor: NSViewRepresentable {
    @Binding var text: String
    var showsLineNumbers: Bool = true
    var isEditable: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = LineNumberTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        if showsLineNumbers {
            scrollView.rulersVisible = true
            scrollView.hasVerticalRuler = true
            scrollView.verticalRulerView = LineNumberRulerView(textView: textView)
        }

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.setText(text)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? LineNumberTextView else { return }
        textView.isEditable = isEditable
        if textView.string != text {
            context.coordinator.setText(text)
        }
        scrollView.verticalRulerView?.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: YAMLHighlightTextEditor
        fileprivate weak var textView: LineNumberTextView?
        weak var scrollView: NSScrollView?
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
            scrollView?.verticalRulerView?.needsDisplay = true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            guard isApplyingHighlight == false else { return }
            highlight(textView)
            scrollView?.verticalRulerView?.needsDisplay = true
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

fileprivate final class LineNumberTextView: NSTextView {
    override func didChangeText() {
        super.didChangeText()
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }
}

fileprivate final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 42
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }

        let relativePoint = convert(NSPoint.zero, from: textView)
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        var lineNumber = lineNumber(for: glyphRange.location)

        var index = glyphRange.location
        while index < NSMaxRange(glyphRange) {
            var lineRange = NSRange()
            let rects = layoutManager.lineFragmentRect(forGlyphAt: index, effectiveRange: &lineRange)
            let y = relativePoint.y + rects.minY
            drawLineNumber("\(lineNumber)", at: y)
            index = NSMaxRange(lineRange)
            lineNumber += 1
        }

        if textView.string.isEmpty {
            drawLineNumber("1", at: relativePoint.y)
        }
    }

    private func lineNumber(for glyphIndex: Int) -> Int {
        guard let textView, let layoutManager = textView.layoutManager else { return 1 }
        let characterIndex = layoutManager.characterIndexForGlyph(at: max(glyphIndex, 0))
        let nsText = textView.string as NSString
        var number = 1
        nsText.enumerateSubstrings(in: NSRange(location: 0, length: min(characterIndex, nsText.length)), options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            number += 1
        }
        return max(number, 1)
    }

    private func drawLineNumber(_ value: String, at y: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let size = (value as NSString).size(withAttributes: attributes)
        let point = NSPoint(x: ruleThickness - size.width - 8, y: y + 1)
        (value as NSString).draw(at: point, withAttributes: attributes)
    }
}
