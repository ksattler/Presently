import PDFKit
import XCTest
@testable import PDFPresenter

@MainActor
final class PDFLinksTests: XCTestCase {
    /// 400 × 300 pages; page 0 has a link to page 2 in its top-left corner (y up: 0…100 × 200…300),
    /// a URL in the bottom-right and a "NextPage" action in the bottom-left.
    private func document(rotation: Int = 0) -> PDFDocument {
        PDFFixture.document(pages: [
            .init(links: [
                .init(rect: CGRect(x: 0, y: 200, width: 100, height: 100), kind: .page(2)),
                .init(rect: CGRect(x: 300, y: 0, width: 100, height: 100), kind: .uri("https://example.org")),
                .init(rect: CGRect(x: 0, y: 0, width: 100, height: 100), kind: .named("NextPage")),
            ]),
            .init(), .init(),
        ], rotation: rotation)
    }

    func testFindsLinksByNormalizedPoint() throws {
        let doc = document()   // pages only hold their document weakly
        let page = try XCTUnwrap(doc.page(at: 0))
        // Normalized coordinates are y down: top-left corner = (small x, small y).
        XCTAssertEqual(PDFLinks.target(atNormalized: CGPoint(x: 0.1, y: 0.1), page: page, region: .full), .page(2))
        XCTAssertEqual(PDFLinks.target(atNormalized: CGPoint(x: 0.9, y: 0.9), page: page, region: .full),
                       .url(URL(string: "https://example.org")!))
        XCTAssertEqual(PDFLinks.target(atNormalized: CGPoint(x: 0.1, y: 0.9), page: page, region: .full), .named(.nextPage))
        XCTAssertNil(PDFLinks.target(atNormalized: CGPoint(x: 0.5, y: 0.5), page: page, region: .full))
        XCTAssertNil(PDFLinks.target(atNormalized: CGPoint(x: -0.1, y: 0.1), page: page, region: .full), "letterbox")
    }

    func testRotatedPage() throws {
        // Rotated 90° clockwise, page corners move on screen: top-left → top-right,
        // bottom-left → top-left, bottom-right → bottom-left, top-right → bottom-right.
        let doc = document(rotation: 90)
        let page = try XCTUnwrap(doc.page(at: 0))
        XCTAssertEqual(PDFLinks.target(atNormalized: CGPoint(x: 0.9, y: 0.1), page: page, region: .full), .page(2))
        XCTAssertEqual(PDFLinks.target(atNormalized: CGPoint(x: 0.1, y: 0.1), page: page, region: .full), .named(.nextPage))
        XCTAssertEqual(PDFLinks.target(atNormalized: CGPoint(x: 0.1, y: 0.9), page: page, region: .full),
                       .url(URL(string: "https://example.org")!))
        XCTAssertNil(PDFLinks.target(atNormalized: CGPoint(x: 0.9, y: 0.9), page: page, region: .full))
    }

    func testRegionOfBeamerNotesPage() throws {
        // Slide in the left half: its top-left corner is the page's top-left corner.
        let doc = document()
        let page = try XCTUnwrap(doc.page(at: 0))
        XCTAssertEqual(PDFLinks.target(atNormalized: CGPoint(x: 0.2, y: 0.1), page: page, region: .leftHalf), .page(2))
        XCTAssertNil(PDFLinks.target(atNormalized: CGPoint(x: 0.6, y: 0.1), page: page, region: .leftHalf))
    }

    func testSessionFollowsLinks() {
        let s = PresentationSession(deck: SlideDeck(pdf: document(), fileURL: nil))
        var opened: [URL] = []
        s.openURL = { opened.append($0) }

        XCTAssertTrue(s.followLink(atNormalized: CGPoint(x: 0.1, y: 0.1), pageIndex: 0))
        XCTAssertEqual(s.currentIndex, 2)
        XCTAssertTrue(s.follow(.named(.goBack)))
        XCTAssertEqual(s.currentIndex, 0)
        XCTAssertFalse(s.follow(.named(.goBack)), "history empty")

        XCTAssertTrue(s.followLink(atNormalized: CGPoint(x: 0.9, y: 0.9), pageIndex: 0))
        XCTAssertEqual(opened, [URL(string: "https://example.org")!])
        XCTAssertEqual(s.currentIndex, 0)

        XCTAssertTrue(s.followLink(atNormalized: CGPoint(x: 0.1, y: 0.9), pageIndex: 0))
        XCTAssertEqual(s.currentIndex, 1)
        XCTAssertFalse(s.followLink(atNormalized: CGPoint(x: 0.5, y: 0.5), pageIndex: 0), "no link: caller advances")
    }

    func testAudienceLinkUnfreezes() {
        let s = PresentationSession(deck: SlideDeck(pdf: document(), fileURL: nil))
        s.handle(.toggleFreeze)
        s.followLink(atNormalized: CGPoint(x: 0.1, y: 0.1), pageIndex: 0)
        XCTAssertEqual(s.frozenIndex, 0, "from the presenter view: stays frozen")
        s.go(to: 0)
        s.followLink(atNormalized: CGPoint(x: 0.1, y: 0.1), pageIndex: 0, unfreeze: true)
        XCTAssertNil(s.frozenIndex)
        XCTAssertEqual(s.audienceIndex, 2)
    }
}

final class SwapScreensTests: XCTestCase {
    func testKey() {
        XCTAssertEqual(PresentKeyAction(keyCode: 1, characters: "s"), .swapScreens)
    }

    func testDisplaysTradePlaces() {
        let t = PresentationController.swapTargets(audience: 2, presenter: 1, available: [1, 2, 3])
        XCTAssertEqual(t?.audience, 1)
        XCTAssertEqual(t?.presenter, 2)
    }

    func testPresenterHiddenBehindAudienceIsBroughtBack() {
        // Both on display 2 (presenter covered by the audience window): presenter moves away.
        let t = PresentationController.swapTargets(audience: 2, presenter: 2, available: [1, 2])
        XCTAssertEqual(t?.audience, 2)
        XCTAssertEqual(t?.presenter, 1)
        let gone = PresentationController.swapTargets(audience: 2, presenter: 9, available: [1, 2])
        XCTAssertEqual(gone?.presenter, 1, "presenter's display disconnected")
        XCTAssertNil(PresentationController.swapTargets(audience: 1, presenter: 1, available: [1]))
    }

    func testFrameKeepsRelativePosition() {
        let laptop = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let projector = CGRect(x: 1000, y: 0, width: 2000, height: 1000)
        let window = CGRect(x: 100, y: 100, width: 400, height: 300)   // center at 30 % / 31.25 %
        let moved = PresentationController.frame(window, movedFrom: laptop, to: projector)
        XCTAssertEqual(moved.size, window.size)
        XCTAssertEqual(moved.midX, 1000 + 0.3 * 2000, accuracy: 0.001)
        XCTAssertEqual(moved.midY, 0.3125 * 1000, accuracy: 0.001)
    }

    func testFrameShrinksAndStaysInside() {
        let big = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        let small = CGRect(x: -1280, y: 100, width: 1280, height: 800)
        let window = CGRect(x: 1500, y: 100, width: 1500, height: 1900)
        let moved = PresentationController.frame(window, movedFrom: big, to: small)
        XCTAssertEqual(moved.size, CGSize(width: 1280, height: 800))
        XCTAssertTrue(small.contains(moved))
    }
}
