import SwiftUI

/// What the audience sees: the current slide (without a Beamer notes half), full screen.
/// While zoomed, a part of the slide fills the slide's area (`session.zoom`).
struct AudienceView: View {
    @ObservedObject var session: PresentationSession
    @ObservedObject private var deck: SlideDeck
    @AppStorage(PageTransition.enabledKey) private var transitionsEnabled = true

    init(session: PresentationSession) {
        self.session = session
        deck = session.deck
    }

    var body: some View {
        let page = deck.page(session.audienceIndex)
        let region = deck.notesLayout.slideRegion
        let zoom = session.audienceZoom
        ZStack {
            PDFPageView(page: page, region: region, pageIndex: session.audienceIndex,
                        transition: transitionsEnabled ? { [deck] in deck.transition(from: $0, to: $1) } : nil,
                        zoom: zoom)
            Group {
                MediaLayer(playback: session.media, page: page, pageIndex: session.audienceIndex,
                           region: region, zoom: zoom)
                LaserPointerLayer(pointer: session.pointer, page: page, region: region,
                                  showsDot: session.audienceIndex == session.currentIndex, zoom: zoom)
                DrawingLayer(drawings: session.drawings, page: page, pageIndex: session.audienceIndex,
                             region: region, zoom: zoom)
            }
            // Zoomed, the layers reach past the slide's area; the letterbox stays black.
            .mask {
                GeometryReader { geo in
                    let slide = page.map { PageRenderer.fittedRect(for: $0, region: region, in: CGRect(origin: .zero, size: geo.size)) } ?? .zero
                    Rectangle().frame(width: slide.width, height: slide.height)
                        .position(x: slide.midX, y: slide.midY)
                }
            }
            if let blank = session.blank {
                (blank == .black ? Color.black : Color.white)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.blank)
        .ignoresSafeArea()
    }
}
