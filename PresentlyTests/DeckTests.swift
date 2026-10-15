import PDFKit
import XCTest
@testable import Presently

final class PdfpcFileTests: XCTestCase {
    func testParsesNotesAndDuration() throws {
        let json = """
        {"pdfpcFormat": 2, "duration": 20, "noteFontSize": 18,
         "pages": [{"idx": 0, "label": "1", "overlay": 0, "note": "Hallo *Welt*"},
                   {"idx": 3, "label": "2", "overlay": 2, "note": "Overlay"},
                   {"idx": 4, "label": "3", "overlay": 0, "forcedOverlay": true}]}
        """
        let file = try PdfpcFile(data: Data(json.utf8))
        XCTAssertEqual(file.notes, [0: "Hallo *Welt*", 3: "Overlay"])
        XCTAssertEqual(file.durationMinutes, 20)
    }

    func testRoundTripKeepsUnknownKeys() throws {
        let json = """
        {"pdfpcFormat": 2, "noteFontSize": 18, "endSlide": 4,
         "pages": [{"idx": 4, "label": "x", "overlay": 0, "forcedOverlay": true}]}
        """
        var file = try PdfpcFile(data: Data(json.utf8))
        file.notes[1] = "Neu"
        file.durationMinutes = 15
        let labels = ["1", "2", "2", "2", "3"]
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: file.serialized(pageLabels: labels)) as? [String: Any])
        XCTAssertEqual(root["noteFontSize"] as? Int, 18)
        XCTAssertEqual(root["endSlide"] as? Int, 4)
        XCTAssertEqual(root["duration"] as? Int, 15)
        XCTAssertEqual(root["pdfpcFormat"] as? Int, 2)
        let pages = try XCTUnwrap(root["pages"] as? [[String: Any]])
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0]["idx"] as? Int, 1)
        XCTAssertEqual(pages[0]["note"] as? String, "Neu")
        XCTAssertEqual(pages[0]["label"] as? String, "2")
        XCTAssertEqual(pages[1]["forcedOverlay"] as? Bool, true)
        XCTAssertEqual(pages[1]["label"] as? String, "3", "label comes from the PDF")
        XCTAssertNil(pages[1]["note"])
    }

    func testOverlayIndex() {
        let labels = ["1", "2", "2", "2", "3"]
        XCTAssertEqual((0..<5).map { PdfpcFile.overlayIndex(of: $0, labels: labels) }, [0, 0, 1, 2, 0])
    }

    func testRejectsOldFormat() {
        XCTAssertThrowsError(try PdfpcFile(data: Data("[file]\ntalk.pdf\n[notes]\n### 1\nHi".utf8)))
    }

    func testSidecarURL() {
        XCTAssertEqual(PdfpcFile.url(forPDF: URL(fileURLWithPath: "/a/talk.pdf")).path, "/a/talk.pdfpc")
    }
}

final class NotesLayoutTests: XCTestCase {
    func testRegions() {
        let b = CGRect(x: 0, y: 0, width: 800, height: 300)
        XCTAssertEqual(PageRegion.leftHalf.rect(in: b), CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertEqual(PageRegion.rightHalf.rect(in: b), CGRect(x: 400, y: 0, width: 400, height: 300))
        // y up: "top" is the upper half
        XCTAssertEqual(PageRegion.topHalf.rect(in: b), CGRect(x: 0, y: 150, width: 800, height: 150))
        XCTAssertEqual(NotesLayout.right.slideRegion, .leftHalf)
        XCTAssertEqual(NotesLayout.bottom.slideRegion, .topHalf)
        XCTAssertNil(NotesLayout.none.notesRegion)
    }

    func testLayoutMustFitPageFormat() {
        let slide169 = CGSize(width: 842, height: 474)
        XCTAssertTrue(NotesLayout.none.fits(pageSize: slide169))
        XCTAssertFalse(NotesLayout.right.fits(pageSize: slide169), "half a slide for the audience")
        XCTAssertFalse(NotesLayout.bottom.fits(pageSize: slide169))
        XCTAssertTrue(NotesLayout.right.fits(pageSize: CGSize(width: 32, height: 9)))
        XCTAssertTrue(NotesLayout.bottom.fits(pageSize: CGSize(width: 16, height: 18)))
    }

    func testDetectsBeamerSideBySidePages() {
        XCTAssertEqual(NotesLayout.detect(pageSize: CGSize(width: 800, height: 300)), .right)       // 2 × 4:3
        XCTAssertEqual(NotesLayout.detect(pageSize: CGSize(width: 32, height: 9)), .right)          // 2 × 16:9
        XCTAssertEqual(NotesLayout.detect(pageSize: CGSize(width: 16, height: 9)), .none)
        XCTAssertEqual(NotesLayout.detect(pageSize: CGSize(width: 4, height: 3)), .none)
    }
}

final class PageRendererTests: XCTestCase {
    private func color(of image: NSImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let rep = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        return (Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }

    func testRegionsShowTheRightHalf() throws {
        let page = try XCTUnwrap(PDFFixture.document(pages: [.init()], size: CGSize(width: 800, height: 300)).page(at: 0))
        let left = try XCTUnwrap(PageRenderer.image(of: page, region: .leftHalf, maxPixelSize: CGSize(width: 400, height: 400)))
        XCTAssertEqual(left.size, CGSize(width: 400, height: 300))
        XCTAssertGreaterThan(color(of: left, x: 390, y: 150).r, 200, "left half is red up to its right edge")
        let right = try XCTUnwrap(PageRenderer.image(of: page, region: .rightHalf, maxPixelSize: CGSize(width: 400, height: 400)))
        XCTAssertGreaterThan(color(of: right, x: 10, y: 150).b, 200)
    }

    func testRotatedPage() throws {
        let page = try XCTUnwrap(PDFFixture.document(pages: [.init()], size: CGSize(width: 400, height: 300), rotation: 90).page(at: 0))
        XCTAssertEqual(PageRenderer.displaySize(of: page), CGSize(width: 300, height: 400))
        let image = try XCTUnwrap(PageRenderer.image(of: page, region: .full, maxPixelSize: CGSize(width: 300, height: 400)))
        XCTAssertEqual(image.size, CGSize(width: 300, height: 400))
        // Rotated 90° clockwise: the red (left) half ends up on top. Bitmap rows count from the top.
        XCTAssertGreaterThan(color(of: image, x: 150, y: 20).r, 200)
        XCTAssertGreaterThan(color(of: image, x: 150, y: 380).b, 200)
    }
}

@MainActor
final class SlideDeckTests: XCTestCase {
    func testLabelsAndOverlayGroups() {
        let deck = SlideDeck(pdf: PDFFixture.document(pages: PDFFixture.overlayPages), fileURL: nil)
        XCTAssertEqual(deck.labels, ["1", "2", "2", "2", "3"])
        XCTAssertEqual(deck.overlayGroup(of: 2), 1...3)
        XCTAssertEqual(deck.overlayGroup(of: 0), 0...0)
        XCTAssertEqual(deck.nextSlideStart(after: 1), 4)
        XCTAssertNil(deck.nextSlideStart(after: 4))
    }

    func testPagesWithoutLabelsAreNumbered() {
        let deck = SlideDeck(pdf: PDFFixture.document(pages: [.init(), .init()]), fileURL: nil)
        XCTAssertEqual(deck.labels, ["1", "2"])
    }

    func testOverlaysShareANote() {
        let deck = SlideDeck(pdf: PDFFixture.document(pages: PDFFixture.overlayPages), fileURL: nil)
        deck.setNote("Zwei", for: 2)
        XCTAssertEqual(deck.notes, [1: "Zwei"], "a new note goes to the first overlay")
        XCTAssertEqual((1...3).map { deck.note(for: $0) }, ["Zwei", "Zwei", "Zwei"])
        XCTAssertEqual(deck.note(for: 4), "")
        deck.setNote("", for: 3)
        XCTAssertTrue(deck.notes.isEmpty)
    }

    func testEmbeddedAnnotationNotesAreReadAndHidden() throws {
        let pdf = PDFFixture.document(pages: [.init(note: "Aus dem PDF"), .init()])
        let deck = SlideDeck(pdf: pdf, fileURL: nil)
        XCTAssertEqual(deck.embeddedNotes, [0: "Aus dem PDF"])
        XCTAssertEqual(deck.note(for: 0), "Aus dem PDF")
        let annotation = try XCTUnwrap(pdf.page(at: 0)?.annotations.first)
        XCTAssertFalse(annotation.shouldDisplay, "the audience must not see note icons")

        deck.setNote("Sidecar", for: 0)
        XCTAssertEqual(deck.note(for: 0), "Sidecar", "sidecar wins")
    }

    func testDetectsNotesLayout() {
        let wide = SlideDeck(pdf: PDFFixture.document(pages: [.init()], size: CGSize(width: 800, height: 300)), fileURL: nil)
        XCTAssertEqual(wide.notesLayout, .right)
        let normal = SlideDeck(pdf: PDFFixture.document(pages: [.init()]), fileURL: nil)
        XCTAssertEqual(normal.notesLayout, .none)
    }

    func testSavesAndLoadsSidecar() throws {
        let dir = try PDFFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdfURL = dir.appendingPathComponent("talk.pdf")
        let data = PDFFixture.data(pages: PDFFixture.overlayPages)
        try data.write(to: pdfURL)
        let sidecarURL = dir.appendingPathComponent("talk.pdfpc")

        let deck = try XCTUnwrap(SlideDeck(data: data, fileURL: pdfURL))
        deck.saveNow()
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL.path), "no notes: no empty sidecar")

        deck.setNote("Einleitung", for: 0)
        deck.talkLimit = .duration(minutes: 25)
        deck.saveNow()
        XCTAssertNil(deck.saveError)

        let reopened = try XCTUnwrap(SlideDeck(data: data, fileURL: pdfURL))
        XCTAssertEqual(reopened.note(for: 0), "Einleitung")
        XCTAssertEqual(reopened.talkLimit, .duration(minutes: 25))
    }
}

@MainActor
final class NotesLayoutWarningTests: XCTestCase {
    func testWrongLayoutIsFlagged() {
        let deck = SlideDeck(pdf: PDFFixture.document(pages: [.init()], size: CGSize(width: 842, height: 474)), fileURL: nil)
        XCTAssertEqual(deck.notesLayout, .none)
        XCTAssertFalse(deck.notesLayoutLooksWrong)
        deck.notesLayout = .right
        XCTAssertTrue(deck.notesLayoutLooksWrong)
        XCTAssertEqual(deck.slideAspectRatio, 421.0 / 474, accuracy: 0.001, "portrait — what the user saw")
    }
}
