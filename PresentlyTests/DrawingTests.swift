import XCTest
@testable import Presently

@MainActor
final class DrawingTests: XCTestCase {
    private func session() -> PresentationSession {
        PresentationSession(deck: SlideDeck(pdf: PDFFixture.document(pages: [.init(), .init(), .init()]), fileURL: nil))
    }

    func testKeys() {
        XCTAssertEqual(PresentKeyAction(keyCode: 2, characters: "d"), .pen)
        XCTAssertEqual(PresentKeyAction(keyCode: 4, characters: "h"), .highlighter)
        XCTAssertEqual(PresentKeyAction(keyCode: 14, characters: "e"), .eraser)
        XCTAssertEqual(PresentKeyAction(keyCode: 6, characters: "z"), .undoDrawing)
        XCTAssertEqual(PresentKeyAction(keyCode: 7, characters: "x"), .clearDrawing)
        XCTAssertNil(PresentKeyAction(keyCode: 6, characters: "z", modifiers: .command), "⌘Z stays the menu's")
    }

    func testStrokesArePerPage() {
        let d = Drawings()
        d.tool = .pen
        d.begin(at: CGPoint(x: 0.1, y: 0.1), page: 0)
        d.move(to: CGPoint(x: 0.5, y: 0.5), page: 0)
        d.move(to: CGPoint(x: 0.5004, y: 0.5), page: 0)   // < 1 px: dropped
        XCTAssertEqual(d.strokes(on: 0).count, 1, "stroke in progress is shown")
        d.end()
        XCTAssertEqual(d.strokes[0]?.first?.points.count, 2)
        XCTAssertEqual(d.strokes[0]?.first?.color, .red)
        XCTAssertTrue(d.strokes(on: 1).isEmpty)

        d.tool = .highlighter
        d.begin(at: CGPoint(x: 0.2, y: 0.8), page: 0)
        d.end()
        XCTAssertEqual(d.strokes[0]?.last?.isHighlighter, true)
        XCTAssertEqual(d.strokes[0]?.last?.color, .yellow)
    }

    func testNoToolDrawsNothing() {
        let d = Drawings()
        d.begin(at: CGPoint(x: 0.5, y: 0.5), page: 0)
        d.end()
        XCTAssertFalse(d.hasStrokes)
    }

    func testEraserRemovesTouchedStrokes() {
        let d = Drawings()
        d.tool = .pen
        d.begin(at: CGPoint(x: 0.1, y: 0.5), page: 0); d.move(to: CGPoint(x: 0.9, y: 0.5), page: 0); d.end()
        d.begin(at: CGPoint(x: 0.1, y: 0.9), page: 0); d.move(to: CGPoint(x: 0.9, y: 0.9), page: 0); d.end()
        d.tool = .eraser
        d.begin(at: CGPoint(x: 0.5, y: 0.2), page: 0)   // far from both
        XCTAssertEqual(d.strokes[0]?.count, 2)
        d.move(to: CGPoint(x: 0.5, y: 0.51), page: 0)    // across the middle of the first line
        XCTAssertEqual(d.strokes[0]?.count, 1)
        XCTAssertEqual(d.strokes[0]?.first?.points.first?.y, 0.9)
    }

    func testSegmentDistance() {
        let a = CGPoint(x: 0, y: 0), b = CGPoint(x: 1, y: 0)
        XCTAssertEqual(Drawings.segmentDistance(CGPoint(x: 0.5, y: 0.2), a, b), 0.2, accuracy: 1e-9)
        XCTAssertEqual(Drawings.segmentDistance(CGPoint(x: 2, y: 0), a, b), 1, accuracy: 1e-9, "beyond the end")
    }

    func testUndoAndClearViaKeys() {
        let s = session()
        s.handle(.pen)
        for y in [0.2, 0.4] {
            s.drawings.begin(at: CGPoint(x: 0.1, y: y), page: 0)
            s.drawings.move(to: CGPoint(x: 0.9, y: y), page: 0)
            s.drawings.end()
        }
        s.handle(.undoDrawing)
        XCTAssertEqual(s.drawings.strokes[0]?.count, 1)
        s.handle(.clearDrawing)
        XCTAssertFalse(s.drawings.hasStrokes)
    }

    func testToolsAndPointerExcludeEachOther() {
        let s = session()
        s.handle(.togglePointer)
        s.handle(.pen)
        XCTAssertEqual(s.drawings.tool, .pen)
        XCTAssertFalse(s.pointer.isEnabled)
        s.handle(.highlighter)
        XCTAssertEqual(s.drawings.tool, .highlighter)
        s.handle(.highlighter)
        XCTAssertNil(s.drawings.tool, "same key again: off")
        s.handle(.eraser)
        s.handle(.togglePointer)
        XCTAssertNil(s.drawings.tool)
        XCTAssertTrue(s.pointer.isEnabled)
    }

    func testEscapeStopsDrawingFirstAndEndKeepsStrokes() {
        let s = session()
        s.handle(.black)
        s.handle(.pen)
        s.drawings.begin(at: CGPoint(x: 0.1, y: 0.1), page: 0)
        s.drawings.move(to: CGPoint(x: 0.3, y: 0.3), page: 0)
        XCTAssertTrue(s.handle(.exit))
        XCTAssertNil(s.drawings.tool)
        XCTAssertNotNil(s.blank, "blank screen still on")
        XCTAssertEqual(s.drawings.strokes[0]?.count, 1, "unfinished stroke kept")
        s.handle(.pen)
        s.end()
        XCTAssertNil(s.drawings.tool)
        XCTAssertTrue(s.drawings.hasStrokes)
    }

    func testNavigationDoesNotTouchDrawings() {
        let s = session()
        s.handle(.pen)
        s.drawings.begin(at: CGPoint(x: 0.5, y: 0.5), page: 0)
        s.drawings.end()
        s.handle(.next)
        XCTAssertEqual(s.drawings.tool, .pen)
        XCTAssertTrue(s.drawings.strokes(on: 1).isEmpty)
        XCTAssertEqual(s.drawings.strokes(on: 0).count, 1)
    }
}

final class PresenterLayoutTests: XCTestCase {
    func testDividerDrag() {
        // 1000 pt wide, current slide at 65 %: dragging 100 pt right → 75 %.
        XCTAssertEqual(PresenterLayout.draggedFraction(start: 0.65, translation: 100, total: 1000), 0.75, accuracy: 1e-9)
        // Current slide on the right: the same drag shrinks it.
        XCTAssertEqual(PresenterLayout.draggedFraction(start: 0.65, translation: 100, total: 1000, inverted: true), 0.55, accuracy: 1e-9)
    }

    func testDividerDragIsClamped() {
        XCTAssertEqual(PresenterLayout.draggedFraction(start: 0.8, translation: 500, total: 1000), PresenterLayout.fractionRange.upperBound)
        XCTAssertEqual(PresenterLayout.draggedFraction(start: 0.3, translation: -500, total: 1000), PresenterLayout.fractionRange.lowerBound)
        XCTAssertEqual(PresenterLayout.draggedFraction(start: 0.5, translation: 10, total: 0), 0.5)
    }

    func testUpcomingPages() {
        XCTAssertEqual(PresenterLayout.upcomingPages(after: 0, showsNext: true, count: 3, pageCount: 10), [2, 3, 4])
        XCTAssertEqual(PresenterLayout.upcomingPages(after: 0, showsNext: false, count: 3, pageCount: 10), [1, 2, 3])
        XCTAssertEqual(PresenterLayout.upcomingPages(after: 7, showsNext: true, count: 3, pageCount: 10), [9])
        // Near and on the last page the strip is empty instead of building an invalid range.
        XCTAssertEqual(PresenterLayout.upcomingPages(after: 8, showsNext: true, count: 3, pageCount: 10), [])
        XCTAssertEqual(PresenterLayout.upcomingPages(after: 9, showsNext: true, count: 3, pageCount: 10), [])
        XCTAssertEqual(PresenterLayout.upcomingPages(after: 9, showsNext: false, count: 3, pageCount: 10), [])
        XCTAssertEqual(PresenterLayout.upcomingPages(after: 0, showsNext: true, count: 0, pageCount: 10), [])
    }

    func testReset() {
        let defaults = UserDefaults(suiteName: "PresenterLayout-\(UUID().uuidString)")!
        defaults.set(0.3, forKey: PresenterLayout.Key.currentFraction)
        defaults.set(true, forKey: PresenterLayout.Key.currentOnRight)
        defaults.set("x", forKey: "unrelated")
        PresenterLayout.reset(defaults)
        XCTAssertNil(defaults.object(forKey: PresenterLayout.Key.currentFraction))
        XCTAssertNil(defaults.object(forKey: PresenterLayout.Key.currentOnRight))
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "x")
    }
}
