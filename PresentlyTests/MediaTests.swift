import AVFoundation
import PDFKit
import XCTest
@testable import Presently

/// Movie annotations and launch links as LaTeX Beamer's `multimedia` package writes them
/// (structure taken from pdfTeX output of `\movie`).
@MainActor
final class MediaTests: XCTestCase {
    static let movie = "<< /Type /Annot /Subtype /Movie /T (mmdefaultlabel1) /Border [0 0 0] /Rect [100 50 300 150] /Movie << /F (clip.mp4) /Poster true >> /A << /Start [128 128] /Duration [384 128] /Mode /Repeat /ShowControls true >> >>"
    static let autostartWidget = "<< /Type /Annot /Subtype /Widget /FT /Btn /Ff 65537 /T (wid@mmdefaultlabel1) /Rect [0 0 0 0] /AA << /PO << /S /Movie /T (mmdefaultlabel1) /Operation /Play >> >> >>"
    static func launch(_ target: String, rect: String = "[0 0 50 50]") -> String {
        "<< /Type /Annot /Subtype /Link /Rect \(rect) /A << /F (\(target)) /S /Launch >> >>"
    }

    private var dir: URL!

    override func setUpWithError() throws {
        dir = try PDFFixture.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func clips(_ page: PDFFixture.Page, baseURL: URL? = nil) throws -> [MediaClip] {
        let doc = PDFFixture.document(pages: [page])
        return PageMedia.clips(on: try XCTUnwrap(doc.page(at: 0)), baseURL: baseURL ?? dir)
    }

    func testParsesBeamerMovie() throws {
        let found = try clips(PDFFixture.Page(annotations: [Self.movie, Self.autostartWidget]))
        XCTAssertEqual(found.count, 1)
        let clip = try XCTUnwrap(found.first)
        XCTAssertEqual(clip.url, dir.appendingPathComponent("clip.mp4").standardizedFileURL)
        XCTAssertEqual(clip.bounds, CGRect(x: 100, y: 50, width: 200, height: 100))
        XCTAssertTrue(clip.autostart)
        XCTAssertTrue(clip.loops)
        XCTAssertTrue(clip.showsControls)
        XCTAssertEqual(clip.start, 1)
        XCTAssertEqual(clip.duration, 3)
    }

    func testMovieWithoutOptions() throws {
        let plain = "<< /Type /Annot /Subtype /Movie /T (m) /Rect [0 0 10 10] /Movie << /F (sub/clip.mov) >> /A << >> >>"
        let clip = try XCTUnwrap(clips(PDFFixture.Page(annotations: [plain])).first)
        XCTAssertEqual(clip.url, dir.appendingPathComponent("sub/clip.mov").standardizedFileURL)
        XCTAssertFalse(clip.autostart)
        XCTAssertFalse(clip.loops)
        XCTAssertFalse(clip.showsControls)
        XCTAssertEqual(clip.start, 0)
        XCTAssertNil(clip.duration)
    }

    func testAutostartFromPageOpenAction() throws {
        // dvips/pdfmark variant: the play action sits in the page's /AA /O.
        let page = PDFFixture.Page(annotations: [Self.movie],
                                   entries: "/AA << /O << /S /Movie /T (mmdefaultlabel1) /Operation /Play >> >>")
        XCTAssertEqual(try clips(page).first?.autostart, true)
    }

    func testLaunchLinks() throws {
        let page = PDFFixture.Page(annotations: [
            Self.launch("clip.mp4"),                                   // \movie[externalviewer]
            Self.launch("clip.m4v?autostart&loop&start=5&stop=12&noprogress"),
            Self.launch("slides.pdf"),                                 // not a video
            "<< /Type /Annot /Subtype /Link /Rect [0 0 9 9] /A << /S /URI /URI (run:talk.mov?autostart) >> >>",
            "<< /Type /Annot /Subtype /Link /Rect [0 0 9 9] /A << /S /URI /URI (https://example.org/a.mp4) >> >>",
        ])
        let found = try clips(page)
        XCTAssertEqual(found.map(\.url.lastPathComponent), ["clip.mp4", "clip.m4v", "talk.mov"])
        XCTAssertFalse(found[0].autostart)
        XCTAssertTrue(found[1].autostart)
        XCTAssertTrue(found[1].loops)
        XCTAssertEqual(found[1].start, 5)
        XCTAssertEqual(found[1].duration, 7)
        XCTAssertTrue(found[2].autostart)
        XCTAssertEqual(found[0].bounds, CGRect(x: 0, y: 0, width: 50, height: 50))
    }

    func testRelativePathsNeedTheDocumentFolder() throws {
        let doc = PDFFixture.document(pages: [PDFFixture.Page(annotations: [Self.movie, Self.launch("/abs/clip.mp4")])])
        let found = PageMedia.clips(on: try XCTUnwrap(doc.page(at: 0)), baseURL: nil)
        XCTAssertEqual(found.map(\.url.path), ["/abs/clip.mp4"])
    }

    func testRunTargetOptions() {
        XCTAssertNil(PageMedia.parseRunTarget("notes.txt?autostart"))
        XCTAssertNil(PageMedia.parseRunTarget("https://example.org"))
        let t = PageMedia.parseRunTarget("a.mp4?start=3&stop=2")
        XCTAssertEqual(t?.path, "a.mp4")
        XCTAssertEqual(t?.options.start, 3)
        XCTAssertNil(t?.options.duration, "stop before start is ignored")
        XCTAssertEqual(PageMedia.parseRunTarget("a.mp4")?.options.autostart, false)
    }

    func testNormalizedRectInvertsPagePoint() throws {
        for (rotation, region) in [(0, PageRegion.full), (90, .full), (0, .leftHalf), (270, .topHalf)] {
            let doc = PDFFixture.document(pages: [PDFFixture.Page()], size: CGSize(width: 400, height: 300), rotation: rotation)
            let page = try XCTUnwrap(doc.page(at: 0))
            let pageRect = CGRect(x: 40, y: 30, width: 80, height: 60)
            let n = PDFLinks.normalizedRect(forPageRect: pageRect, page: page, region: region)
            let center = PDFLinks.pagePoint(forNormalized: CGPoint(x: n.midX, y: n.midY), page: page, region: region)
            XCTAssertEqual(center.x, pageRect.midX, accuracy: 1e-6, "rotation \(rotation), \(region)")
            XCTAssertEqual(center.y, pageRect.midY, accuracy: 1e-6, "rotation \(rotation), \(region)")
        }
    }

    // MARK: Playback

    private func session() -> PresentationSession {
        let pages = [PDFFixture.Page(annotations: [Self.movie, Self.autostartWidget]), PDFFixture.Page(),
                     PDFFixture.Page(annotations: [Self.launch("clip.mp4", rect: "[0 0 400 300]")])]
        let deck = SlideDeck(pdf: PDFFixture.document(pages: pages), fileURL: dir.appendingPathComponent("talk.pdf"))
        let s = PresentationSession(deck: deck)
        s.defaults = UserDefaults(suiteName: "MediaTests-\(UUID().uuidString)")!
        return s
    }

    func testLoadsOnlyWhilePresentingAndFollowsTheAudiencePage() {
        let s = session()
        XCTAssertNil(s.media.pageIndex, "browsing: nothing loaded")
        s.begin()
        XCTAssertEqual(s.media.pageIndex, 0)
        XCTAssertEqual(s.media.items.count, 1)
        XCTAssertEqual(s.media.playing, [0], "autostart")

        // Frozen audience: the video stays on the frozen page.
        s.handle(.toggleFreeze)
        s.go(to: 1)
        XCTAssertEqual(s.media.pageIndex, 0)
        XCTAssertEqual(s.media.playing, [0])
        s.handle(.toggleFreeze)
        XCTAssertEqual(s.media.pageIndex, 1)
        XCTAssertTrue(s.media.items.isEmpty)

        s.go(to: 2)
        XCTAssertEqual(s.media.items.count, 1)
        XCTAssertTrue(s.media.playing.isEmpty, "no autostart")
        s.end()
        XCTAssertNil(s.media.pageIndex)
        XCTAssertTrue(s.media.items.isEmpty)
    }

    func testClickPlaysAndPausesInsteadOfAdvancing() {
        let s = session()
        s.begin()
        // Movie rect 100…300 × 50…150 on a 400×300 page; y down in normalized coordinates.
        let inside = CGPoint(x: 0.5, y: 0.6)
        XCTAssertTrue(s.click(atNormalized: inside, pageIndex: 0))
        XCTAssertTrue(s.media.playing.isEmpty, "paused")
        XCTAssertTrue(s.click(atNormalized: inside, pageIndex: 0))
        XCTAssertEqual(s.media.playing, [0])
        XCTAssertFalse(s.click(atNormalized: CGPoint(x: 0.05, y: 0.05), pageIndex: 0), "outside: caller advances")
        XCTAssertFalse(s.click(atNormalized: inside, pageIndex: 1), "another page than the audience's")
        XCTAssertEqual(s.currentIndex, 0)
    }

    func testEndOfClipLoopsOrStops() throws {
        let playback = MediaPlayback()
        var once = MediaClip(url: dir.appendingPathComponent("a.mp4"), bounds: CGRect(x: 0, y: 0, width: 10, height: 10))
        once.autostart = true
        var looping = once
        looping.loops = true
        playback.load([once, looping], page: 0)
        XCTAssertEqual(playback.playing, [0, 1])

        for item in playback.items {
            NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: item.player.currentItem)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(playback.playing, [1], "the looping clip keeps playing")
        XCTAssertEqual(playback.started, [0, 1], "the finished clip keeps its last frame")
        XCTAssertEqual(playback.clip(atPagePoint: CGPoint(x: 5, y: 5)), 1, "topmost")
    }
}
