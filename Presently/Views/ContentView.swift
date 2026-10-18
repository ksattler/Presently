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
        _session = StateObject(wrappedValue: PresentationSession(deck: deck, watchesFile: true, remembersPage: LastPageStore()))
    }

    var body: some View {
        Group {
            if session.isPresenting {
                PresenterView(session: session, deck: session.deck, stop: stopPresenting,
                              swapScreens: { controller.swapScreens() })
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
            start: startPresenting, stop: stopPresenting, swapScreens: { controller.swapScreens() }))
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
    /// The list's own selection, synced with the session via `onChange`: List writes its
    /// selection during view updates, and publishing session changes from there is not allowed.
    @State private var selection: Int?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(0..<deck.pageCount, id: \.self) { i in
                    VStack(spacing: 4) {
                        PageThumbnail(deck: deck, index: i, region: deck.notesLayout.slideRegion,
                                      pixelSize: CGSize(width: 360, height: 270))
                            .frame(height: 110)
                            .shadow(radius: 1)
                        HStack(spacing: 4) {
                            Text(deck.label(i)).monospacedDigit()
                            if !deck.note(for: i).isEmpty {
                                Image(systemName: "note.text").help("Has notes")
                            }
                            if deck.isHidden(i) {
                                Image(systemName: "eye.slash").help("Skipped in the presentation")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .opacity(deck.isHidden(i) ? 0.35 : deck.isBackup(i) ? 0.55 : 1)
                    .overlay(alignment: .bottom) {
                        if deck.endPage == i {
                            Text("End of Talk").font(.caption2.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Color.purple, in: Capsule())
                                .offset(y: 8)
                        }
                    }
                    .contextMenu {
                        if deck.endPage == i {
                            Button("Remove “End of Talk” Mark") { deck.endPage = nil }
                        } else {
                            Button("Talk Ends Here (Backup After)") { deck.endPage = i }
                        }
                        SkipSlideButton(deck: deck, index: i)
                    }
                    .tag(i)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
            .onAppear { selection = session.currentIndex }
            .onChange(of: selection) { if let selection { session.go(to: selection) } }
            .onChange(of: session.currentIndex) { selection = session.currentIndex }
        } detail: {
            VStack(spacing: 0) {
            NotesLayoutWarning(deck: deck)
            VSplitView {
                PDFPageView(page: deck.page(session.currentIndex), region: deck.notesLayout.slideRegion,
                            background: .windowBackgroundColor)
                    .padding(12)
                    .frame(minHeight: 200, maxHeight: .infinity)
                NotesEditor(deck: deck, index: session.currentIndex)
                    .frame(minHeight: 100, idealHeight: 170, maxHeight: 420)
            }
            }
        }
        .navigationSubtitle(session.reloadError ?? (deck.pageCount == 0 ? "" : String(localized: "Page \(session.currentIndex + 1) of \(deck.pageCount)")))
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    PresentationScreenMenu()
                } label: {
                    Label("Display", systemImage: "display.2")
                }
                .help("Display for the presentation")
                Button(action: startPresenting) {
                    Label("Present", systemImage: "play.fill")
                }
                .help("Start presentation (⌘⏎ or F5)")
                .disabled(deck.pageCount == 0)
            }
        }
        .alert("Error", isPresented: .constant(deck.saveError != nil)) {
            Button("OK") {}
        } message: {
            Text(deck.saveError ?? "")
        }
    }
}

/// Shown when a Beamer notes layout is active although the pages have an ordinary slide format
/// — the audience would see only half a slide.
struct NotesLayoutWarning: View {
    @ObservedObject var deck: SlideDeck

    var body: some View {
        if deck.notesLayoutLooksWrong {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Beamer notes “\(deck.notesLayout.title)” are active, but the pages have a normal slide format – only half a page is shown.")
                    .lineLimit(2)
                Spacer()
                Button("Show Whole Page") { deck.notesLayout = .none }
            }
            .font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.orange.opacity(0.15))
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
                Text("Notes").font(.headline)
                if deck.overlayGroup(of: index).count > 1 {
                    Text("applies to all overlays of slide \(deck.label(index))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if deck.fileURL == nil {
                    Text("Can’t be saved (no file)").font(.caption).foregroundStyle(.secondary)
                }
            }
            NotesTextView(text: Binding(get: { deck.editableNote(for: index) },
                                        set: { deck.setNote($0, for: index) }))
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if deck.editableNote(for: index).isEmpty {
                        Text("Notes for this slide (Markdown) …")
                            .foregroundStyle(.tertiary).padding(9).allowsHitTesting(false)
                    }
                }
            if let embedded = deck.embeddedNotes[index], !embedded.isEmpty {
                Text("In the PDF: \(embedded)")
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
