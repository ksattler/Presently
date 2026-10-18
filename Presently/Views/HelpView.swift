import SwiftUI

/// A topic of the help window: title, sidebar symbol and paragraphs in inline Markdown.
/// The keyboard topic lists `AboutPanel.shortcuts` instead of repeating them.
enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted, presenting, presenterView, timer, notes, beamer, drawing, keys

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: String(localized: "Getting Started")
        case .presenting:     String(localized: "Presenting")
        case .presenterView:  String(localized: "Presenter View")
        case .timer:          String(localized: "Timer and Schedule")
        case .notes:          String(localized: "Notes")
        case .beamer:         String(localized: "LaTeX Beamer")
        case .drawing:        String(localized: "Drawing")
        case .keys:           String(localized: "Keyboard Shortcuts")
        }
    }

    var symbol: String {
        switch self {
        case .gettingStarted: "hand.wave"
        case .presenting:     "play.rectangle"
        case .presenterView:  "rectangle.split.3x1"
        case .timer:          "hourglass"
        case .notes:          "note.text"
        case .beamer:         "doc.richtext"
        case .drawing:        "pencil.tip"
        case .keys:           "keyboard"
        }
    }

    var paragraphs: [String] {
        switch self {
        case .gettingStarted: [
            String(localized: "Presently presents PDF slides: the audience sees the slide full screen on one display, you see the presenter view with the current and next slide, notes and timer."),
            String(localized: "**Open a PDF** with ⌘O, by dragging it onto the Dock icon or via *File → Open Recent*. The document window shows the page list, a large preview and the notes of the selected page."),
            String(localized: "A PDF opens on the page where you left off. Presently never changes the PDF itself."),
            String(localized: "**Settings** (⌘,) gather the display, rehearsal, transition, timer and presenter layout options in one place."),
            String(localized: "**Clickers** work without setup: they send keys such as Page Up/Page Down, B or “.”, F5 and Esc, which Presently understands."),
        ]
        case .presenting: [
            String(localized: "**Start** with ⌘⏎, F5 or ▶︎ in the toolbar. **End** with ⌘⏎ or Esc – Esc first closes an open overview, input, drawing mode, black screen or freeze."),
            String(localized: "**Choose a display** in the toolbar or via *Presentation → Present On*. With several displays, *Automatic* picks the one the document window is not on. The choice is remembered."),
            String(localized: "**Rehearsal:** *Audience View in a Window (Rehearsal)* opens the audience view as a regular window – useful with a single display."),
            String(localized: "**Swap displays (S)** when the audience view ended up on the wrong display. The choice is remembered."),
            String(localized: "**Projector unplugged:** the presentation keeps running. The audience view is hidden (or moves to a free display) and comes back when the projector is reconnected."),
            String(localized: "**Transitions** from the PDF (e.g. from LaTeX Beamer) are played when advancing to the next page. Turn them off via *Presentation → Play Transitions from the PDF*."),
        ]
        case .presenterView: [
            String(localized: "While presenting, the document window shows the presenter view: current slide, next slide, upcoming pages, notes, elapsed time and clock."),
            String(localized: "**Layout:** drag the dividers between the areas. The *View* menu puts the current slide left or right, shows or hides the next slide and the notes, sets the number of upcoming pages and resets the layout. The layout applies to all documents."),
            String(localized: "**Go to a page:** click an upcoming page, open the overview (Tab or O), or type the slide number and press ⏎."),
            String(localized: "**Freeze (F):** the audience keeps the current slide while you browse, e.g. for questions. F or Esc shows your slide again."),
            String(localized: "**Black or white screen:** B or “.” / W or “,”. Press the key again to return."),
            String(localized: "**Laser pointer (L):** the mouse pointer over the current slide appears as a red dot for the audience."),
            String(localized: "**Zoom (M):** drag a rectangle on the current slide or on the audience view – or click for 2× – and the audience sees that part enlarged, sharp at any size. The presenter view dims the rest. M, Esc or the next page show the whole slide again."),
            String(localized: "**Links** in the PDF are clickable on the current slide and in the audience view. A click outside a link advances."),
        ]
        case .timer: [
            String(localized: "The timer shows the elapsed time. P pauses and resumes it, R resets it. By default it starts with the first page turn, so you can open the presentation early and wait on the title slide."),
            String(localized: "**Schedule** (hourglass icon): set the talk duration or an end time. Presently shows the remaining time and whether you are ahead of or behind schedule – slide progress compared to elapsed time; overlays don't count separately."),
            String(localized: "**End of talk:** right-click a page in the page list → *Talk Ends Here (Backup After)*. Later pages are backup: dimmed, not counted in the schedule, and End jumps to the end of the talk first."),
            String(localized: "**Skip slides:** right-click a page in the page list or the overview → *Skip Slide in Presentation* (all overlays of the slide). Paging passes over it, the preview and the schedule leave it out; a jump (number, overview, link) still shows it. Stored in the pdfpc file like pdfpc's own hidden slides."),
        ]
        case .notes: [
            String(localized: "Write notes for each slide in the document window or during the presentation (pencil icon or double-click on the notes; Esc ends editing). Notes support Markdown. While editing, a clicker's Page Up/Page Down still turn pages."),
            String(localized: "Notes are stored next to the PDF in pdfpc format (`talk.pdf` → `talk.pdfpc`), so pdfpc can use them too."),
            String(localized: "Text annotations in the PDF (comments, `pdfpcnote` from LaTeX) are shown as notes and hidden from the audience."),
            String(localized: "Beamer overlays (consecutive pages with the same label) share one note."),
        ]
        case .beamer: [
            String(localized: "**Notes on the second screen:** with `show notes on second screen=right` (or left, top, bottom) the audience sees only the slide half and the presenter view shows the notes half. Wide pages are detected automatically; change it via *Presentation → Beamer Notes*. If the setting doesn't match the page format, a notice offers *Show Whole Page*."),
            String(localized: "**Videos** from the PDF play inside the slide: LaTeX Beamer's `\\movie` (with autostart, loop, start, duration) and links like `run:clip.mp4?autostart&loop`. The video file lies next to the PDF. Click a video to play or pause it; the presenter view shows its progress."),
            String(localized: "**Overlays:** ⇧ with an arrow key skips them. They share one note and count as one slide in the schedule."),
            String(localized: "**Automatic reload:** when the PDF changes on disk – e.g. after compiling again – it is reloaded; the current page and the notes are kept. Half-written files are ignored."),
        ]
        case .drawing: [
            String(localized: "Draw on the current slide in the presenter view or directly on the audience view: pen (D), highlighter (H), eraser (E). Press the key again or Esc to stop drawing."),
            String(localized: "Pick a color with the color button. Z removes the slide's last stroke, X all strokes on the slide."),
            String(localized: "Drawings are kept per slide while the document is open, but they are not saved."),
        ]
        case .keys: [
            String(localized: "The keys work in the presenter view and in the audience view. A click on the audience view advances, a right-click goes back. ⌘, ⌥ and ⌃ combinations are left to the menus."),
        ]
        }
    }

    /// Key rows shown below the paragraphs.
    var shortcuts: [(keys: String, action: String)] {
        self == .keys ? AboutPanel.shortcuts : []
    }

    /// Search over title, text and key rows, ignoring case and diacritics. Empty matches all.
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let texts = [title] + paragraphs + shortcuts.flatMap { [$0.keys, $0.action] }
        return texts.contains { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// A paragraph as inline Markdown; plain text if it doesn't parse.
    static func attributed(_ paragraph: String) -> AttributedString {
        (try? AttributedString(markdown: paragraph,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(paragraph)
    }
}

/// Help window (menu Help → Presently Help): topics on the left, text on the right.
struct HelpView: View {
    static let windowID = "help"

    @State private var selection: HelpTopic? = .gettingStarted
    @State private var query = ""

    private var topics: [HelpTopic] { HelpTopic.allCases.filter { $0.matches(query) } }

    var body: some View {
        NavigationSplitView {
            List(topics, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.symbol).tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            if let selection, topics.contains(selection) {
                HelpTopicView(topic: selection)
            } else if topics.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                Color.clear
            }
        }
        .searchable(text: $query, placement: .sidebar)
        .onChange(of: query) {
            // Keep a matching topic selected while searching.
            if let selection, topics.contains(selection) { return }
            selection = topics.first
        }
    }
}

private struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(topic.title).font(.title.bold())
                ForEach(topic.paragraphs, id: \.self) { p in
                    Text(HelpTopic.attributed(p)).fixedSize(horizontal: false, vertical: true)
                }
                if !topic.shortcuts.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        ForEach(topic.shortcuts, id: \.keys) { row in
                            GridRow {
                                Text(row.keys).fontWeight(.semibold).gridColumnAlignment(.trailing)
                                Text(row.action).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: 620, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
