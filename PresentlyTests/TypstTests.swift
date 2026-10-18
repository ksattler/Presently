import PDFKit
import XCTest
@testable import Presently

/// Typst slides (Touying, Polylux): page labels come from Typst, everything else from the
/// `.pdfpc` file exported with `typst eval 'query(<pdfpc-file>).first().value' --in talk.typ`.
@MainActor
final class TypstTests: XCTestCase {
    /// Touying 0.7.4's export of a deck with title, intro, a slide with two `#pause`s (note on
    /// the last overlay), a hidden slide and a last slide.
    static let touyingSidecar = #"{"pdfpcFormat":2,"disableMarkdown":false,"duration":20,"defaultTransition":"push:1:0:horizontal:outward","pages":[{"idx":0,"label":"1","overlay":0,"forcedOverlay":false,"hidden":false},{"idx":1,"label":"2","overlay":0,"forcedOverlay":false,"hidden":false},{"idx":2,"label":"3","overlay":0,"forcedOverlay":false,"hidden":false,"note":"Intro note"},{"idx":3,"label":"4","overlay":0,"forcedOverlay":false,"hidden":false},{"idx":4,"label":"4","overlay":1,"forcedOverlay":true,"hidden":false},{"idx":5,"label":"4","overlay":2,"forcedOverlay":true,"hidden":false,"note":"Overlay note"},{"idx":6,"label":"5","overlay":0,"forcedOverlay":false,"hidden":true},{"idx":7,"label":"6","overlay":0,"forcedOverlay":false,"hidden":false}]}"#
    /// Page labels Typst writes for that deck.
    static let touyingLabels = ["1", "2", "3", "4", "4", "4", "5", "6"]

    private var dir: URL!

    override func setUpWithError() throws { dir = try PDFFixture.temporaryDirectory() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func deck(sidecar: String, labels: [String] = touyingLabels) throws -> (SlideDeck, Data, URL) {
        let pdfURL = dir.appendingPathComponent("talk.pdf")
        let data = PDFFixture.data(pages: labels.map { PDFFixture.Page(label: $0) })
        try data.write(to: pdfURL)
        try Data(sidecar.utf8).write(to: dir.appendingPathComponent("talk.pdfpc"))
        return (try XCTUnwrap(SlideDeck(data: data, fileURL: pdfURL)), data, pdfURL)
    }

    func testReadsTouyingExport() throws {
        let (deck, _, _) = try deck(sidecar: Self.touyingSidecar)
        XCTAssertEqual(deck.note(for: 2), "Intro note")
        for i in 3...5 { XCTAssertEqual(deck.note(for: i), "Overlay note", "the note on the last overlay shows on all of them") }
        XCTAssertEqual(deck.hiddenPages, [6])
        XCTAssertEqual(deck.talkLimit, .duration(minutes: 20))
        XCTAssertTrue(deck.notesAreMarkdown)
        let push = PageTransition(style: .push, duration: 1, horizontal: true, inward: false, direction: 0)
        XCTAssertEqual(deck.transition(from: 0, to: 1), push, "Typst can't write /Trans: pdfpc's default applies")
        XCTAssertNil(deck.transition(from: 0, to: 2), "still only when moving on")
    }

    func testSavingKeepsTouyingsKeys() throws {
        let (deck, _, _) = try deck(sidecar: Self.touyingSidecar)
        deck.setNote("Edited", for: 2)
        deck.saveNow()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("talk.pdfpc"))) as? [String: Any])
        XCTAssertEqual(root["defaultTransition"] as? String, "push:1:0:horizontal:outward")
        XCTAssertEqual(root["disableMarkdown"] as? Bool, false)
        let pages = try XCTUnwrap(root["pages"] as? [[String: Any]])
        let byIdx = Dictionary(uniqueKeysWithValues: pages.map { ($0["idx"] as! Int, $0) })
        XCTAssertEqual(byIdx[2]?["note"] as? String, "Edited")
        XCTAssertEqual(byIdx[5]?["label"] as? String, "4")
        XCTAssertEqual(byIdx[5]?["overlay"] as? Int, 2)
        XCTAssertEqual(byIdx[5]?["forcedOverlay"] as? Bool, true)
        XCTAssertEqual(byIdx[6]?["hidden"] as? Bool, true)
    }

    func testPdfpcTransitionStrings() {
        XCTAssertEqual(PageTransition.parse(pdfpc: "fade"), PageTransition(style: .fade))
        XCTAssertEqual(PageTransition.parse(pdfpc: "replace")?.style, .replace)
        XCTAssertEqual(PageTransition.parse(pdfpc: "wipe:0.5:90:vertical:inward"),
                       PageTransition(style: .wipe, duration: 0.5, horizontal: false, inward: true, direction: 90))
        XCTAssertEqual(PageTransition.parse(pdfpc: "Blinds:2")?.duration, 2)
        XCTAssertNil(PageTransition.parse(pdfpc: "explode"))
        XCTAssertNil(PageTransition.parse(pdfpc: ""))
    }

    func testEndSlideCountsUserSlides() throws {
        let labels = ["1", "2", "2", "3"]
        XCTAssertEqual(SlideDeck.lastPage(ofUserSlide: 0, labels: labels), 0)
        XCTAssertEqual(SlideDeck.lastPage(ofUserSlide: 1, labels: labels), 2, "the slide's last overlay")
        XCTAssertEqual(SlideDeck.lastPage(ofUserSlide: 2, labels: labels), 3)
        XCTAssertNil(SlideDeck.lastPage(ofUserSlide: 3, labels: labels))

        XCTAssertEqual(try deck(sidecar: #"{"pdfpcFormat":2,"endSlide":3}"#).0.endPage, 5, "Polylux-style end of talk")
        XCTAssertEqual(try deck(sidecar: #"{"pdfpcFormat":2,"endSlide":3,"presentlyEndPage":1}"#).0.endPage, 1, "our own key wins")
    }

    func testPlainTextNotes() throws {
        XCTAssertFalse(try deck(sidecar: #"{"pdfpcFormat":2,"disableMarkdown":true}"#).0.notesAreMarkdown)
    }

    func testTouyingNotesOnSecondScreenAreDetected() {
        // `config-common(show-notes-on-second-screen: right)` with a 16:9 theme: 1683.78 × 473.56 pt.
        XCTAssertEqual(NotesLayout.detect(pageSize: CGSize(width: 1683.78, height: 473.563)), .right)
        XCTAssertEqual(NotesLayout.detect(pageSize: CGSize(width: 841.89, height: 473.563)), .none, "plain 16:9")
    }
}
