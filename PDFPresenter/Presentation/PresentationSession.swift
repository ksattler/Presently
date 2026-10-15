import Foundation
import PDFKit

/// Laser pointer position, separate from the session so 60 Hz mouse moves only re-render the
/// pointer overlays, not the whole presenter view.
@MainActor
final class LaserPointer: ObservableObject {
    @Published var isEnabled = false {
        didSet { if !isEnabled { position = nil } }
    }
    /// Position in the shown slide region, normalized to 0…1 (y down); nil = not over the slide.
    @Published var position: CGPoint?

    func move(to point: CGPoint?) {
        guard isEnabled else { return }
        let p = point.flatMap { (0...1).contains($0.x) && (0...1).contains($0.y) ? $0 : nil }
        if p != position { position = p }
    }
}

/// Navigation and presenter state of one document window: current page, black/white screen,
/// typed page number, overview, timer. Shared by the browse view, the presenter view and the
/// audience window, so they always show the same page.
@MainActor
final class PresentationSession: ObservableObject {
    enum Blank: Equatable { case black, white }

    let deck: SlideDeck

    @Published var currentIndex = 0
    @Published private(set) var isPresenting = false
    @Published var blank: Blank?
    @Published var showsOverview = false
    /// Digits typed so far for "go to page"; Return jumps, Escape clears.
    @Published private(set) var pageInput = ""
    @Published private(set) var timer = PresentationTimer()
    /// Page the audience keeps seeing while frozen; nil = follows `currentIndex`.
    @Published private(set) var frozenIndex: Int?
    /// Set when reloading the PDF from disk failed (file unreadable or not a PDF).
    @Published private(set) var reloadError: String?

    let pointer = LaserPointer()
    private var watcher: FileWatcher?

    /// Page shown in the audience window.
    var audienceIndex: Int { frozenIndex ?? currentIndex }

    var now: () -> Date = Date.init

    init(deck: SlideDeck, watchesFile: Bool = false) {
        self.deck = deck
        if watchesFile, let url = deck.fileURL {
            watcher = FileWatcher(url: url) { [weak self] in self?.reloadFromDisk() }
        }
    }

    // MARK: Reload

    /// Re-reads the PDF (e.g. recompiled with LaTeX) and stays on the same page. A file that
    /// is mid-write or broken is ignored — the next change event tries again.
    func reloadFromDisk() {
        guard let url = deck.fileURL else { return }
        guard let data = try? Data(contentsOf: url), let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
            reloadError = "„\(url.lastPathComponent)“ konnte nicht neu geladen werden."
            return
        }
        reloadError = nil
        deck.reload(pdf: pdf)
        go(to: currentIndex)
        if let frozenIndex { self.frozenIndex = min(frozenIndex, deck.pageCount - 1) }
    }

    // MARK: Lifecycle

    func begin() {
        isPresenting = true
        blank = nil
        showsOverview = false
        pageInput = ""
        frozenIndex = nil
        timer = PresentationTimer()
        timer.start(at: now())
    }

    func end() {
        isPresenting = false
        blank = nil
        showsOverview = false
        pageInput = ""
        frozenIndex = nil
        pointer.isEnabled = false
        timer.pause(at: now())
    }

    // MARK: Navigation

    var isAtEnd: Bool { currentIndex >= deck.pageCount - 1 }

    func go(to index: Int) {
        guard deck.pageCount > 0 else { return }
        currentIndex = min(max(index, 0), deck.pageCount - 1)
    }

    func next() { go(to: currentIndex + 1) }
    func previous() { go(to: currentIndex - 1) }

    func nextSlide() {
        if let i = deck.nextSlideStart(after: currentIndex) { go(to: i) } else { go(to: deck.pageCount - 1) }
    }

    /// Start of the previous slide; from inside a slide's overlays, its own first overlay.
    func previousSlide() {
        let group = deck.overlayGroup(of: currentIndex)
        go(to: currentIndex > group.lowerBound ? group.lowerBound
                                               : deck.overlayGroup(of: group.lowerBound - 1).lowerBound)
    }

    /// Page for typed input: a page label matches first (so "12" finds slide 12 even with
    /// overlays, landing on its first overlay), else the page number.
    func index(forInput input: String) -> Int? {
        if let i = deck.labels.firstIndex(of: input) { return i }
        if let n = Int(input), (1...deck.pageCount).contains(n) { return n - 1 }
        return nil
    }

    // MARK: Keys

    /// Returns false if the action isn't meaningful right now (event passes through).
    @discardableResult
    func handle(_ action: PresentKeyAction) -> Bool {
        // Any navigation shows the slides again.
        switch action {
        case .next, .previous, .first, .last, .nextSlide, .previousSlide: blank = nil
        default: break
        }
        if case .digit = action {} else if action != .confirm, action != .exit { pageInput = "" }

        switch action {
        case .next:          next()
        case .previous:      previous()
        case .nextSlide:     nextSlide()
        case .previousSlide: previousSlide()
        case .first:         go(to: 0)
        case .last:          go(to: deck.pageCount - 1)
        case .black:         blank = blank == .black ? nil : .black
        case .white:         blank = blank == .white ? nil : .white
        case .digit(let d):  if pageInput.count < 4 { pageInput += String(d) }
        case .confirm:
            if pageInput.isEmpty {
                if showsOverview { showsOverview = false } else { blank = nil; next() }
            } else {
                if let i = index(forInput: pageInput) { go(to: i); blank = nil }
                pageInput = ""
                showsOverview = false
            }
        case .toggleOverview: showsOverview.toggle()
        case .toggleFreeze:   frozenIndex = frozenIndex == nil ? currentIndex : nil
        case .togglePointer:  pointer.isEnabled.toggle()
        case .toggleTimer:    timer.toggle(at: now())
        case .resetTimer:     timer.reset(at: now())
        case .ignore:         break
        case .exit:
            if !pageInput.isEmpty { pageInput = "" }
            else if showsOverview { showsOverview = false }
            else if blank != nil { blank = nil }
            else if frozenIndex != nil { frozenIndex = nil }
            else { return false }   // caller ends the presentation
        }
        return true
    }
}
