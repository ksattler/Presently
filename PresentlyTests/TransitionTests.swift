import PDFKit
import XCTest
@testable import Presently

@MainActor
final class TransitionTests: XCTestCase {
    private func transition(_ dict: String) throws -> PageTransition? {
        let doc = PDFFixture.document(pages: [.init(transition: dict)])
        return PageTransition.parse(try XCTUnwrap(doc.page(at: 0)))
    }

    func testParsesBeamerTransitions() throws {
        // \\transdissolve[duration=0.5]
        XCTAssertEqual(try transition("/S /Dissolve /D 0.5"), PageTransition(style: .dissolve, duration: 0.5))
        // \\transwipe[direction=90]
        let wipe = try XCTUnwrap(try transition("/S /Wipe /Di 90"))
        XCTAssertEqual(wipe.style, .wipe)
        XCTAssertEqual(wipe.direction, 90)
        XCTAssertEqual(wipe.motion, CGVector(dx: 0, dy: 1), "upward")
        // \\transsplitverticalout
        let split = try XCTUnwrap(try transition("/S /Split /Dm /V /M /O"))
        XCTAssertFalse(split.horizontal)
        XCTAssertFalse(split.inward)
        // \\transblindshorizontal, integer duration
        let blinds = try XCTUnwrap(try transition("/S /Blinds /Dm /H /D 2"))
        XCTAssertTrue(blinds.horizontal)
        XCTAssertEqual(blinds.duration, 2)
    }

    func testDefaultsAndOddValues() throws {
        let box = try XCTUnwrap(try transition("/S /Box"))
        XCTAssertEqual(box, PageTransition(style: .box, duration: 1, horizontal: true, inward: true, direction: 0))
        XCTAssertEqual(try transition("/S /Push /Di 270")?.motion, CGVector(dx: 0, dy: -1))
        XCTAssertEqual(try transition("/S /Push /Di -90")?.direction, 270)
        XCTAssertEqual(try transition("/S /Fade /D 60")?.duration, PageTransition.durationRange.upperBound)
        XCTAssertEqual(try transition("/S /Zoom")?.style, .dissolve, "unknown style: soft fallback")
        XCTAssertEqual(try transition("/D 0.3")?.style, .replace, "no /S means replace")
        XCTAssertNil(PageTransition.parse(try XCTUnwrap(PDFFixture.document(pages: [.init()]).page(at: 0))))
    }

    func testPlaysOnlyWhenMovingToTheNextPage() {
        let deck = SlideDeck(pdf: PDFFixture.document(pages: [
            .init(), .init(transition: "/S /Dissolve"), .init(transition: "/S /R"), .init(transition: "/S /Wipe"),
        ]), fileURL: nil)
        XCTAssertEqual(deck.transition(from: 0, to: 1)?.style, .dissolve)
        XCTAssertNil(deck.transition(from: 2, to: 1), "going back: instant")
        XCTAssertNil(deck.transition(from: 0, to: 3), "jump: instant")
        XCTAssertNil(deck.transition(from: 1, to: 2), "replace: nothing to play")
        XCTAssertEqual(deck.transition(from: 2, to: 3)?.style, .wipe)
    }

    func testDocumentTransitionOnlyWhereANewSlideBegins() {
        // Slides 1, 2 (three overlays), 3; page 3 has its own /Trans.
        let deck = SlideDeck(pdf: PDFFixture.document(pages: [
            .init(label: "1"), .init(label: "2"), .init(label: "2"), .init(label: "2", transition: "/S /Wipe"), .init(label: "3"),
        ]), fileURL: nil)
        deck.defaultTransition = PageTransition(style: .cube)
        XCTAssertEqual(deck.transition(from: 0, to: 1)?.style, .cube, "new slide")
        XCTAssertNil(deck.transition(from: 1, to: 2), "overlay step: no document transition")
        XCTAssertEqual(deck.transition(from: 2, to: 3)?.style, .wipe, "/Trans from the PDF plays on every page")
        XCTAssertEqual(deck.transition(from: 3, to: 4)?.style, .cube)
        XCTAssertNil(deck.transition(from: 4, to: 1), "going back: instant")

        deck.defaultTransition = nil
        XCTAssertNil(deck.transition(from: 0, to: 1))
    }

    func testPdfpcStringsRoundTrip() {
        for style in PageTransition.Style.allCases {
            let t = PageTransition(style: style, duration: 0.7, horizontal: false, inward: false, direction: 270)
            XCTAssertEqual(PageTransition.parse(pdfpc: t.pdfpcString), t, "\(style)")
        }
        XCTAssertEqual(PageTransition(style: .push).pdfpcString, "push:1:0:horizontal:inward")
        XCTAssertEqual(PageTransition(style: .fadeThroughBlack, duration: 1.5).pdfpcString, "fadethroughblack:1.5:0:horizontal:inward")
    }

    func testOwnStylesAreNotReadFromThePDF() throws {
        XCTAssertEqual(try transition("/S /Cube")?.style, .dissolve, "not a PDF style")
        XCTAssertEqual(try transition("/S /FadeThroughBlack")?.style, .dissolve)
        XCTAssertEqual(try transition("/S /MoveIn")?.style, .dissolve)
    }

    func testSavesTheDocumentTransitionInTheSidecar() throws {
        let dir = try PDFFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdfURL = dir.appendingPathComponent("talk.pdf"), sidecarURL = dir.appendingPathComponent("talk.pdfpc")
        let data = PDFFixture.data(pages: [.init(), .init()])
        try data.write(to: pdfURL)
        func root() throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: sidecarURL)) as? [String: Any])
        }

        let deck = try XCTUnwrap(SlideDeck(data: data, fileURL: pdfURL))
        deck.defaultTransition = PageTransition(style: .wipe, duration: 0.5, direction: 90)
        deck.saveNow()
        XCTAssertEqual(try root()["defaultTransition"] as? String, "wipe:0.5:90:horizontal:inward", "pdfpc reads it")
        XCTAssertNil(try root()[PdfpcFile.transitionKey])

        deck.defaultTransition = PageTransition(style: .flip)
        deck.saveNow()
        XCTAssertNil(try root()["defaultTransition"], "pdfpc doesn't know flip")
        XCTAssertEqual(try root()[PdfpcFile.transitionKey] as? String, "flip:1:0:horizontal:inward")
        XCTAssertEqual(try XCTUnwrap(SlideDeck(data: data, fileURL: pdfURL)).defaultTransition, PageTransition(style: .flip), "loaded again")

        deck.defaultTransition = nil
        deck.saveNow()
        XCTAssertNil(try root()["defaultTransition"])
        XCTAssertNil(try root()[PdfpcFile.transitionKey])
    }

    func testNoSidecarWithoutChanges() throws {
        let dir = try PDFFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdfURL = dir.appendingPathComponent("talk.pdf")
        let data = PDFFixture.data(pages: [.init()])
        try data.write(to: pdfURL)
        try XCTUnwrap(SlideDeck(data: data, fileURL: pdfURL)).saveNow()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("talk.pdfpc").path))
    }

    func testPageViewOverlaysAndCancels() {
        let doc = PDFFixture.document(pages: [.init(), .init()])
        let view = PDFPageNSView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        view.show(doc.page(at: 0), index: 0, transition: nil)
        XCTAssertNil(view.transitionLayer)

        let styles = PageTransition.Style.allCases.filter { $0 != .replace }
        for (i, style) in styles.enumerated() {
            let target = (i + 1) % 2   // alternate between the two pages
            view.show(doc.page(at: target), index: target, transition: PageTransition(style: style, duration: 2))
            let overlay = view.transitionLayer
            XCTAssertNotNil(overlay, "\(style)")
            XCTAssertEqual(overlay?.name, PageTransitionAnimator.layerName)
            XCTAssertNotNil(overlay?.superlayer)
        }
        let last = view.transitionLayer
        view.show(doc.page(at: 0), index: 0, transition: nil)   // next turn mid-animation
        XCTAssertNil(view.transitionLayer)
        XCTAssertNil(last?.superlayer, "overlay removed immediately")
    }
}
