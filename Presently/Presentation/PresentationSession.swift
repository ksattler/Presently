import AppKit
import PDFKit

/// Laser pointer position, separate from the session so 60 Hz mouse moves only re-render the
/// pointer overlays, not the whole presenter view.
@MainActor
final class LaserPointer: ObservableObject {
    /// A red dot, or a spotlight: the slide dimmed except a circle around the pointer.
    enum Style { case dot, spotlight }

    @Published var isEnabled = false {
        didSet { if !isEnabled { position = nil } }
    }
    @Published var style = Style.dot
    /// UserDefaults: spotlight radius as a fraction of the slide width.
    static let spotlightRadiusKey = "spotlightRadius"
    static let defaultSpotlightRadius = 0.12
    static let spotlightRadiusRange: ClosedRange<Double> = 0.05...0.3

    /// L / C: switches to `style`, or off if that style is already on.
    func toggle(_ style: Style) {
        if isEnabled, self.style == style {
            isEnabled = false
        } else {
            self.style = style
            isEnabled = true
        }
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

    @Published var currentIndex = 0 {
        didSet {
            guard currentIndex != oldValue else { return }
            if isPresenting, timerWaitsForFirstTurn {
                timerWaitsForFirstTurn = false
                timer.start(at: now())
            }
            if let url = deck.fileURL { lastPages?.set(currentIndex, for: url) }
            audiencePageChanged()
        }
    }
    @Published private(set) var isPresenting = false
    @Published var blank: Blank?
    @Published var showsOverview = false
    /// Digits typed so far for "go to page"; Return jumps, Escape clears.
    @Published private(set) var pageInput = ""
    @Published private(set) var timer = PresentationTimer()
    /// The timer starts with the first page turn instead of with the presentation (pdfpc's
    /// behavior: you can open the presentation early and wait on the title slide).
    @Published private(set) var timerWaitsForFirstTurn = false
    /// Time per slide of the current (or last) presentation; reset with the timer.
    @Published private(set) var slideTimes = SlideTimes()
    static let timerStartsOnFirstTurnKey = "timerStartsOnFirstTurn"
    /// Page the audience keeps seeing while frozen; nil = follows `currentIndex`.
    @Published private(set) var frozenIndex: Int? {
        didSet { if frozenIndex != oldValue { audiencePageChanged() } }
    }
    /// The audience display is disconnected; the audience view is hidden until it's back.
    @Published var audienceDisconnected = false
    /// Set when reloading the PDF from disk failed (file unreadable or not a PDF).
    @Published private(set) var reloadError: String?

    let pointer = LaserPointer()
    let drawings = Drawings()
    let media = MediaPlayback()
    /// Part of the audience slide shown enlarged (`SlideZoom`); nil = the whole slide.
    @Published private(set) var zoom: CGRect?
    private var zoomPage: Int?
    /// The next drag (or click) on the presenter's current slide selects the zoom.
    @Published private(set) var isSelectingZoom = false
    var audienceZoom: CGRect { zoom ?? PageRenderer.unzoomed }
    /// Deck revision the loaded clips belong to (a reload re-reads them).
    private var mediaRevision = -1
    /// Opens external links (browser); replaceable in tests.
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Pages left by following internal links, for the PDF's "GoBack" action.
    private(set) var linkHistory: [Int] = []
    private var watcher: FileWatcher?

    /// Page shown in the audience window.
    var audienceIndex: Int { frozenIndex ?? currentIndex }

    var now: () -> Date = Date.init
    var defaults: UserDefaults = .standard
    /// nil = don't remember the page (tests, windows without a file).
    private let lastPages: LastPageStore?

    var timerStartsOnFirstTurn: Bool {
        get { defaults.object(forKey: Self.timerStartsOnFirstTurnKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.timerStartsOnFirstTurnKey); objectWillChange.send() }
    }

    /// `remembersPage`: open at the page shown last time and keep remembering it.
    init(deck: SlideDeck, watchesFile: Bool = false, remembersPage: LastPageStore? = nil) {
        self.deck = deck
        lastPages = remembersPage
        if let store = remembersPage, let url = deck.fileURL, let page = store.page(for: url), page < deck.pageCount {
            currentIndex = page
        }
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
            reloadError = String(localized: "“\(url.lastPathComponent)” could not be reloaded.")
            return
        }
        reloadError = nil
        deck.reload(pdf: pdf, data: data)
        go(to: currentIndex)
        if let frozenIndex { self.frozenIndex = min(frozenIndex, deck.pageCount - 1) }
        audiencePageChanged()
    }

    // MARK: Lifecycle

    func begin() {
        isPresenting = true
        linkHistory = []
        blank = nil
        showsOverview = false
        pageInput = ""
        frozenIndex = nil
        timer = PresentationTimer()
        slideTimes = SlideTimes()
        timerWaitsForFirstTurn = timerStartsOnFirstTurn
        if !timerWaitsForFirstTurn { timer.start(at: now()) }
        audiencePageChanged()
    }

    func end() {
        isPresenting = false
        blank = nil
        showsOverview = false
        pageInput = ""
        frozenIndex = nil
        timerWaitsForFirstTurn = false
        audienceDisconnected = false
        pointer.isEnabled = false
        drawings.end()
        drawings.tool = nil   // the strokes stay
        timer.pause(at: now())
        audiencePageChanged()
    }

    /// The audience page may have changed (page turn, freeze, reload, begin/end): a zoom ends
    /// with its page; the videos of the new page are loaded while presenting, stopped otherwise.
    /// A new page (or a reload) stops what was playing.
    private func audiencePageChanged() {
        slideTimes.enter(isPresenting ? slide(of: audienceIndex) : nil, elapsed: timer.elapsed(at: now()))
        if zoom != nil, !isPresenting || zoomPage != audienceIndex { zoom = nil }
        if !isPresenting { isSelectingZoom = false }
        let index = isPresenting ? audienceIndex : nil
        guard index != media.pageIndex || deck.revision != mediaRevision else { return }
        mediaRevision = deck.revision
        let clips = index.flatMap { deck.page($0) }.map {
            PageMedia.clips(on: $0, baseURL: deck.fileURL?.deletingLastPathComponent())
        } ?? []
        media.load(clips, page: index)
    }

    /// Key of a page's slide in `slideTimes`: the first page of its overlay group.
    func slide(of index: Int) -> Int { deck.overlayGroup(of: index).lowerBound }

    // MARK: Navigation

    var isAtEnd: Bool { currentIndex >= deck.pageCount - 1 }

    func go(to index: Int) {
        guard deck.pageCount > 0 else { return }
        // Assigning an equal value still publishes; the page list writes its selection back
        // during view updates, which SwiftUI flags as "publishing changes from within view updates".
        let index = min(max(index, 0), deck.pageCount - 1)
        if index != currentIndex { currentIndex = index }
    }

    /// Paging skips pages marked as skipped (`deck.hiddenPages`); jumps don't.
    func next() {
        if let i = deck.nextShown(after: currentIndex) { go(to: i) }
    }

    func previous() {
        if let i = deck.previousShown(before: currentIndex) { go(to: i) }
    }

    /// Start of the next slide; on the last slide, its last shown overlay.
    func nextSlide() {
        if let i = deck.nextSlideStart(after: currentIndex) {
            go(to: i)
        } else if let last = (currentIndex..<deck.pageCount).last(where: { !deck.isHidden($0) }) {
            go(to: last)
        }
    }

    /// Start of the previous slide; from inside a slide's overlays, its own first overlay.
    func previousSlide() {
        if let i = deck.previousSlideStart(before: currentIndex) { go(to: i) }
    }

    /// Page for typed input: a page label matches first (so "12" finds slide 12 even with
    /// overlays, landing on its first overlay), else the page number.
    func index(forInput input: String) -> Int? {
        if let i = deck.labels.firstIndex(of: input) { return i }
        if let n = Int(input), (1...deck.pageCount).contains(n) { return n - 1 }
        return nil
    }

    // MARK: Links

    /// Follows the link under a point of a shown page (normalized to the slide region, y down).
    /// `unfreeze`: the click came from the audience view, which should then show the result.
    /// Returns false if there is no link there.
    @discardableResult
    /// Click on a shown slide: a video there plays or pauses, otherwise a link is followed.
    /// False if there is neither (the audience view then advances).
    func click(atNormalized point: CGPoint, pageIndex: Int, unfreeze: Bool = false) -> Bool {
        if pageIndex == media.pageIndex, (0...1).contains(point.x), (0...1).contains(point.y),
           let page = deck.page(pageIndex),
           let id = media.clip(atPagePoint: PDFLinks.pagePoint(forNormalized: point, page: page,
                                                               region: deck.notesLayout.slideRegion)) {
            media.toggle(id)
            return true
        }
        return followLink(atNormalized: point, pageIndex: pageIndex, unfreeze: unfreeze)
    }

    func followLink(atNormalized point: CGPoint, pageIndex: Int, unfreeze: Bool = false) -> Bool {
        guard let page = deck.page(pageIndex),
              let target = PDFLinks.target(atNormalized: point, page: page, region: deck.notesLayout.slideRegion)
        else { return false }
        let followed = follow(target)
        if followed, unfreeze { frozenIndex = nil }
        return followed
    }

    @discardableResult
    func follow(_ target: LinkTarget) -> Bool {
        switch target {
        case .page(let index):
            linkHistory.append(currentIndex)
            blank = nil
            go(to: index)
        case .url(let url):
            openURL(url)
        case .named(let name):
            switch name {
            case .nextPage:     next()
            case .previousPage: previous()
            case .firstPage:    go(to: 0)
            case .lastPage:     go(to: deck.pageCount - 1)
            case .goBack:
                guard let back = linkHistory.popLast() else { return false }
                go(to: back)
            default: return false
            }
        }
        return true
    }

    /// Toggles a drawing tool; drawing and the laser pointer exclude each other.
    func selectTool(_ tool: Drawings.Tool) {
        drawings.end()
        drawings.tool = drawings.tool == tool ? nil : tool
        if drawings.tool != nil { pointer.isEnabled = false; isSelectingZoom = false }
    }

    /// M: start selecting a zoom; while zoomed (or selecting) back to the whole slide.
    func toggleZoom() {
        if zoom != nil || isSelectingZoom {
            zoom = nil
            isSelectingZoom = false
        } else {
            drawings.end()
            drawings.tool = nil
            pointer.isEnabled = false
            isSelectingZoom = true
        }
    }

    /// Zooms the audience view to a drag on the current slide (normalized points), or 2× around
    /// a clicked point. Only while the audience shows the current page.
    func zoom(from a: CGPoint, to b: CGPoint) {
        isSelectingZoom = false
        guard audienceIndex == currentIndex else { return }
        zoom = SlideZoom.rect(from: a, to: b)
        zoomPage = currentIndex
    }

    // MARK: Keys

    /// Returns false if the action isn't meaningful right now (event passes through).
    @discardableResult
    // Esc's chain of "close the topmost thing" counts as complex.
    // swiftlint:disable:next cyclomatic_complexity
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
        case .last:
            // End of the talk first (backup slides follow), then the last page.
            if let end = deck.endPage, currentIndex < end { go(to: end) } else { go(to: deck.pageCount - 1) }
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
        case .swapScreens:    break   // done by the PresentationController
        case .toggleFreeze:   frozenIndex = frozenIndex == nil ? currentIndex : nil
        case .togglePointer, .toggleSpotlight:
            pointer.toggle(action == .toggleSpotlight ? .spotlight : .dot)
            if pointer.isEnabled { drawings.tool = nil; isSelectingZoom = false }
        case .toggleZoom:     toggleZoom()
        case .pen:            selectTool(.pen)
        case .highlighter:    selectTool(.highlighter)
        case .eraser:         selectTool(.eraser)
        case .undoDrawing:    drawings.undo(page: currentIndex)
        case .clearDrawing:   drawings.clear(page: currentIndex)
        case .toggleTimer:    timerWaitsForFirstTurn = false; timer.toggle(at: now())
        case .resetTimer:
            timer.reset(at: now())
            slideTimes = SlideTimes()
            slideTimes.enter(slide(of: audienceIndex), elapsed: 0)
        case .ignore:         break
        case .exit:
            if !pageInput.isEmpty { pageInput = "" }
            else if showsOverview { showsOverview = false }
            else if drawings.tool != nil { drawings.end(); drawings.tool = nil }
            else if isSelectingZoom || zoom != nil { isSelectingZoom = false; zoom = nil }
            else if blank != nil { blank = nil }
            else if frozenIndex != nil { frozenIndex = nil }
            else { return false }   // caller ends the presentation
        }
        return true
    }
}
