import PDFKit
import XCTest
@testable import Presently

@MainActor
final class ZoomTests: XCTestCase {
    func testSelectionKeepsTheSlideAspect() throws {
        // A wide drag becomes a square (slide aspect) around its center.
        let r = try XCTUnwrap(SlideZoom.rect(from: CGPoint(x: 0.2, y: 0.4), to: CGPoint(x: 0.6, y: 0.5)))
        XCTAssertEqual(r.width, 0.4, accuracy: 1e-9)
        XCTAssertEqual(r.height, 0.4, accuracy: 1e-9)
        XCTAssertEqual(r.midX, 0.4, accuracy: 1e-9)
        XCTAssertEqual(r.midY, 0.45, accuracy: 1e-9)
    }

    func testClickZoomsTwiceAroundThePointAndStaysInside() throws {
        let center = try XCTUnwrap(SlideZoom.rect(from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.505, y: 0.5)))
        XCTAssertEqual(center, CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        let corner = try XCTUnwrap(SlideZoom.rect(from: CGPoint(x: 0.95, y: 0.02), to: CGPoint(x: 0.95, y: 0.02)))
        XCTAssertEqual(corner, CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), "moved inside the slide")
    }

    func testSelectionLimits() throws {
        let tiny = try XCTUnwrap(SlideZoom.rect(from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.53, y: 0.53)))
        XCTAssertEqual(tiny.width, 1 / SlideZoom.maxFactor, accuracy: 1e-9)
        XCTAssertNil(SlideZoom.rect(from: .zero, to: CGPoint(x: 1, y: 1)), "whole slide: no zoom")
    }

    func testFittedRectWithZoom() throws {
        let page = try XCTUnwrap(PDFFixture.document(pages: [PDFFixture.Page()]).page(at: 0))   // 400×300
        let view = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertEqual(PageRenderer.fittedRect(for: page, region: .full, in: view), view)
        XCTAssertEqual(PageRenderer.fittedRect(for: page, region: .full, in: view, yUp: true), view)
        // Bottom-right quarter: the slide doubles and its bottom-right corner meets the view's.
        let quarter = CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        XCTAssertEqual(PageRenderer.fittedRect(for: page, region: .full, in: view, zoom: quarter),
                       CGRect(x: -400, y: -300, width: 800, height: 600))
        XCTAssertEqual(PageRenderer.fittedRect(for: page, region: .full, in: view, zoom: quarter, yUp: true),
                       CGRect(x: -400, y: 0, width: 800, height: 600))
    }

    func testDrawsOnlyTheZoomedPart() throws {
        // Fixture pages: red left half, blue right half. Zoomed into the right half: all blue.
        let page = try XCTUnwrap(PDFFixture.document(pages: [PDFFixture.Page()]).page(at: 0))
        let w = 80, h = 60
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        PageRenderer.draw(page, region: .full, in: CGRect(x: 0, y: 0, width: w, height: h),
                          zoom: CGRect(x: 0.55, y: 0.25, width: 0.4, height: 0.4), context: ctx)
        let pixels = try XCTUnwrap(ctx.data).bindMemory(to: UInt8.self, capacity: w * h * 4)
        for (x, y) in [(2, 2), (w - 3, 2), (w / 2, h / 2), (2, h - 3)] {
            let i = (y * w + x) * 4
            XCTAssertLessThan(pixels[i], 60, "red at \(x),\(y)")
            XCTAssertGreaterThan(pixels[i + 2], 200, "blue at \(x),\(y)")
        }
    }

    // MARK: Session

    private func session() -> PresentationSession {
        let s = PresentationSession(deck: SlideDeck(pdf: PDFFixture.document(pages: [PDFFixture.Page(), PDFFixture.Page()]),
                                                    fileURL: nil))
        s.defaults = UserDefaults(suiteName: "ZoomTests-\(UUID().uuidString)")!
        s.begin()
        return s
    }

    func testKeyAndSelection() {
        XCTAssertEqual(PresentKeyAction(keyCode: 46, characters: "m"), .toggleZoom)
        let s = session()
        s.handle(.togglePointer)
        s.handle(.toggleZoom)
        XCTAssertTrue(s.isSelectingZoom)
        XCTAssertFalse(s.pointer.isEnabled, "zoom selection replaces the laser pointer")
        s.zoom(from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.5, y: 0.5))
        XCTAssertFalse(s.isSelectingZoom)
        XCTAssertEqual(s.zoom, CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        XCTAssertEqual(s.audienceZoom, s.zoom)
        s.handle(.toggleZoom)
        XCTAssertNil(s.zoom, "M again: whole slide")
        XCTAssertEqual(s.audienceZoom, PageRenderer.unzoomed)
    }

    func testZoomEndsWithItsPageAndOnEscape() {
        let s = session()
        s.zoom(from: .zero, to: CGPoint(x: 0.5, y: 0.5))
        XCTAssertNotNil(s.zoom)
        s.handle(.next)
        XCTAssertNil(s.zoom, "page turn")

        s.zoom(from: .zero, to: CGPoint(x: 0.5, y: 0.5))
        s.handle(.pen)
        XCTAssertTrue(s.handle(.exit))
        XCTAssertNotNil(s.zoom, "Esc ends drawing first")
        XCTAssertTrue(s.handle(.exit))
        XCTAssertNil(s.zoom)

        s.handle(.toggleZoom)
        XCTAssertTrue(s.handle(.exit))
        XCTAssertFalse(s.isSelectingZoom)
        XCTAssertFalse(s.handle(.exit), "nothing left: the presentation ends")
    }

    func testZoomStaysWhileFrozenAndNeedsTheAudiencePage() {
        let s = session()
        s.zoom(from: .zero, to: CGPoint(x: 0.5, y: 0.5))
        s.handle(.toggleFreeze)
        s.handle(.next)
        XCTAssertNotNil(s.zoom, "the audience still sees the zoomed page")
        s.handle(.exit)   // Esc: zoom first
        XCTAssertNil(s.zoom)
        s.zoom(from: .zero, to: CGPoint(x: 0.5, y: 0.5))
        XCTAssertNil(s.zoom, "the presenter's current page isn't the audience's")
        s.end()
        XCTAssertFalse(s.isSelectingZoom)
    }
}
