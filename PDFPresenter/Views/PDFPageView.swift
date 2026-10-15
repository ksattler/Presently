import AppKit
import PDFKit
import SwiftUI

/// Vector rendering of a page region, aspect-fit on a colored background. Used for the
/// audience view and the large previews — sharp at any size, unlike thumbnails.
struct PDFPageView: NSViewRepresentable {
    let page: PDFPage?
    var region: PageRegion = .full
    var background: NSColor = .black

    func makeNSView(context: Context) -> PDFPageNSView { PDFPageNSView() }

    func updateNSView(_ view: PDFPageNSView, context: Context) {
        if view.page !== page || view.region != region || view.background != background {
            view.page = page
            view.region = region
            view.background = background
            view.needsDisplay = true
        }
    }
}

final class PDFPageNSView: NSView {
    var page: PDFPage?
    var region: PageRegion = .full
    var background: NSColor = .black

    override var isOpaque: Bool { true }
    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        bounds.fill()
        guard let page, let ctx = NSGraphicsContext.current?.cgContext else { return }
        PageRenderer.draw(page, region: region, in: bounds, context: ctx)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
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
        .task(id: "\(index)-\(region)") {
            image = deck.thumbnail(index, region: region, maxPixelSize: pixelSize)
        }
    }
}

/// Speaker notes as Markdown (inline formatting; line breaks kept), as pdfpc renders them.
struct NotesText: View {
    let text: String

    var body: some View {
        if let attributed = try? AttributedString(
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
