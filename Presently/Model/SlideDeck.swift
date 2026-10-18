import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// The opened PDF. Read-only: the app never writes the PDF itself.
struct PDFFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, PDFDocument(data: data) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }
}

/// A PDF prepared for presenting: pages, labels, notes layout and speaker notes.
///
/// Notes come from two sources:
/// - the pdfpc sidecar (`PdfpcFile`) next to the PDF — editable, saved automatically;
/// - text annotations ("sticky notes", `\pdfpcnote`) in the PDF — read-only. Their icons are
///   hidden so the audience doesn't see them.
/// The sidecar wins. Beamer overlays (consecutive pages with the same label) share a note.
@MainActor
final class SlideDeck: ObservableObject {
    let fileURL: URL?
    // Replaced together by `reload(pdf:)` when the file changes on disk.
    @Published private(set) var pdf: PDFDocument
    @Published private(set) var pageCount: Int
    @Published private(set) var labels: [String]
    @Published private(set) var embeddedNotes: [Int: String]
    /// Page index → transition when moving onto that page (`/Trans`).
    @Published private(set) var transitions: [Int: PageTransition]
    /// For pages without their own: pdfpc's `defaultTransition` from the sidecar (Typst slides).
    let defaultTransition: PageTransition?
    /// Notes are Markdown unless the sidecar says otherwise (pdfpc's `disableMarkdown`).
    let notesAreMarkdown: Bool
    /// Counts reloads; views that cache per page (thumbnails) key on it.
    @Published private(set) var revision = 0

    @Published var notesLayout: NotesLayout
    @Published private(set) var notes: [Int: String]
    @Published var talkLimit: TalkLimit {
        didSet { if talkLimit != oldValue { scheduleSave() } }
    }
    /// Last page of the talk; later pages are backup. nil = all pages.
    @Published var endPage: Int? {
        didSet { if endPage != oldValue { scheduleSave() } }
    }
    /// Pages skipped when paging through the presentation (still reachable by jumps).
    @Published private(set) var hiddenPages: Set<Int> {
        didSet { if hiddenPages != oldValue { scheduleSave() } }
    }
    @Published private(set) var saveError: String?

    private var sidecar: PdfpcFile
    private var saveTask: Task<Void, Never>?
    private let thumbnails = NSCache<NSString, NSImage>()
    private var renderer: ThumbnailRenderer

    /// `data`: the PDF's bytes for the background thumbnail renderer; taken from `pdf` if nil.
    init(pdf: PDFDocument, fileURL: URL?, data: Data? = nil) {
        renderer = ThumbnailRenderer(data: data ?? pdf.dataRepresentation())
        self.pdf = pdf
        self.fileURL = fileURL
        pageCount = pdf.pageCount
        let pageLabels = Self.labels(of: pdf)
        labels = pageLabels
        embeddedNotes = Self.extractAnnotationNotes(from: pdf)
        transitions = Self.transitions(of: pdf)

        var sidecar = PdfpcFile()
        if let fileURL, let data = try? Data(contentsOf: PdfpcFile.url(forPDF: fileURL)) {
            sidecar = (try? PdfpcFile(data: data)) ?? PdfpcFile()
        }
        self.sidecar = sidecar
        notes = sidecar.notes
        if let m = sidecar.durationMinutes {
            talkLimit = .duration(minutes: m)
        } else if let t = sidecar.endTime, let h = t.hour, let m = t.minute {
            talkLimit = .endTime(hour: h, minute: m)
        } else {
            talkLimit = .none
        }
        // Our own key wins; else pdfpc's endSlide (counted in user slides).
        endPage = (sidecar.endPage ?? sidecar.endSlide.flatMap { Self.lastPage(ofUserSlide: $0, labels: pageLabels) })
            .flatMap { $0 < pdf.pageCount ? $0 : nil }
        hiddenPages = sidecar.hiddenPages.filter { $0 < pdf.pageCount }
        defaultTransition = sidecar.defaultTransition
        notesAreMarkdown = !sidecar.disableMarkdown
        notesLayout = pdf.page(at: 0).map { NotesLayout.detect(pageSize: PageRenderer.displaySize(of: $0)) } ?? .none
    }

    convenience init?(data: Data, fileURL: URL?) {
        guard let pdf = PDFDocument(data: data) else { return nil }
        self.init(pdf: pdf, fileURL: fileURL, data: data)
    }

    /// Swaps in a new version of the PDF (recompiled slides). Sidecar notes, notes layout and
    /// duration stay; notes are matched by page index, as pdfpc does.
    func reload(pdf newPDF: PDFDocument, data: Data? = nil) {
        thumbnails.removeAllObjects()
        renderer = ThumbnailRenderer(data: data ?? newPDF.dataRepresentation())
        pdf = newPDF
        pageCount = newPDF.pageCount
        labels = Self.labels(of: newPDF)
        embeddedNotes = Self.extractAnnotationNotes(from: newPDF)
        transitions = Self.transitions(of: newPDF)
        if let e = endPage, e >= pageCount { endPage = nil }
        hiddenPages = hiddenPages.filter { $0 < pageCount }
        revision += 1
    }

    private static func transitions(of pdf: PDFDocument) -> [Int: PageTransition] {
        var result: [Int: PageTransition] = [:]
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let t = PageTransition.parse(page), t.style != .replace { result[i] = t }
        }
        return result
    }

    /// Transition to play when the audience view goes from page `old` to `new`.
    /// Also across skipped pages: moving on to the next shown page counts as "next". Pages
    /// without `/Trans` use the sidecar's default transition.
    func transition(from old: Int, to new: Int) -> PageTransition? {
        PageTransition.plays(from: old, to: new) || nextShown(after: old) == new ? transitions[new] ?? defaultTransition : nil
    }

    /// Last page of pdfpc's user slide `n` (0-based; consecutive pages with equal labels are
    /// one user slide). nil if there are fewer slides.
    static func lastPage(ofUserSlide n: Int, labels: [String]) -> Int? {
        var slide = -1
        for i in labels.indices where i == 0 || labels[i] != labels[i - 1] {
            slide += 1
            if slide == n + 1 { return i - 1 }
        }
        return slide == n ? labels.count - 1 : nil
    }

    private static func labels(of pdf: PDFDocument) -> [String] {
        (0..<pdf.pageCount).map { pdf.page(at: $0)?.label ?? "\($0 + 1)" }
    }

    func page(_ index: Int) -> PDFPage? {
        (0..<pageCount).contains(index) ? pdf.page(at: index) : nil
    }

    /// Width / height of the shown slide (first page, without a Beamer notes half).
    var slideAspectRatio: CGFloat {
        guard let page = page(0) else { return 4 / 3 }
        let size = notesLayout.slideRegion.rect(in: CGRect(origin: .zero, size: PageRenderer.displaySize(of: page))).size
        return size.height > 0 ? size.width / size.height : 4 / 3
    }

    /// The chosen notes layout doesn't match the page format (set by mistake).
    var notesLayoutLooksWrong: Bool {
        guard let page = page(0) else { return false }
        return !notesLayout.fits(pageSize: PageRenderer.displaySize(of: page))
    }

    func isBackup(_ index: Int) -> Bool { endPage.map { index > $0 } ?? false }

    /// Share of the talk done at a page (see `TalkPlan.progress`); skipped pages don't count.
    func talkProgress(at index: Int) -> Double? {
        TalkPlan.progress(at: index, labels: labels, endPage: endPage, hidden: hiddenPages)
    }

    // MARK: Skipped slides

    func isHidden(_ index: Int) -> Bool { hiddenPages.contains(index) }

    /// Skips (or no longer skips) the whole slide of a page, all its overlays.
    func setHidden(_ hidden: Bool, slideOf index: Int) {
        let group = Set(overlayGroup(of: index))
        hiddenPages = hidden ? hiddenPages.union(group) : hiddenPages.subtracting(group)
    }

    /// Next page that isn't skipped; nil at the end.
    func nextShown(after index: Int) -> Int? {
        (index + 1..<max(index + 1, pageCount)).first { !isHidden($0) }
    }

    /// Previous page that isn't skipped; nil at the start.
    func previousShown(before index: Int) -> Int? {
        (0..<min(max(index, 0), pageCount)).last { !isHidden($0) }
    }

    func label(_ index: Int) -> String {
        labels.indices.contains(index) ? labels[index] : "\(index + 1)"
    }

    // MARK: Notes

    /// The page whose sidecar note `index` shows: its own, else the first overlay of its slide
    /// that has one, else the first overlay (where a new note goes).
    func noteOwner(for index: Int) -> Int {
        if notes[index] != nil { return index }
        let group = overlayGroup(of: index)
        return group.first { notes[$0] != nil } ?? group.lowerBound
    }

    /// Note shown for a page (Markdown). Empty if there is none.
    func note(for index: Int) -> String {
        if let n = notes[noteOwner(for: index)] { return n }
        let group = overlayGroup(of: index)
        if let n = embeddedNotes[index] { return n }
        return group.lazy.compactMap { self.embeddedNotes[$0] }.first ?? ""
    }

    /// Sidecar note only — what the editor edits.
    func editableNote(for index: Int) -> String { notes[noteOwner(for: index)] ?? "" }

    func setNote(_ text: String, for index: Int) {
        let owner = noteOwner(for: index)
        guard (notes[owner] ?? "") != text else { return }
        notes[owner] = text.isEmpty ? nil : text
        scheduleSave()
    }

    /// Consecutive pages with the same label.
    func overlayGroup(of index: Int) -> ClosedRange<Int> {
        guard labels.indices.contains(index) else { return index...index }
        var lo = index, hi = index
        while lo > 0, labels[lo - 1] == labels[index] { lo -= 1 }
        while hi < labels.count - 1, labels[hi + 1] == labels[index] { hi += 1 }
        return lo...hi
    }

    /// First page of the next slide — skips the remaining overlays of the current one (and
    /// skipped pages).
    func nextSlideStart(after index: Int) -> Int? {
        nextShown(after: overlayGroup(of: index).upperBound)
    }

    /// First shown page of the previous slide; from inside a slide's overlays, the first shown
    /// overlay of its own slide.
    func previousSlideStart(before index: Int) -> Int? {
        if let first = overlayGroup(of: index).first(where: { !isHidden($0) }), first < index { return first }
        var lower = overlayGroup(of: index).lowerBound
        while lower > 0 {
            let group = overlayGroup(of: lower - 1)
            if let first = group.first(where: { !isHidden($0) }) { return first }
            lower = group.lowerBound
        }
        return nil
    }

    // MARK: Saving

    private func scheduleSave() {
        guard fileURL != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes pending changes immediately (on close, before presenting).
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let fileURL else { return }
        sidecar.notes = notes
        switch talkLimit {
        case .none:                     sidecar.durationMinutes = nil; sidecar.endTime = nil
        case .duration(let m):          sidecar.durationMinutes = m; sidecar.endTime = nil
        case .endTime(let h, let m):    sidecar.durationMinutes = nil; sidecar.endTime = DateComponents(hour: h, minute: m)
        }
        sidecar.endPage = endPage
        sidecar.hiddenPages = hiddenPages
        let url = PdfpcFile.url(forPDF: fileURL)
        // Nothing to store and no file yet: don't create an empty sidecar.
        if notes.isEmpty, talkLimit == .none, endPage == nil, hiddenPages.isEmpty, !FileManager.default.fileExists(atPath: url.path) { return }
        do {
            try sidecar.serialized(pageLabels: labels).write(to: url, options: .atomic)
            saveError = nil
        } catch {
            saveError = String(localized: "Notes could not be saved: \(error.localizedDescription)")
        }
    }

    // MARK: Thumbnails

    func cachedThumbnail(_ index: Int, region: PageRegion, maxPixelSize: CGSize) -> NSImage? {
        thumbnails.object(forKey: thumbnailKey(index, region, maxPixelSize))
    }

    /// Rendered in the background; cached. nil if the task was cancelled or the page is gone.
    func thumbnail(_ index: Int, region: PageRegion, maxPixelSize: CGSize) async -> NSImage? {
        let key = thumbnailKey(index, region, maxPixelSize)
        if let cached = thumbnails.object(forKey: key) { return cached }
        let rev = revision
        guard let cg = await renderer.image(index: index, region: region, maxPixelSize: maxPixelSize),
              rev == revision   // reloaded meanwhile: stale
        else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnails.setObject(image, forKey: key)
        return image
    }

    private func thumbnailKey(_ index: Int, _ region: PageRegion, _ size: CGSize) -> NSString {
        "\(revision)-\(index)-\(region)-\(Int(size.width))x\(Int(size.height))" as NSString
    }

    // MARK: Embedded notes

    nonisolated static func extractAnnotationNotes(from pdf: PDFDocument) -> [Int: String] {
        var result: [Int: String] = [:]
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            var texts: [String] = []
            for annotation in page.annotations where annotation.type == PDFAnnotationSubtype.text.rawValue.trimmingCharacters(in: ["/"]) {
                if let text = annotation.contents?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    texts.append(text)
                }
                annotation.shouldDisplay = false
                annotation.popup?.shouldDisplay = false
            }
            if !texts.isEmpty { result[i] = texts.joined(separator: "\n\n") }
        }
        return result
    }
}
