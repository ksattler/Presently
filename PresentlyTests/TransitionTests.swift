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

    func testPageViewOverlaysAndCancels() {
        let doc = PDFFixture.document(pages: [.init(), .init()])
        let view = PDFPageNSView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        view.show(doc.page(at: 0), index: 0, transition: nil)
        XCTAssertNil(view.transitionLayer)

        let styles: [PageTransition.Style] = [.dissolve, .wipe, .push, .cover, .uncover, .split, .box, .blinds, .fly]
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
