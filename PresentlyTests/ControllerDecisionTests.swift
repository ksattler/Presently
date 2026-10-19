import AppKit
import XCTest
@testable import Presently

/// The decisions of `PresentationController`, without windows or displays.
final class ControllerDecisionTests: XCTestCase {
    private typealias C = PresentationController
    private typealias Key = PresentKeyAction.KeyCode

    // MARK: Event routing

    private func key(_ code: UInt16 = 0, _ characters: String? = nil, from source: C.EventSource = .audience,
                     editingText: Bool = false, modifiers: NSEvent.ModifierFlags = []) -> C.EventRoute {
        C.route(.init(kind: .key, source: source, editingText: editingText, keyCode: code,
                      characters: characters, modifiers: modifiers))
    }

    func testClicksOnTheAudienceView() {
        XCTAssertEqual(C.route(.init(kind: .leftClick, source: .audience)), .clickOnAudience)
        XCTAssertEqual(C.route(.init(kind: .rightClick, source: .audience)), .previous)
        XCTAssertEqual(C.route(.init(kind: .leftClick, source: .audience, clickCount: 2)), .passThrough,
                       "the second click of a double click doesn't turn again")
        XCTAssertEqual(C.route(.init(kind: .leftClick, source: .audience, audienceTakesDrags: true)), .passThrough,
                       "drawing or selecting a zoom")
        XCTAssertEqual(C.route(.init(kind: .rightClick, source: .audience, audienceTakesDrags: true)), .previous)
    }

    func testClicksElsewhereAreLeftAlone() {
        for kind in [C.EventInput.Kind.leftClick, .rightClick] {
            XCTAssertEqual(C.route(.init(kind: kind, source: .presenter)), .passThrough, "presenter view handles its own")
            XCTAssertEqual(C.route(.init(kind: kind, source: .other)), .passThrough)
        }
    }

    func testKeysInBothWindows() {
        XCTAssertEqual(key(Key.right), .key(.next))
        XCTAssertEqual(key(Key.right, from: .presenter), .key(.next))
        XCTAssertEqual(key(Key.escape, from: .presenter), .key(.exit))
        XCTAssertEqual(key(1, "s"), .key(.swapScreens))
        XCTAssertEqual(key(Key.right, from: .other), .passThrough, "another document's window")
    }

    func testUnknownKeysAndMenuShortcutsPassThrough() {
        XCTAssertEqual(key(7, "q"), .passThrough)
        XCTAssertEqual(key(Key.right, modifiers: .command), .passThrough)
        XCTAssertEqual(key(12, "q", modifiers: .command), .passThrough, "⌘Q reaches the menu")
    }

    func testTypingInTheNotesKeepsKeysExceptTheClickersPageKeys() {
        XCTAssertEqual(key(Key.right, from: .presenter, editingText: true), .passThrough, "moves the text cursor")
        XCTAssertEqual(key(11, "b", from: .presenter, editingText: true), .passThrough, "typed, not a black screen")
        XCTAssertEqual(key(Key.escape, from: .presenter, editingText: true), .passThrough, "ends editing")
        XCTAssertEqual(key(Key.pageDown, from: .presenter, editingText: true), .key(.next))
        XCTAssertEqual(key(Key.pageUp, from: .presenter, editingText: true), .key(.previous))
    }

    // MARK: Click position

    func testNormalizedClickIsYDown() throws {
        let slide = CGRect(x: 100, y: 50, width: 400, height: 300)
        let topLeft = try XCTUnwrap(C.normalized(CGPoint(x: 100, y: 350), in: slide))
        XCTAssertEqual(topLeft, CGPoint(x: 0, y: 0))
        let p = try XCTUnwrap(C.normalized(CGPoint(x: 400, y: 125), in: slide))
        XCTAssertEqual(p.x, 0.75, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0.75, accuracy: 1e-9)
        XCTAssertEqual(C.normalized(CGPoint(x: 0, y: 0), in: slide)?.x, -0.25, "letterbox: outside 0…1, no link there")
        XCTAssertNil(C.normalized(.zero, in: CGRect(x: 0, y: 0, width: 0, height: 300)))
    }

    // MARK: Displays connected / disconnected

    private func update(_ intended: CGDirectDisplayID, _ presenter: CGDirectDisplayID?, _ available: [CGDirectDisplayID])
        -> C.PlacementUpdate {
        C.placementUpdate(intended: intended, presenter: presenter, available: available)
    }

    func testNothingChangesWhileEverythingIsConnected() {
        XCTAssertEqual(update(2, 1, [1, 2]), .init(placement: .show(2), intended: 2))
    }

    func testDisconnectedProjectorIsRememberedForItsReturn() {
        XCTAssertEqual(update(2, 1, [1]), .init(placement: .hide, intended: 2))
        XCTAssertEqual(update(2, 1, [1, 3]), .init(placement: .show(3), intended: 2),
                       "stands in on a third display, but goes back to 2 when it returns")
        XCTAssertEqual(update(2, 1, [1, 2, 3]), .init(placement: .show(2), intended: 2))
    }

    func testProjectorPluggedInLaterBecomesHome() {
        // Started on the laptop alone: audience and presenter on display 1.
        XCTAssertEqual(update(1, 1, [1]), .init(placement: .show(1), intended: 1))
        XCTAssertEqual(update(1, 1, [1, 2]), .init(placement: .show(2), intended: 2))
    }

    func testAudienceAndPresenterOnOneDisplay() {
        // Only one display left: the audience shows there (the talk starts like that too),
        // the presenter has nowhere to go.
        XCTAssertEqual(update(1, 1, [1]), .init(placement: .show(1), intended: 1))
        XCTAssertEqual(update(2, nil, [2]), .init(placement: .show(2), intended: 2), "presenter window gone")
        XCTAssertEqual(update(5, nil, [1]), .init(placement: .show(1), intended: 5), "stand-in, unknown presenter display")
    }

    func testAudienceNeverCoversThePresenterWhileAnotherDisplayIsFree() {
        // Why the presenter window never has to make way after a display change.
        let ids: [CGDirectDisplayID] = [1, 2, 3, 4]
        for mask in 1..<(1 << ids.count) {
            let available = ids.indices.filter { mask & (1 << $0) != 0 }.map { ids[$0] }
            for intended in ids {
                for presenter in [nil] + ids {
                    guard case .show(let id) = update(intended, presenter, available).placement else { continue }
                    XCTAssertTrue(id != presenter || available.allSatisfy { $0 == id },
                                  "intended \(intended), presenter \(String(describing: presenter)), available \(available)")
                }
            }
        }
    }

    // MARK: Small things

    func testMenuBarHiddenOnlyOnItsDisplay() {
        let saved: NSApplication.PresentationOptions = [.autoHideToolbar]
        XCTAssertEqual(C.presentationOptions(coveringMenuBarDisplay: true, saved: saved), [.autoHideMenuBar, .autoHideDock])
        XCTAssertEqual(C.presentationOptions(coveringMenuBarDisplay: false, saved: saved), saved)
    }

    func testRehearsalWindowIsCenteredAndFits() {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let f = C.rehearsalFrame(in: visible)
        XCTAssertEqual(f.size, CGSize(width: 960, height: 540))
        XCTAssertEqual(f.midX, visible.midX)
        XCTAssertEqual(f.midY, visible.midY)
        let tiny = CGRect(x: 0, y: 0, width: 800, height: 500)
        XCTAssertTrue(tiny.contains(C.rehearsalFrame(in: tiny)))
    }
}
