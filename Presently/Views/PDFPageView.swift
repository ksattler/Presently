import AppKit
import PDFKit
import SwiftUI

/// Vector rendering of a page region, aspect-fit on a colored background. Used for the
/// audience view and the large previews — sharp at any size, unlike thumbnails.
struct PDFPageView: NSViewRepresentable {
    let page: PDFPage?
    var region: PageRegion = .full
    var background: NSColor = .black
    /// Index of `page`; needed only with `transition`.
    var pageIndex: Int? = nil
    /// Transition to play when the shown page changes from one index to another.
    var transition: ((_ old: Int, _ new: Int) -> PageTransition?)? = nil
    /// Part of the region to show enlarged (normalized, y down).
    var zoom: CGRect = PageRenderer.unzoomed

    func makeNSView(context: Context) -> PDFPageNSView { PDFPageNSView() }

    func updateNSView(_ view: PDFPageNSView, context: Context) {
        if view.page !== page {
            var t: PageTransition?
            if let old = view.pageIndex, let new = pageIndex, view.page != nil { t = transition?(old, new) }
            view.region = region
            view.background = background
            view.zoom = zoom
            view.show(page, index: pageIndex, transition: t)
        } else if view.region != region || view.background != background || view.zoom != zoom {
            view.region = region
            view.background = background
            view.zoom = zoom
            view.needsDisplay = true
        }
    }
}

final class PDFPageNSView: NSView {
    private(set) var page: PDFPage?
    private(set) var pageIndex: Int?
    var region: PageRegion = .full
    var background: NSColor = .black
    var zoom: CGRect = PageRenderer.unzoomed
    /// Layer-hosting subview for transition overlays (the page itself is drawn in `draw`).
    private let overlayView: NSView = {
        let v = NSView()
        v.layer = CALayer()
        v.wantsLayer = true
        v.autoresizingMask = [.width, .height]
        return v
    }()
    private(set) var transitionLayer: CALayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        overlayView.frame = bounds
        addSubview(overlayView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isOpaque: Bool { true }
    override var wantsUpdateLayer: Bool { false }

    /// Shows another page, optionally with a transition from the current one.
    func show(_ newPage: PDFPage?, index: Int?, transition: PageTransition?) {
        finishTransition()
        if let transition, transition.style != .replace, let oldPage = page, let newPage, let host = overlayView.layer,
           bounds.width > 0, bounds.height > 0 {
            let scale = window?.backingScaleFactor ?? 2
            if let old = snapshot(oldPage, scale: scale), let new = snapshot(newPage, scale: scale) {
                transitionLayer = PageTransitionAnimator.play(transition, in: host, size: bounds.size, scale: scale,
                                                              old: old, new: new) { [weak self] in
                    self?.transitionLayer = nil
                }
            }
        }
        page = newPage
        pageIndex = index
        needsDisplay = true
    }

    /// Ends a running transition immediately (next page turn, resize).
    func finishTransition() {
        transitionLayer?.removeFromSuperlayer()
        transitionLayer = nil
    }

    /// The view as it looks with `page`, as a bitmap for the transition layers.
    private func snapshot(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let w = Int((bounds.width * scale).rounded()), h = Int((bounds.height * scale).rounded())
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(background.usingColorSpace(.sRGB)?.cgColor ?? .black)
        ctx.fill(bounds)
        PageRenderer.draw(page, region: region, in: bounds, context: ctx)
        return ctx.makeImage()
    }

    override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        bounds.fill()
        guard let page, let ctx = NSGraphicsContext.current?.cgContext else { return }
        PageRenderer.draw(page, region: region, in: bounds, zoom: zoom, context: ctx)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        finishTransition()
        needsDisplay = true
    }

    // Clicks go to the window (the presentation controller handles them on the audience view).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Cached bitmap thumbnail of a page region.
struct PageThumbnail: View {
    @ObservedObject var deck: SlideDeck
    let index: Int
    var region: PageRegion = .full
    var pixelSize = CGSize(width: 480, height: 360)
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .task(id: "\(deck.revision)-\(index)-\(region)") {
            if let cached = deck.cachedThumbnail(index, region: region, maxPixelSize: pixelSize) {
                image = cached
            } else {
                image = nil
                image = await deck.thumbnail(index, region: region, maxPixelSize: pixelSize)
            }
        }
    }
}

/// Speaker notes as Markdown (inline formatting; line breaks kept), as pdfpc renders them.
struct NotesText: View {
    let text: String
    /// pdfpc's `disableMarkdown`: shown as plain text.
    var markdown = true

    var body: some View {
        if markdown, let attributed = try? AttributedString(
            markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
        } else {
            Text(text)
        }
    }
}

/// Gives SwiftUI access to the hosting window.
struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { window = v.window }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        if v.window !== window { DispatchQueue.main.async { window = v.window } }
    }
}
