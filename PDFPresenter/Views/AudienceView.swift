import SwiftUI

/// What the audience sees: the current slide (without a Beamer notes half), full screen.
struct AudienceView: View {
    @ObservedObject var session: PresentationSession
    @ObservedObject private var deck: SlideDeck

    init(session: PresentationSession) {
        self.session = session
        deck = session.deck
    }

    var body: some View {
        ZStack {
            PDFPageView(page: deck.page(session.audienceIndex), region: deck.notesLayout.slideRegion)
            LaserPointerLayer(pointer: session.pointer, page: deck.page(session.audienceIndex),
                              region: deck.notesLayout.slideRegion,
                              showsDot: session.audienceIndex == session.currentIndex)
            if let blank = session.blank {
                (blank == .black ? Color.black : Color.white)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.blank)
        .ignoresSafeArea()
    }
}
