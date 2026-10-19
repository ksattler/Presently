import AppKit
import SwiftUI

/// Plain-text editor for speaker notes. Unlike SwiftUI's `TextEditor` it has its own undo
/// manager: edits must not reach the document's, or the read-only PDF document is marked as
/// edited and AppKit tries (and fails) to autosave it. Notes are saved to the pdfpc sidecar.
struct NotesTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = NSFont.systemFontSize + 1
    /// nil = system text color (follows the window's appearance).
    var textColor: NSColor? = nil
    /// Put the cursor into the editor when it appears (editing started by a button).
    var focusOnAppear = false
    /// Escape pressed in the editor; nil = AppKit's default handling.
    var onEscape: (() -> Void)? = nil

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesTextView
        let undoManager = UndoManager()

        init(_ parent: NotesTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)), let onEscape = parent.onEscape else { return false }
            onEscape()
            return true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        // scrollableTextView() always holds an NSTextView.
        // swiftlint:disable:next force_cast
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.allowsUndo = true
        tv.isRichText = false
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.string = text
        scroll.drawsBackground = false
        tv.drawsBackground = false
        applyStyle(to: tv)
        if focusOnAppear {
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        applyStyle(to: tv)
        guard tv.string != text else { return }
        tv.string = text
        // Another page's text: its undo history doesn't apply.
        context.coordinator.undoManager.removeAllActions()
    }

    private func applyStyle(to tv: NSTextView) {
        let font = NSFont.systemFont(ofSize: fontSize)
        let color = textColor ?? .textColor
        if tv.font != font { tv.font = font }
        if tv.textColor != color {
            tv.textColor = color
            tv.insertionPointColor = color
        }
        tv.typingAttributes[.font] = font
        tv.typingAttributes[.foregroundColor] = color
    }
}
