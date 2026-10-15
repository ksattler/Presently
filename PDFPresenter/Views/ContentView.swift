import PDFKit
import SwiftUI

/// Document window. Browse mode: page list, large preview and notes editor. While
/// presenting it shows the presenter view; the audience window shows the slide.
struct ContentView: View {
    @StateObject private var session: PresentationSession
    @State private var controller = PresentationController()
    @State private var window: NSWindow?

    init(file: PDFFile, fileURL: URL?) {
        let deck = SlideDeck(data: file.data, fileURL: fileURL) ?? SlideDeck(pdf: PDFDocument(), fileURL: nil)
        _session = StateObject(wrappedValue: PresentationSession(deck: deck, watchesFile: true))
    }

    var body: some View {
        Group {
            if session.isPresenting {
                PresenterView(session: session, deck: session.deck, stop: stopPresenting)
            } else {
                BrowseView(session: session, deck: session.deck, startPresenting: startPresenting)
            }
        }
        .background(WindowAccessor(window: $window))
        .onChange(of: window) {
            // Don't start with the cursor in the notes editor: arrow keys should turn pages.
            DispatchQueue.main.async { window?.makeFirstResponder(nil) }
        }
        .background(BrowseKeyHandler(session: session, window: window, startPresenting: startPresenting))
        .focusedSceneValue(\.presentationActions, PresentationActions(
            isPresenting: session.isPresenting, canPresent: session.deck.pageCount > 0,
            start: startPresenting, stop: stopPresenting))
        .focusedSceneObject(session.deck)
        .onDisappear {
            controller.stop()
            session.deck.saveNow()
        }
    }

    private func startPresenting() {
        guard session.deck.pageCount > 0 else { return }
        controller.start(session: session, presenterWindow: window)
    }

    private func stopPresenting() {
        controller.stop()
    }
}

/// Page list, large preview of the selected page and the notes editor.
private struct BrowseView: View {
    @ObservedObject var session: PresentationSession
    @ObservedObject var deck: SlideDeck
    let startPresenting: () -> Void

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { session.currentIndex }, set: { if let i = $0 { session.go(to: i) } })) {
                ForEach(0..<deck.pageCount, id: \.self) { i in
                    VStack(spacing: 4) {
                        PageThumbnail(deck: deck, index: i, region: deck.notesLayout.slideRegion,
                                      pixelSize: CGSize(width: 360, height: 270))
                            .frame(height: 110)
                            .shadow(radius: 1)
                        HStack(spacing: 4) {
                            Text(deck.label(i)).monospacedDigit()
                            if !deck.note(for: i).isEmpty {
                                Image(systemName: "note.text").help("Hat Notizen")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .tag(i)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } detail: {
            VSplitView {
                PDFPageView(page: deck.page(session.currentIndex), region: deck.notesLayout.slideRegion,
                            background: .windowBackgroundColor)
                    .padding(12)
                    .frame(minHeight: 200, maxHeight: .infinity)
                NotesEditor(deck: deck, index: session.currentIndex)
                    .frame(minHeight: 100, idealHeight: 170, maxHeight: 420)
            }
        }
        .navigationSubtitle(session.reloadError ?? (deck.pageCount == 0 ? "" : "Seite \(session.currentIndex + 1) von \(deck.pageCount)"))
        .toolbar {
            ToolbarItemGroup {
                Picker("Beamer-Notizen", selection: $deck.notesLayout) {
                    ForEach(NotesLayout.allCases) { Text($0.title).tag($0) }
                }
                .help("Notizen, die im PDF neben der Folie stehen (LaTeX Beamer)")
                Menu {
                    PresentationScreenMenu()
                } label: {
                    Label("Bildschirm", systemImage: "display.2")
                }
                .help("Bildschirm für die Präsentation")
                Button(action: startPresenting) {
                    Label("Präsentieren", systemImage: "play.fill")
                }
                .help("Präsentation starten (⌘⏎ oder F5)")
                .disabled(deck.pageCount == 0)
            }
        }
        .alert("Fehler", isPresented: .constant(deck.saveError != nil)) {
            Button("OK") {}
        } message: {
            Text(deck.saveError ?? "")
        }
    }
}

/// Edits the pdfpc note of a page. Embedded PDF notes (read-only) are shown below it.
private struct NotesEditor: View {
    @ObservedObject var deck: SlideDeck
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Notizen").font(.headline)
                if deck.overlayGroup(of: index).count > 1 {
                    Text("gilt für alle Overlays von Folie \(deck.label(index))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if deck.fileURL == nil {
                    Text("Nicht speicherbar (keine Datei)").font(.caption).foregroundStyle(.secondary)
                }
            }
            NotesTextView(text: Binding(get: { deck.editableNote(for: index) },
                                        set: { deck.setNote($0, for: index) }))
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if deck.editableNote(for: index).isEmpty {
                        Text("Notizen für diese Folie (Markdown) …")
                            .foregroundStyle(.tertiary).padding(9).allowsHitTesting(false)
                    }
                }
            if let embedded = deck.embeddedNotes[index], !embedded.isEmpty {
                Text("Im PDF: \(embedded)")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(3)
                    .help(embedded)
            }
        }
        .padding(12)
    }
}

/// Browse mode keys: arrows / Page Up / Page Down / Space move through pages; F5 (also sent by
/// clickers' start button) and ⌘⏎ start the presentation. Ignored while editing notes.
private struct BrowseKeyHandler: NSViewRepresentable {
    let session: PresentationSession
    let window: NSWindow?
    let startPresenting: () -> Void

    final class Coordinator {
        var monitor: Any?
        var session: PresentationSession?
        weak var window: NSWindow?
        var startPresenting: () -> Void = {}
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let c = context.coordinator
        c.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak c] event in
            guard let c, let session = c.session, !session.isPresenting,
                  let window = c.window, event.window === window,
                  !(window.firstResponder is NSText)
            else { return event }
            if event.keyCode == PresentKeyAction.KeyCode.f5 { c.startPresenting(); return nil }
            // The page list handles ↑/↓ itself when focused.
            if window.firstResponder is NSTableView,
               [PresentKeyAction.KeyCode.up, PresentKeyAction.KeyCode.down].contains(event.keyCode) { return event }
            guard let action = PresentKeyAction(keyCode: event.keyCode, characters: nil, modifiers: event.modifierFlags)
            else { return event }
            switch action {
            case .next, .previous, .first, .last, .nextSlide, .previousSlide:
                session.handle(action)
                return nil
            default:
                return event
            }
        }
        return NSView()
    }

    func updateNSView(_ v: NSView, context: Context) {
        context.coordinator.session = session
        context.coordinator.window = window
        context.coordinator.startPresenting = startPresenting
    }
}
