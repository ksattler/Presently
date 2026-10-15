import AppKit
import SwiftUI

/// Plain-text editor for speaker notes. Unlike SwiftUI's `TextEditor` it has its own undo
/// manager: edits must not reach the document's, or the read-only PDF document is marked as
/// edited and AppKit tries (and fails) to autosave it. Notes are saved to the pdfpc sidecar.
struct NotesTextView: NSViewRepresentable {
    @Binding var text: String

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesTextView
        let undoManager = UndoManager()

        init(_ parent: NotesTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.allowsUndo = true
        tv.isRichText = false
        tv.font = .systemFont(ofSize: NSFont.systemFontSize + 1)
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.string = text
        scroll.drawsBackground = false
        tv.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView, tv.string != text else { return }
        tv.string = text
        // Another page's text: its undo history doesn't apply.
        context.coordinator.undoManager.removeAllActions()
    }
}
