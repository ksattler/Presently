import AppKit
import PDFKit
import SwiftUI

/// Transparent layer over a `PDFPageView` with the same page and region. Tracks the mouse
/// for the laser pointer (in slide coordinates, so presenter and audience views of different
/// sizes agree) and draws the pointer dot. Hides the system cursor over the slide while the
/// pointer is on.
struct LaserPointerLayer: View {
    @ObservedObject var pointer: LaserPointer
    let page: PDFPage?
    let region: PageRegion
    /// False when this view shows another page than the pointer refers to (frozen audience).
    var showsDot = true
    @State private var hidesCursor = false

    var body: some View {
        GeometryReader { geo in
            let slide = page.map { PageRenderer.fittedRect(for: $0, region: region, in: CGRect(origin: .zero, size: geo.size)) } ?? .zero
            ZStack(alignment: .topLeading) {
                Color.clear
                if showsDot, pointer.isEnabled, let p = pointer.position, slide.width > 0 {
                    let d = max(12, slide.width * 0.018)
                    Circle()
                        .fill(RadialGradient(colors: [.white, Color(red: 1, green: 0.15, blue: 0.1), Color(red: 1, green: 0, blue: 0).opacity(0)],
                                             center: .center, startRadius: 0, endRadius: d / 2))
                        .frame(width: d, height: d)
                        .shadow(color: .red.opacity(0.8), radius: d / 3)
                        .position(x: slide.minX + p.x * slide.width, y: slide.minY + p.y * slide.height)
                        .allowsHitTesting(false)
                }
            }
            .background(MouseTracker { location in
                guard pointer.isEnabled, slide.width > 0, slide.height > 0 else { return }
                if let location {
                    pointer.move(to: CGPoint(x: (location.x - slide.minX) / slide.width,
                                             y: (location.y - slide.minY) / slide.height))
                    setCursorHidden(pointer.position != nil)
                } else {
                    pointer.move(to: nil)
                    setCursorHidden(false)
                }
            })
        }
        .onChange(of: pointer.isEnabled) { if !pointer.isEnabled { setCursorHidden(false) } }
        .onDisappear { setCursorHidden(false) }
    }

    /// NSCursor.hide/unhide are counted; keep them balanced.
    private func setCursorHidden(_ hidden: Bool) {
        guard hidden != hidesCursor else { return }
        hidesCursor = hidden
        hidden ? NSCursor.hide() : NSCursor.unhide()
    }
}

/// Reports the mouse position (y down, view coordinates; nil when it leaves) — also in windows
/// that aren't key: during a presentation the audience window is key, but the pointer is
/// usually driven from the presenter window. SwiftUI's hover tracking only works in the key
/// window. Clicks pass through.
private struct MouseTracker: NSViewRepresentable {
    let onMove: (CGPoint?) -> Void

    final class TrackingView: NSView {
        var onMove: ((CGPoint?) -> Void)?
        override var isFlipped: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self))
        }

        override func mouseMoved(with event: NSEvent) { onMove?(convert(event.locationInWindow, from: nil)) }
        override func mouseEntered(with event: NSEvent) { onMove?(convert(event.locationInWindow, from: nil)) }
        override func mouseExited(with event: NSEvent) { onMove?(nil) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> TrackingView {
        let v = TrackingView()
        v.onMove = onMove
        return v
    }

    func updateNSView(_ v: TrackingView, context: Context) { v.onMove = onMove }
}
