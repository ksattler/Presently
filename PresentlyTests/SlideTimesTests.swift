import XCTest
@testable import Presently

@MainActor
final class SlideTimesTests: XCTestCase {
    func testAccumulatesVisitsAndTheRunningOne() {
        var t = SlideTimes()
        XCTAssertTrue(t.isEmpty)
        t.enter(0, elapsed: 0)
        t.enter(4, elapsed: 10)
        t.enter(0, elapsed: 25)
        XCTAssertEqual(t.seconds(of: 0, elapsed: 30), 15, "10 + the running 5")
        XCTAssertEqual(t.seconds(of: 4, elapsed: 30), 15)
        t.enter(nil, elapsed: 30)
        XCTAssertEqual(t.seconds, [0: 15, 4: 15])
        XCTAssertEqual(t.total(elapsed: 99), 30, "nothing running after the end")
        XCTAssertFalse(t.isEmpty)
    }

    private var clock = Date(timeIntervalSinceReferenceDate: 0)

    private func session() -> PresentationSession {
        let s = PresentationSession(deck: SlideDeck(pdf: PDFFixture.document(pages: PDFFixture.overlayPages), fileURL: nil))
        s.defaults = UserDefaults(suiteName: "SlideTimesTests-\(UUID().uuidString)")!
        s.timerStartsOnFirstTurn = false
        s.now = { [unowned self] in self.clock }
        return s
    }

    private func at(_ seconds: TimeInterval) { clock = Date(timeIntervalSinceReferenceDate: seconds) }

    func testSessionCountsTalkTimePerSlide() {
        let s = session()   // labels 1, 2, 2, 2, 3
        s.begin()
        at(10); s.handle(.next)          // slide 2, first overlay
        at(25); s.handle(.next)          // same slide
        at(40); s.handle(.nextSlide)     // slide 3
        at(50); s.handle(.toggleTimer)   // pause: doesn't count
        at(80); s.handle(.toggleTimer)
        at(90); s.end()
        XCTAssertEqual(s.slideTimes.seconds, [0: 10, 1: 30, 4: 20], "overlays add up; the pause is left out")
        XCTAssertEqual(s.slideTimes.total(elapsed: 0), 60)
        XCTAssertEqual(SlideTimesView.rows(session: s, deck: s.deck, elapsed: 0).map(\.slide), [0, 1, 4])

        at(100); s.begin()
        XCTAssertEqual(s.slideTimes.total(elapsed: s.timer.elapsed(at: clock)), 0, "a new presentation starts over")
    }

    func testFrozenAudienceSlideCountsAndResetTimerStartsOver() {
        let s = session()
        s.begin()
        s.handle(.toggleFreeze)
        at(10); s.handle(.next)          // presenter browses; the audience still sees slide 1
        at(20); s.handle(.toggleFreeze)  // now the audience sees slide 2
        at(30)
        XCTAssertEqual(s.slideTimes.seconds(of: 0, elapsed: s.timer.elapsed(at: clock)), 20)
        XCTAssertEqual(s.slideTimes.seconds(of: 1, elapsed: s.timer.elapsed(at: clock)), 10)

        s.handle(.resetTimer)
        at(35)
        XCTAssertEqual(s.slideTimes.seconds(of: 0, elapsed: s.timer.elapsed(at: clock)), 0)
        XCTAssertEqual(s.slideTimes.seconds(of: 1, elapsed: s.timer.elapsed(at: clock)), 5, "counting again from the reset")
    }

    func testWaitingForTheFirstTurnDoesntCount() {
        let s = session()
        s.timerStartsOnFirstTurn = true
        s.begin()
        at(60); s.handle(.next)          // the timer starts now
        at(70); s.end()
        XCTAssertEqual(s.slideTimes.seconds[0] ?? 0, 0, "waiting on the title slide")
        XCTAssertEqual(s.slideTimes.seconds[1], 10)
    }
}
