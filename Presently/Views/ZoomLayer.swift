import PDFKit
import SwiftUI

/// Over the presenter's current slide and the (unzoomed) audience slide: while selecting, takes
/// a drag (or click) and shows the dragged rectangle. In the presenter view it also marks the
/// selection mode (frame and hint) and, while zoomed, dims what the audience doesn't see. Only
/// when the audience shows the current page (not frozen elsewhere).
struct ZoomLayer: View {
    @ObservedObject var session: PresentationSession
    let page: PDFPage?
    let region: PageRegion
    /// Audience view: selection only, nothing else is shown there.
    var isAudience = false
    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let slide = page.map { PageRenderer.fittedRect(for: $0, region: region, in: CGRect(origin: .zero, size: geo.size)) } ?? .zero
            if slide.width > 0, session.audienceIndex == session.currentIndex {
                ZStack(alignment: .topLeading) {
                    if let zoom = session.zoom, !isAudience {
                        outline(denormalize(zoom, slide), in: slide)
                    }
                    if session.isSelectingZoom, !isAudience, dragStart == nil {
                        selectionHint(slide)
                    }
                    if session.isSelectingZoom {
                        if let a = dragStart, let b = dragEnd {
                            let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
                            Rectangle()
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                .frame(width: r.width * slide.width, height: r.height * slide.height)
                                .offset(x: slide.minX + r.minX * slide.width, y: slide.minY + r.minY * slide.height)
                                .allowsHitTesting(false)
                        }
                        DragInput(cursor: .crosshair,
                                  onBegin: { dragStart = normalize($0, slide); dragEnd = dragStart },
                                  onMove: { dragEnd = normalize($0, slide) },
                                  onEnd: {
                                      if let a = dragStart, let b = dragEnd { session.zoom(from: a, to: b) }
                                      dragStart = nil
                                      dragEnd = nil
                                  })
                    }
                }
            }
        }
    }

    /// Selection mode: the slide framed, with a hint at its top.
    private func selectionHint(_ slide: CGRect) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
            Text("Drag a rectangle to zoom in for the audience, or click for 2× · Esc cancels")
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor, in: Capsule())
                .padding(.top, 8)
        }
        .frame(width: slide.width, height: slide.height)
        .offset(x: slide.minX, y: slide.minY)
        .allowsHitTesting(false)
    }

    /// The part the audience sees, framed; the rest of the slide dimmed.
    private func outline(_ r: CGRect, in slide: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.addRect(slide)
                p.addRect(r)
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
        }
        .allowsHitTesting(false)
    }

    private func denormalize(_ r: CGRect, _ slide: CGRect) -> CGRect {
        CGRect(x: slide.minX + r.minX * slide.width, y: slide.minY + r.minY * slide.height,
               width: r.width * slide.width, height: r.height * slide.height)
    }

    private func normalize(_ p: CGPoint, _ slide: CGRect) -> CGPoint {
        CGPoint(x: min(max((p.x - slide.minX) / slide.width, 0), 1),
                y: min(max((p.y - slide.minY) / slide.height, 0), 1))
    }
}
