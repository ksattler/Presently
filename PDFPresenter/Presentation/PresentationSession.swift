import Foundation

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

    var now: () -> Date = Date.init

    init(deck: SlideDeck) {
        self.deck = deck
    }

    // MARK: Lifecycle

    func begin() {
        isPresenting = true
        blank = nil
        showsOverview = false
        pageInput = ""
        timer = PresentationTimer()
        timer.start(at: now())
    }

    func end() {
        isPresenting = false
        blank = nil
        showsOverview = false
        pageInput = ""
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
        case .toggleTimer:    timer.toggle(at: now())
        case .resetTimer:     timer.reset(at: now())
        case .ignore:         break
        case .exit:
            if !pageInput.isEmpty { pageInput = "" }
            else if showsOverview { showsOverview = false }
            else if blank != nil { blank = nil }
            else { return false }   // caller ends the presentation
        }
        return true
    }
}
