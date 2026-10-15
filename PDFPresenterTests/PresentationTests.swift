import AppKit
import XCTest
@testable import PDFPresenter

final class PresentKeyActionTests: XCTestCase {
    private func action(_ code: UInt16, _ chars: String? = nil, _ mods: NSEvent.ModifierFlags = []) -> PresentKeyAction? {
        PresentKeyAction(keyCode: code, characters: chars, modifiers: mods)
    }

    func testClickerKeys() {
        XCTAssertEqual(action(121), .next)       // Page Down
        XCTAssertEqual(action(116), .previous)   // Page Up
        XCTAssertEqual(action(36), .confirm)     // Return
        XCTAssertEqual(action(76), .confirm)     // keypad Enter
        XCTAssertEqual(action(51), .previous)    // Backspace
        XCTAssertEqual(action(115), .first)      // Home
        XCTAssertEqual(action(119), .last)       // End
        XCTAssertEqual(action(96), .ignore)      // F5 (start button)
        XCTAssertEqual(action(47, "."), .black)  // "." (blank button)
        XCTAssertEqual(action(11, "b"), .black)
    }

    func testKeyboardKeys() {
        XCTAssertEqual(action(124), .next)
        XCTAssertEqual(action(125), .next)
        XCTAssertEqual(action(49), .next)
        XCTAssertEqual(action(49, nil, .shift), .previous)
        XCTAssertEqual(action(124, nil, .shift), .nextSlide)
        XCTAssertEqual(action(123, nil, .shift), .previousSlide)
        XCTAssertEqual(action(123), .previous)
        XCTAssertEqual(action(126), .previous)
        XCTAssertEqual(action(53), .exit)
        XCTAssertEqual(action(48), .toggleOverview)
        XCTAssertEqual(action(13, "w"), .white)
        XCTAssertEqual(action(35, "p"), .toggleTimer)
        XCTAssertEqual(action(19, "2"), .digit(2))
        XCTAssertNil(action(0, "a"))
    }

    func testMenuShortcutsPassThrough() {
        XCTAssertNil(action(12, "q", .command))
        XCTAssertNil(action(124, nil, .command))
        XCTAssertNil(action(11, "b", .option))
    }
}

final class PresentationTimerTests: XCTestCase {
    func testPauseResumeReset() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var timer = PresentationTimer()
        XCTAssertEqual(timer.elapsed(at: t0), 0)
        timer.start(at: t0)
        XCTAssertEqual(timer.elapsed(at: t0 + 10), 10)
        timer.pause(at: t0 + 10)
        XCTAssertEqual(timer.elapsed(at: t0 + 100), 10)
        timer.toggle(at: t0 + 100)
        XCTAssertEqual(timer.elapsed(at: t0 + 105), 15)
        timer.reset(at: t0 + 105)
        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.elapsed(at: t0 + 107), 2)
    }

    func testFormat() {
        XCTAssertEqual(PresentationTimer.format(0), "00:00")
        XCTAssertEqual(PresentationTimer.format(65.9), "01:05")
        XCTAssertEqual(PresentationTimer.format(3725), "1:02:05")
        XCTAssertEqual(PresentationTimer.format(-30), "−00:30")
    }
}

@MainActor
final class PresentationSessionTests: XCTestCase {
    private func session(_ pages: [PDFFixture.Page] = PDFFixture.overlayPages) -> PresentationSession {
        PresentationSession(deck: SlideDeck(pdf: PDFFixture.document(pages: pages), fileURL: nil))
    }

    func testNavigationStaysInRange() {
        let s = session()
        s.handle(.previous)
        XCTAssertEqual(s.currentIndex, 0)
        s.handle(.last)
        XCTAssertEqual(s.currentIndex, 4)
        XCTAssertTrue(s.isAtEnd)
        s.handle(.next)
        XCTAssertEqual(s.currentIndex, 4)
        s.handle(.first)
        XCTAssertEqual(s.currentIndex, 0)
    }

    func testSlideNavigationSkipsOverlays() {
        let s = session()   // labels 1 2 2 2 3
        s.handle(.nextSlide)
        XCTAssertEqual(s.currentIndex, 1)
        s.handle(.nextSlide)
        XCTAssertEqual(s.currentIndex, 4)
        s.handle(.previousSlide)
        XCTAssertEqual(s.currentIndex, 1)
        s.go(to: 3)
        s.handle(.previousSlide)
        XCTAssertEqual(s.currentIndex, 1, "inside overlays: back to the slide's first overlay")
        s.handle(.previousSlide)
        XCTAssertEqual(s.currentIndex, 0)
    }

    func testTypedPageNumberPrefersLabel() {
        let s = session()
        s.handle(.digit(3))
        XCTAssertEqual(s.pageInput, "3")
        s.handle(.confirm)
        XCTAssertEqual(s.currentIndex, 4, "label 3 is page 5")
        XCTAssertEqual(s.pageInput, "")

        let plain = session([.init(), .init(), .init()])
        plain.handle(.digit(2))
        plain.handle(.confirm)
        XCTAssertEqual(plain.currentIndex, 1)
        plain.handle(.digit(9))
        plain.handle(.confirm)
        XCTAssertEqual(plain.currentIndex, 1, "unknown page: stays")
        plain.handle(.confirm)
        XCTAssertEqual(plain.currentIndex, 2, "Return without input advances")
    }

    func testEscapeClearsStateBeforeEnding() {
        let s = session()
        s.handle(.digit(1))
        s.handle(.toggleOverview)   // clears input
        XCTAssertEqual(s.pageInput, "")
        s.handle(.black)
        XCTAssertTrue(s.handle(.exit))
        XCTAssertFalse(s.showsOverview)
        XCTAssertTrue(s.handle(.exit))
        XCTAssertNil(s.blank)
        XCTAssertFalse(s.handle(.exit), "nothing left: caller ends the presentation")
    }

    func testBlankTogglesAndNavigationUnblanks() {
        let s = session()
        s.handle(.black)
        XCTAssertEqual(s.blank, .black)
        s.handle(.white)
        XCTAssertEqual(s.blank, .white)
        s.handle(.white)
        XCTAssertNil(s.blank)
        s.handle(.black)
        s.handle(.next)
        XCTAssertNil(s.blank)
        XCTAssertEqual(s.currentIndex, 1)
    }

    func testBeginStartsTimerAndEndPausesIt() {
        let s = session()
        var t = Date(timeIntervalSinceReferenceDate: 1000)
        s.now = { t }
        s.begin()
        XCTAssertTrue(s.isPresenting)
        t += 42
        s.end()
        XCTAssertFalse(s.isPresenting)
        XCTAssertEqual(s.timer.elapsed(at: t + 100), 42)
    }
}

@MainActor
final class PresentationScreensTests: XCTestCase {
    func testAutomaticPicksOtherDisplayWhenSeveral() {
        XCTAssertEqual(PresentationScreens.target(available: [1, 2], selected: nil, presenterDisplay: 1), 2)
        XCTAssertEqual(PresentationScreens.target(available: [1, 2, 3], selected: nil, presenterDisplay: 2), 1)
    }

    func testAutomaticWithOneDisplayUsesIt() {
        XCTAssertEqual(PresentationScreens.target(available: [1], selected: nil, presenterDisplay: 1), 1)
        XCTAssertEqual(PresentationScreens.target(available: [1], selected: nil, presenterDisplay: nil), 1)
    }

    func testChosenDisplayWinsAndFallsBackWhenDisconnected() {
        XCTAssertEqual(PresentationScreens.target(available: [1, 2], selected: 1, presenterDisplay: 1), 1)
        XCTAssertEqual(PresentationScreens.target(available: [1, 2], selected: 9, presenterDisplay: 1), 2)
    }

    func testSettingsArePersisted() {
        let defaults = UserDefaults(suiteName: "PresentationScreensTests-\(UUID().uuidString)")!
        let a = PresentationScreens(defaults: defaults)
        XCTAssertNil(a.selectedID)
        XCTAssertFalse(a.windowed)
        XCTAssertTrue(a.presenterFullScreen)
        a.selectedID = 42
        a.windowed = true
        a.presenterFullScreen = false
        let b = PresentationScreens(defaults: defaults)
        XCTAssertEqual(b.selectedID, 42)
        XCTAssertTrue(b.windowed)
        XCTAssertFalse(b.presenterFullScreen)
    }

    func testAudienceWindowCoversTargetScreenAndClosingEndsPresentation() throws {
        let screens = PresentationScreens.shared
        let saved = (screens.windowed, screens.presenterFullScreen)
        defer { screens.windowed = saved.0; screens.presenterFullScreen = saved.1 }
        screens.windowed = false
        screens.presenterFullScreen = false

        let session = PresentationSession(deck: SlideDeck(pdf: PDFFixture.document(pages: [.init(), .init()]), fileURL: nil))
        let controller = PresentationController()
        controller.start(session: session, presenterWindow: nil)
        let window = try XCTUnwrap(controller.window)
        let screen = try XCTUnwrap(screens.targetScreen(presenterWindow: nil))
        XCTAssertEqual(window.frame, screen.frame)
        XCTAssertEqual(window.styleMask, .borderless)
        XCTAssertTrue(session.isPresenting)

        window.close()   // e.g. display disconnected
        XCTAssertFalse(controller.isShowing)
        XCTAssertFalse(session.isPresenting)

        controller.start(session: session, presenterWindow: nil)
        XCTAssertTrue(session.isPresenting)
        controller.stop()
        XCTAssertFalse(controller.isShowing)
        XCTAssertFalse(session.isPresenting)
    }
}
