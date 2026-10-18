import PDFKit
import SwiftUI
import XCTest
@testable import Presently

@MainActor
final class SpotlightTests: XCTestCase {
    private func session() -> PresentationSession {
        let s = PresentationSession(deck: SlideDeck(pdf: PDFFixture.document(pages: [PDFFixture.Page()]), fileURL: nil))
        s.defaults = UserDefaults(suiteName: "SpotlightTests-\(UUID().uuidString)")!
        s.begin()
        return s
    }

    func testKeysSwitchBetweenDotAndSpotlight() {
        XCTAssertEqual(PresentKeyAction(keyCode: 8, characters: "c"), .toggleSpotlight)
        let s = session()
        s.handle(.toggleSpotlight)
        XCTAssertTrue(s.pointer.isEnabled)
        XCTAssertEqual(s.pointer.style, .spotlight)
        s.handle(.togglePointer)
        XCTAssertTrue(s.pointer.isEnabled, "L while the spotlight is on: switches to the dot")
        XCTAssertEqual(s.pointer.style, .dot)
        s.handle(.togglePointer)
        XCTAssertFalse(s.pointer.isEnabled)
        s.handle(.toggleSpotlight)
        s.handle(.toggleSpotlight)
        XCTAssertFalse(s.pointer.isEnabled, "C again: off")
    }

    func testExcludesDrawingAndZoomSelection() {
        let s = session()
        s.handle(.pen)
        s.handle(.toggleSpotlight)
        XCTAssertNil(s.drawings.tool)
        s.handle(.toggleZoom)
        XCTAssertFalse(s.pointer.isEnabled)
        s.handle(.toggleSpotlight)
        XCTAssertFalse(s.isSelectingZoom)
        s.handle(.highlighter)
        XCTAssertFalse(s.pointer.isEnabled)
    }

    func testDimsAllButACircleAroundThePointer() throws {
        let page = try XCTUnwrap(PDFFixture.document(pages: [PDFFixture.Page()]).page(at: 0))   // 400×300
        let pointer = LaserPointer()
        pointer.toggle(.spotlight)
        pointer.move(to: CGPoint(x: 0.25, y: 0.5))
        let renderer = ImageRenderer(content: LaserPointerLayer(pointer: pointer, page: page, region: .full)
            .frame(width: 400, height: 300)
            .background(Color.white))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: image)
        func brightness(_ x: Int, _ y: Int) -> CGFloat { rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)?.brightnessComponent ?? -1 }
        XCTAssertGreaterThan(brightness(100, 150), 0.95, "the spotlight's center stays bright")
        XCTAssertLessThan(brightness(350, 50), 0.3, "outside: dimmed")
        XCTAssertLessThan(brightness(100, 150 + 60), 0.3, "beyond the radius (12 % of 400 = 48 pt)")
    }
}
