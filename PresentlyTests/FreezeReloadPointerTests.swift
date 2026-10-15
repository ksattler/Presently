import PDFKit
import XCTest
@testable import Presently

@MainActor
final class FreezeTests: XCTestCase {
    private func session() -> PresentationSession {
        PresentationSession(deck: SlideDeck(pdf: PDFFixture.document(pages: PDFFixture.overlayPages), fileURL: nil))
    }

    func testKeys() {
        XCTAssertEqual(PresentKeyAction(keyCode: 3, characters: "f"), .toggleFreeze)
        XCTAssertEqual(PresentKeyAction(keyCode: 37, characters: "l"), .togglePointer)
    }

    func testAudienceKeepsPageWhileFrozen() {
        let s = session()
        s.go(to: 1)
        s.handle(.toggleFreeze)
        XCTAssertEqual(s.frozenIndex, 1)
        s.handle(.next)
        s.handle(.next)
        XCTAssertEqual(s.currentIndex, 3)
        XCTAssertEqual(s.audienceIndex, 1)
        s.handle(.toggleFreeze)
        XCTAssertEqual(s.audienceIndex, 3, "unfreezing shows the presenter's page")
    }

    func testEscapeUnfreezesBeforeEnding() {
        let s = session()
        s.handle(.toggleFreeze)
        s.handle(.black)
        XCTAssertTrue(s.handle(.exit))
        XCTAssertNil(s.blank)
        XCTAssertNotNil(s.frozenIndex)
        XCTAssertTrue(s.handle(.exit))
        XCTAssertNil(s.frozenIndex)
        XCTAssertFalse(s.handle(.exit))
    }

    func testBeginAndEndClearFreezeAndPointer() {
        let s = session()
        s.handle(.toggleFreeze)
        s.handle(.togglePointer)
        XCTAssertTrue(s.pointer.isEnabled)
        s.end()
        XCTAssertNil(s.frozenIndex)
        XCTAssertFalse(s.pointer.isEnabled)
        s.handle(.toggleFreeze)
        s.begin()
        XCTAssertNil(s.frozenIndex)
    }
}

@MainActor
final class LaserPointerTests: XCTestCase {
    func testMovesOnlyWhenEnabledAndInsideSlide() {
        let p = LaserPointer()
        p.move(to: CGPoint(x: 0.5, y: 0.5))
        XCTAssertNil(p.position, "off: ignored")
        p.isEnabled = true
        p.move(to: CGPoint(x: 0.25, y: 0.75))
        XCTAssertEqual(p.position, CGPoint(x: 0.25, y: 0.75))
        p.move(to: CGPoint(x: 1.2, y: 0.5))
        XCTAssertNil(p.position, "outside the slide (letterbox)")
        p.move(to: CGPoint(x: 0.1, y: 0.1))
        p.isEnabled = false
        XCTAssertNil(p.position)
    }
}

@MainActor
final class ReloadTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = try PDFFixture.temporaryDirectory()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testReloadKeepsPageNotesAndClampsIndices() throws {
        let url = dir.appendingPathComponent("talk.pdf")
        try PDFFixture.data(pages: PDFFixture.overlayPages).write(to: url)
        let deck = try XCTUnwrap(SlideDeck(data: Data(contentsOf: url), fileURL: url))
        let s = PresentationSession(deck: deck)
        deck.setNote("Bleibt", for: 0)
        s.go(to: 2)
        let oldPage = deck.page(2)

        try PDFFixture.data(pages: [.init(label: "a"), .init(label: "b"), .init(label: "c"), .init(label: "d")]).write(to: url)
        s.reloadFromDisk()
        XCTAssertNil(s.reloadError)
        XCTAssertEqual(deck.pageCount, 4)
        XCTAssertEqual(deck.labels, ["a", "b", "c", "d"])
        XCTAssertEqual(deck.revision, 1)
        XCTAssertEqual(s.currentIndex, 2, "stays on the same page")
        XCTAssertFalse(deck.page(2) === oldPage)
        XCTAssertEqual(deck.note(for: 0), "Bleibt")

        s.go(to: 3)
        s.handle(.toggleFreeze)
        try PDFFixture.data(pages: [.init(), .init()]).write(to: url)
        s.reloadFromDisk()
        XCTAssertEqual(s.currentIndex, 1, "shorter PDF: clamped")
        XCTAssertEqual(s.frozenIndex, 1)
    }

    func testBrokenFileKeepsOldVersion() throws {
        let url = dir.appendingPathComponent("talk.pdf")
        try PDFFixture.data(pages: PDFFixture.overlayPages).write(to: url)
        let deck = try XCTUnwrap(SlideDeck(data: Data(contentsOf: url), fileURL: url))
        let s = PresentationSession(deck: deck)
        try Data("%PDF-1.7\nhalf written".utf8).write(to: url)
        s.reloadFromDisk()
        XCTAssertNotNil(s.reloadError)
        XCTAssertEqual(deck.pageCount, 5)
        XCTAssertEqual(deck.revision, 0)
    }

    func testWatcherSeesInPlaceWritesAndAtomicReplacement() async throws {
        let url = dir.appendingPathComponent("talk.pdf")
        try PDFFixture.data(pages: [.init()]).write(to: url)
        var count = 0
        let watcher = FileWatcher(url: url, debounce: .milliseconds(100)) { count += 1 }
        defer { watcher.stop() }

        // In place, in several chunks (like pdflatex): one notification.
        let handle = try FileHandle(forWritingTo: url)
        for _ in 0..<3 { try handle.write(contentsOf: Data("x".utf8)); try await Task.sleep(for: .milliseconds(20)) }
        try handle.close()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(count, 1)

        // Atomic save (write temp file, rename over): watched again afterwards.
        try PDFFixture.data(pages: [.init(), .init()]).write(to: url, options: .atomic)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(count, 2)
        try PDFFixture.data(pages: [.init()]).write(to: url, options: .atomic)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(count, 3, "still watching the new file")
    }
}
