import SwiftUI

/// What the audience sees: the current slide (without a Beamer notes half), full screen.
struct AudienceView: View {
    @ObservedObject var session: PresentationSession
    @ObservedObject private var deck: SlideDeck
    @AppStorage(PageTransition.enabledKey) private var transitionsEnabled = true

    init(session: PresentationSession) {
        self.session = session
        deck = session.deck
    }

    var body: some View {
        ZStack {
            PDFPageView(page: deck.page(session.audienceIndex), region: deck.notesLayout.slideRegion,
                        pageIndex: session.audienceIndex,
                        transition: transitionsEnabled ? { [deck] in deck.transition(from: $0, to: $1) } : nil)
            LaserPointerLayer(pointer: session.pointer, page: deck.page(session.audienceIndex),
                              region: deck.notesLayout.slideRegion,
                              showsDot: session.audienceIndex == session.currentIndex)
            DrawingLayer(drawings: session.drawings, page: deck.page(session.audienceIndex),
                         pageIndex: session.audienceIndex, region: deck.notesLayout.slideRegion)
            if let blank = session.blank {
                (blank == .black ? Color.black : Color.white)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.blank)
        .ignoresSafeArea()
    }
}
