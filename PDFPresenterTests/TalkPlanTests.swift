import PDFKit
import XCTest
@testable import PDFPresenter

final class TalkPlanTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    private func date(_ h: Int, _ m: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: h, minute: m))!
    }

    func testRemaining() {
        XCTAssertNil(TalkLimit.none.remaining(elapsed: 10, now: Date()))
        XCTAssertEqual(TalkLimit.duration(minutes: 20).remaining(elapsed: 300, now: Date()), 900)
        let end = TalkLimit.endTime(hour: 14, minute: 30)
        XCTAssertEqual(end.remaining(elapsed: 0, now: date(14, 0), calendar: calendar), 1800)
        XCTAssertEqual(end.remaining(elapsed: 0, now: date(14, 40), calendar: calendar), -600, "running over")
        XCTAssertEqual(TalkLimit.endTime(hour: 0, minute: 30).remaining(elapsed: 0, now: date(23, 50), calendar: calendar),
                       2400, "end after midnight")
    }

    func testProgressCountsSlidesNotOverlays() {
        let labels = ["1", "2", "2", "2", "3", "4"]
        XCTAssertEqual(TalkPlan.progress(at: 0, labels: labels, endPage: nil), 0)
        XCTAssertEqual(TalkPlan.progress(at: 3, labels: labels, endPage: nil), 0.25, "slide 2 of 4: one done")
        XCTAssertEqual(TalkPlan.progress(at: 4, labels: labels, endPage: nil), 0.5)
        XCTAssertEqual(TalkPlan.progress(at: 4, labels: labels, endPage: 4), 2.0 / 3, "slide 4 is backup")
        XCTAssertNil(TalkPlan.progress(at: 5, labels: labels, endPage: 4))
    }

    func testPace() {
        // 10 of 20 min used, half the slides done: on plan.
        XCTAssertEqual(TalkPlan.paceOffset(elapsed: 600, remaining: 600, progress: 0.5), 0)
        // 5 min used, half done: 5 min ahead.
        XCTAssertEqual(TalkPlan.paceOffset(elapsed: 300, remaining: 900, progress: 0.5), 300)
        XCTAssertEqual(TalkPlan.paceOffset(elapsed: 900, remaining: 300, progress: 0.25), -600)
        XCTAssertEqual(TalkPlan.formatPace(10), "im Plan")
        XCTAssertEqual(TalkPlan.formatPace(300), "05:00 voraus")
        XCTAssertEqual(TalkPlan.formatPace(-90), "01:30 zurück")
    }

    func testPdfpcEndTimeAndEndPage() throws {
        var file = try PdfpcFile(data: Data(#"{"pdfpcFormat": 2, "endTime": "14:30", "pdfpresenterEndPage": 7}"#.utf8))
        XCTAssertEqual(file.endTime, DateComponents(hour: 14, minute: 30))
        XCTAssertEqual(file.endPage, 7)
        file.endTime = DateComponents(hour: 9, minute: 5)
        file.endPage = nil
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: file.serialized(pageLabels: [])) as? [String: Any])
        XCTAssertEqual(root["endTime"] as? String, "09:05")
        XCTAssertNil(root["pdfpresenterEndPage"])
        XCTAssertNil(PdfpcFile.parseTime("25:00"))
    }

    func testLastPageStore() {
        let defaults = UserDefaults(suiteName: "LastPageStore-\(UUID().uuidString)")!
        let store = LastPageStore(defaults: defaults)
        let a = URL(fileURLWithPath: "/tmp/a.pdf")
        XCTAssertNil(store.page(for: a))
        store.set(4, for: a)
        XCTAssertEqual(store.page(for: a), 4)
        for i in 0...LastPageStore.limit {
            store.set(i, for: URL(fileURLWithPath: "/tmp/x\(i).pdf"), now: Date(timeIntervalSinceNow: Double(i + 1)))
        }
        XCTAssertNil(store.page(for: a), "oldest entry dropped")
        XCTAssertEqual(defaults.dictionary(forKey: LastPageStore.key)?.count, LastPageStore.limit)
    }
}

@MainActor
final class TalkSessionTests: XCTestCase {
    private func session(startsOnFirstTurn: Bool) -> PresentationSession {
        let s = PresentationSession(deck: SlideDeck(pdf: PDFFixture.document(pages: PDFFixture.overlayPages), fileURL: nil))
        s.defaults = UserDefaults(suiteName: "TalkSessionTests-\(UUID().uuidString)")!
        s.timerStartsOnFirstTurn = startsOnFirstTurn
        return s
    }

    func testTimerStartsWithFirstPageTurn() {
        let s = session(startsOnFirstTurn: true)
        var t = Date(timeIntervalSinceReferenceDate: 0)
        s.now = { t }
        s.begin()
        XCTAssertTrue(s.timerWaitsForFirstTurn)
        XCTAssertFalse(s.timer.isRunning)
        t += 100   // waiting on the title slide
        s.handle(.next)
        XCTAssertFalse(s.timerWaitsForFirstTurn)
        t += 10
        XCTAssertEqual(s.timer.elapsed(at: t), 10)
    }

    func testTimerStartsImmediatelyWhenSwitchedOff() {
        let s = session(startsOnFirstTurn: false)
        s.begin()
        XCTAssertTrue(s.timer.isRunning)
        XCTAssertFalse(s.timerWaitsForFirstTurn)
    }

    func testStartingTimerByHandStopsWaiting() {
        let s = session(startsOnFirstTurn: true)
        s.begin()
        s.handle(.toggleTimer)
        XCTAssertTrue(s.timer.isRunning)
        XCTAssertFalse(s.timerWaitsForFirstTurn)
    }

    func testEndKeyStopsAtEndOfTalkFirst() {
        let s = session(startsOnFirstTurn: false)
        s.deck.endPage = 3
        s.handle(.last)
        XCTAssertEqual(s.currentIndex, 3)
        XCTAssertFalse(s.deck.isBackup(3))
        s.handle(.last)
        XCTAssertEqual(s.currentIndex, 4)
        XCTAssertTrue(s.deck.isBackup(4))
    }

    func testRemembersPage() throws {
        let dir = try PDFFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("talk.pdf")
        let data = PDFFixture.data(pages: PDFFixture.overlayPages)
        try data.write(to: url)
        let store = LastPageStore(defaults: UserDefaults(suiteName: "RemembersPage-\(UUID().uuidString)")!)

        let first = PresentationSession(deck: try XCTUnwrap(SlideDeck(data: data, fileURL: url)), remembersPage: store)
        XCTAssertEqual(first.currentIndex, 0)
        first.go(to: 3)
        let second = PresentationSession(deck: try XCTUnwrap(SlideDeck(data: data, fileURL: url)), remembersPage: store)
        XCTAssertEqual(second.currentIndex, 3)
    }
}

@MainActor
final class ThumbnailTests: XCTestCase {
    func testRendersInBackgroundAndCaches() async throws {
        let deck = SlideDeck(pdf: PDFFixture.document(pages: [.init(), .init()], size: CGSize(width: 800, height: 300)),
                             fileURL: nil)
        XCTAssertNil(deck.cachedThumbnail(0, region: .leftHalf, maxPixelSize: CGSize(width: 200, height: 200)))
        let image = await deck.thumbnail(0, region: .leftHalf, maxPixelSize: CGSize(width: 200, height: 200))
        XCTAssertEqual(image?.size, CGSize(width: 200, height: 150))
        XCTAssertNotNil(deck.cachedThumbnail(0, region: .leftHalf, maxPixelSize: CGSize(width: 200, height: 200)))
    }

    func testReloadInvalidatesCacheAndClampsEndPage() async throws {
        let deck = SlideDeck(pdf: PDFFixture.document(pages: PDFFixture.overlayPages), fileURL: nil)
        deck.endPage = 4
        _ = await deck.thumbnail(0, region: .full, maxPixelSize: CGSize(width: 100, height: 100))
        deck.reload(pdf: PDFFixture.document(pages: [.init(), .init()]))
        XCTAssertNil(deck.cachedThumbnail(0, region: .full, maxPixelSize: CGSize(width: 100, height: 100)))
        XCTAssertNil(deck.endPage, "end page beyond the new PDF")
        let image = await deck.thumbnail(1, region: .full, maxPixelSize: CGSize(width: 100, height: 100))
        XCTAssertNotNil(image, "new renderer has the new pages")
    }

    func testOverviewUsesSlideFormat() {
        let deck = SlideDeck(pdf: PDFFixture.document(pages: [.init()], size: CGSize(width: 1600, height: 900)), fileURL: nil)
        XCTAssertEqual(deck.slideAspectRatio, 16.0 / 9, accuracy: 0.001)
        let beamer = SlideDeck(pdf: PDFFixture.document(pages: [.init()], size: CGSize(width: 800, height: 300)), fileURL: nil)
        XCTAssertEqual(beamer.notesLayout, .right)
        XCTAssertEqual(beamer.slideAspectRatio, 4.0 / 3, accuracy: 0.001)
    }
}
