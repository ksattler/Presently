import AVFoundation
import PDFKit
import SwiftUI

/// Videos of `MediaPlayback` over a `PDFPageView` with the same page and region, each in its
/// annotation rectangle. Until a clip is started the PDF's poster underneath stays visible.
/// Clicks pass through (`PresentationSession.click` decides).
struct MediaLayer: View {
    @ObservedObject var playback: MediaPlayback
    let page: PDFPage?
    let pageIndex: Int
    let region: PageRegion
    /// Progress bar under every started clip (presenter view); otherwise only for clips with
    /// `showsControls`.
    var showsProgress = false
    /// Part of the slide shown enlarged (audience view while zoomed).
    var zoom: CGRect = PageRenderer.unzoomed

    var body: some View {
        GeometryReader { geo in
            if playback.pageIndex == pageIndex, let page {
                let slide = PageRenderer.fittedRect(for: page, region: region, in: CGRect(origin: .zero, size: geo.size), zoom: zoom)
                ForEach(playback.items) { item in
                    let n = PDFLinks.normalizedRect(forPageRect: item.clip.bounds, page: page, region: region)
                    let r = CGRect(x: slide.minX + n.minX * slide.width, y: slide.minY + n.minY * slide.height,
                                   width: n.width * slide.width, height: n.height * slide.height)
                    if playback.started.contains(item.id), r.width > 0, r.height > 0 {
                        PlayerView(player: item.player)
                            .overlay(alignment: .bottom) {
                                if showsProgress || item.clip.showsControls {
                                    MediaProgressBar(playback: playback, item: item)
                                }
                            }
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MediaProgressBar: View {
    let playback: MediaPlayback
    let item: MediaPlayback.Item

    var body: some View {
        // Polled, not published: the time changes constantly. The fraction is computed per tick
        // and passed on as a value, so the bar redraws.
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            Bar(fraction: playback.progress(of: item))
        }
    }

    private struct Bar: View {
        let fraction: Double

        var body: some View {
            ZStack(alignment: .leading) {
                Rectangle().fill(.black.opacity(0.5))
                Rectangle().fill(.white.opacity(0.9))
                    .scaleEffect(x: fraction, y: 1, anchor: .leading)
            }
            .frame(height: 4)
        }
    }
}

/// An `AVPlayerLayer` that keeps the video's aspect ratio inside its frame.
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    final class LayerView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspect
            wantsLayer = true
            layer = playerLayer
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> LayerView {
        let v = LayerView()
        v.playerLayer.player = player
        return v
    }

    func updateNSView(_ v: LayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}
