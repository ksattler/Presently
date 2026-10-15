import AppKit
import PDFKit
import SwiftUI

/// Shows the drawings of a page over a `PDFPageView` (same page and region) and, while a
/// drawing tool is active, takes mouse drags as input.
struct DrawingLayer: View {
    @ObservedObject var drawings: Drawings
    let page: PDFPage?
    let pageIndex: Int
    let region: PageRegion

    var body: some View {
        GeometryReader { geo in
            let slide = page.map { PageRenderer.fittedRect(for: $0, region: region, in: CGRect(origin: .zero, size: geo.size)) } ?? .zero
            ZStack {
                Canvas { ctx, _ in
                    guard slide.width > 0 else { return }
                    for stroke in drawings.strokes(on: pageIndex) {
                        let path = Drawings.path(for: stroke.points, in: slide)
                        let color = stroke.color.color.opacity(stroke.isHighlighter ? 0.4 : 1)
                        ctx.stroke(path, with: .color(color),
                                   style: StrokeStyle(lineWidth: stroke.width * slide.width,
                                                      lineCap: stroke.isHighlighter ? .butt : .round, lineJoin: .round))
                    }
                }
                .allowsHitTesting(false)

                if drawings.tool != nil, slide.width > 0 {
                    DrawingInput(
                        cursor: drawings.tool == .eraser ? .disappearingItem : .crosshair,
                        onBegin: { drawings.begin(at: normalize($0, slide), page: pageIndex) },
                        onMove: { drawings.move(to: normalize($0, slide), page: pageIndex) },
                        onEnd: { drawings.end() })
                }
            }
        }
    }

    private func normalize(_ p: CGPoint, _ slide: CGRect) -> CGPoint {
        CGPoint(x: min(max((p.x - slide.minX) / slide.width, 0), 1),
                y: min(max((p.y - slide.minY) / slide.height, 0), 1))
    }
}

/// Mouse drags in view coordinates (y down). Takes the first click of an inactive window —
/// the presenter window usually isn't key while the audience window is.
private struct DrawingInput: NSViewRepresentable {
    let cursor: NSCursor
    let onBegin: (CGPoint) -> Void
    let onMove: (CGPoint) -> Void
    let onEnd: () -> Void

    final class InputView: NSView {
        var cursor: NSCursor = .crosshair
        var onBegin: ((CGPoint) -> Void)?
        var onMove: ((CGPoint) -> Void)?
        var onEnd: (() -> Void)?

        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }

        override func mouseDown(with event: NSEvent) { onBegin?(convert(event.locationInWindow, from: nil)) }
        override func mouseDragged(with event: NSEvent) { onMove?(convert(event.locationInWindow, from: nil)) }
        override func mouseUp(with event: NSEvent) { onEnd?() }
    }

    func makeNSView(context: Context) -> InputView {
        let v = InputView()
        updateNSView(v, context: context)
        return v
    }

    func updateNSView(_ v: InputView, context: Context) {
        if v.cursor !== cursor {
            v.cursor = cursor
            v.window?.invalidateCursorRects(for: v)
        }
        v.onBegin = onBegin
        v.onMove = onMove
        v.onEnd = onEnd
    }
}
