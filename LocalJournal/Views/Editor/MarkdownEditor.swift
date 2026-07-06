import SwiftUI
import AppKit

/// Controls the writing surface from the outside: the formatting toolbar calls
/// these methods, which mutate the underlying `NSTextView` (selection-aware) and
/// register undo. The editor text is **Markdown source**, so every operation
/// inserts real Markdown that maps 1:1 to the mirrored `.md` file.
@MainActor
final class MarkdownEditingController {
    weak var textView: NSTextView?

    /// Wrap the current selection in a symmetric marker, e.g. `**` for bold. With
    /// no selection the markers are inserted and the cursor placed between them.
    func wrap(_ marker: String) { wrap(prefix: marker, suffix: marker) }

    func wrap(prefix: String, suffix: String) {
        guard let textView else { return }
        let full = textView.string as NSString
        let range = textView.selectedRange()
        let selected = full.substring(with: range)

        let replacement = prefix + selected + suffix
        let innerStart = (prefix as NSString).length
        replace(range, with: replacement,
                reselect: innerStart..<(innerStart + (selected as NSString).length))
    }

    /// Prefix every line touched by the selection (or the current line) with a
    /// generated marker — used for bullet / numbered lists and blockquotes.
    func prefixLines(_ makePrefix: @escaping (_ lineNumber: Int) -> String) {
        guard let textView else { return }
        let full = textView.string as NSString
        let lineRange = full.lineRange(for: textView.selectedRange())
        let block = full.substring(with: lineRange)

        let hadTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hadTrailingNewline { lines.removeLast() }
        if lines.isEmpty { lines = [""] }

        var number = 0
        let transformed = lines.map { line -> String in
            number += 1
            return makePrefix(number) + line
        }.joined(separator: "\n") + (hadTrailingNewline ? "\n" : "")

        replace(lineRange, with: transformed,
                reselect: 0..<(transformed as NSString).length, relativeTo: lineRange.location)
    }

    func bulletList() { prefixLines { _ in "- " } }
    func numberedList() { prefixLines { i in "\(i). " } }
    func blockquote() { prefixLines { _ in "> " } }
    func heading() { prefixLines { _ in "## " } }

    /// Give keyboard focus back to the writing surface.
    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    // MARK: - Editing primitive

    /// Replace `range` with `text`, registering undo, notifying the binding, and
    /// restoring a sensible selection. `reselect` is relative to the replacement
    /// (or to `base` when provided).
    private func replace(_ range: NSRange, with text: String,
                         reselect: Range<Int>, relativeTo base: Int? = nil) {
        guard let textView, let storage = textView.textStorage else { return }
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        storage.replaceCharacters(in: range, with: text)
        textView.didChangeText()   // fires the delegate → updates the SwiftUI binding

        let origin = base ?? range.location
        let newRange = NSRange(location: origin + reselect.lowerBound,
                               length: reselect.count)
        textView.setSelectedRange(newRange)
        focus()
    }
}

/// The main writing surface: a plain-text `NSTextView` whose content is Markdown
/// source. Wrapped for SwiftUI so it composes with the rest of the editor while
/// giving us selection-aware formatting the SwiftUI `TextEditor` can't on
/// macOS 14. The placeholder is drawn by the parent (`text.isEmpty`).
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var controller: MarkdownEditingController
    var fontSize: CGFloat = 15

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true

        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 6, height: 10)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.string = text
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.labelColor
        ]
        controller.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        controller.textView = textView
        // Only push external changes (template/prompt insertion, reset) — never
        // echo the user's own keystrokes back (which would fight the cursor).
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
