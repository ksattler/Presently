import PDFKit
import XCTest
@testable import Presently

/// Skipped slides (pdfpc's per-page `hidden`).
@MainActor
final class SkipTests: XCTestCase {
    func testPdfpcHiddenRoundTrip() throws {
        let json = #"{"pdfpcFormat": 2, "pages": [{"idx": 2, "label": "2", "overlay": 1, "hidden": true, "forcedOverlay": true}, {"idx": 4, "hidden": false, "note": "x"}]}"#
        var file = try PdfpcFile(data: Data(json.utf8))
        XCTAssertEqual(file.hiddenPages, [2])
        file.hiddenPages.insert(0)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: file.serialized(pageLabels: ["1", "2", "2", "2", "3"])) as? [String: Any])
        let pages = try XCTUnwrap(root["pages"] as? [[String: Any]])
        XCTAssertEqual(pages.map { $0["idx"] as? Int }, [0, 2, 4], "hidden pages are written even without a note")
        XCTAssertEqual(pages[0]["hidden"] as? Bool, true)
        XCTAssertEqual(pages[1]["hidden"] as? Bool, true)
        XCTAssertEqual(pages[1]["forcedOverlay"] as? Bool, true, "unknown keys stay")
        XCTAssertNil(pages[2]["hidden"], "not hidden: no key, as pdfpc writes it")
        XCTAssertEqual(pages[2]["note"] as? String, "x")
    }

    func testSkipsWholeSlidesAndSavesThem() throws {
        let dir = try PDFFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdfURL = dir.appendingPathComponent("talk.pdf")
        let data = PDFFixture.data(pages: PDFFixture.overlayPages)   // labels 1, 2, 2, 2, 3
        try data.write(to: pdfURL)

        let deck = try XCTUnwrap(SlideDeck(data: data, fileURL: pdfURL))
        deck.setHidden(true, slideOf: 2)
        XCTAssertEqual(deck.hiddenPages, [1, 2, 3], "all overlays of the slide")
        deck.saveNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("talk.pdfpc").path),
                      "skipped slides alone create a sidecar")

        let reopened = try XCTUnwrap(SlideDeck(data: data, fileURL: pdfURL))
        XCTAssertEqual(reopened.hiddenPages, [1, 2, 3])
        reopened.setHidden(false, slideOf: 1)
        XCTAssertTrue(reopened.hiddenPages.isEmpty)
    }

    private func session(hiding page: Int?) -> PresentationSession {
        let pages = PDFFixture.overlayPages + [PDFFixture.Page(label: "4", transition: "/S /Dissolve")]   // 1, 2, 2, 2, 3, 4
        let deck = SlideDeck(pdf: PDFFixture.document(pages: pages), fileURL: nil)
        if let page { deck.setHidden(true, slideOf: page) }
        let s = PresentationSession(deck: deck)
        s.defaults = UserDefaults(suiteName: "SkipTests-\(UUID().uuidString)")!
        s.begin()
        return s
    }

    func testPagingSkipsButJumpsDont() {
        let s = session(hiding: 2)   // pages 1…3 skipped
        s.handle(.next)
        XCTAssertEqual(s.currentIndex, 4)
        s.handle(.previous)
        XCTAssertEqual(s.currentIndex, 0)
        s.handle(.nextSlide)
        XCTAssertEqual(s.currentIndex, 4)
        s.handle(.previousSlide)
        XCTAssertEqual(s.currentIndex, 0)

        s.go(to: 2)
        XCTAssertEqual(s.currentIndex, 2, "a jump reaches a skipped page")
        s.handle(.next)
        XCTAssertEqual(s.currentIndex, 4)
        s.go(to: 2)
        s.handle(.previous)
        XCTAssertEqual(s.currentIndex, 0)
    }

    func testNothingShownAhead() {
        let s = session(hiding: 5)   // the last slide is skipped
        s.go(to: 4)
        s.handle(.next)
        XCTAssertEqual(s.currentIndex, 4, "stays: only skipped pages follow")
        s.handle(.nextSlide)
        XCTAssertEqual(s.currentIndex, 4)
    }

    func testProgressUpcomingAndTransitions() {
        let s = session(hiding: 2)
        let deck = s.deck
        XCTAssertEqual(deck.talkProgress(at: 4), 1.0 / 3, "slides 1, 3, 4: one done")
        XCTAssertEqual(PresenterLayout.upcomingPages(after: 0, showsNext: false, count: 3, pageCount: deck.pageCount,
                                                     isHidden: deck.isHidden), [4, 5])
        XCTAssertEqual(PresenterLayout.upcomingPages(after: 0, showsNext: true, count: 3, pageCount: deck.pageCount,
                                                     isHidden: deck.isHidden), [5])
        XCTAssertEqual(deck.nextShown(after: 0), 4)

        // Page 5 has a transition; page 4 → 5 is "next", and so is 3 → 5 across a skipped page.
        let t = session(hiding: 4)   // page 4 (slide "3") skipped
        XCTAssertNotNil(t.deck.transition(from: 3, to: 5))
        XCTAssertNil(session(hiding: nil).deck.transition(from: 3, to: 5), "a jump without skipped pages in between")
    }
}
