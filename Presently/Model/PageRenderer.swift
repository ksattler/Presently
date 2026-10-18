import AppKit
import PDFKit

/// Draws (a region of) a PDF page as vector content, aspect-fit and centered.
enum PageRenderer {
    /// Page size as displayed: crop box with the page rotation applied.
    static func displaySize(of page: PDFPage) -> CGSize {
        let b = page.bounds(for: .cropBox)
        return page.rotation % 180 == 0 ? b.size : CGSize(width: b.height, height: b.width)
    }

    /// The whole slide (normalized 0…1, y down) — no zoom.
    static let unzoomed = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Rect of the whole `region` such that its part `zoom` (normalized to the region, y down)
    /// is aspect-fit and centered in `rect`. Unzoomed: the aspect-fit rect of the region. With a
    /// zoom it is larger than `rect` and reaches outside. `yUp`: `rect` lives in a y-up space
    /// (AppKit drawing, window coordinates); otherwise y down (SwiftUI).
    static func fittedRect(for page: PDFPage, region: PageRegion, in rect: CGRect,
                           zoom: CGRect = unzoomed, yUp: Bool = false) -> CGRect {
        let src = region.rect(in: CGRect(origin: .zero, size: displaySize(of: page)))
        guard src.width > 0, src.height > 0, zoom.width > 0, zoom.height > 0 else { return .zero }
        let scale = min(rect.width / (src.width * zoom.width), rect.height / (src.height * zoom.height))
        let size = CGSize(width: src.width * scale, height: src.height * scale)
        let x = rect.midX - zoom.midX * size.width
        // The zoomed part's center sits at rect's center; zoom.midY counts from the top.
        let y = yUp ? rect.midY + zoom.midY * size.height - size.height : rect.midY - zoom.midY * size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// `context` must be y-up (unflipped). Pages get a white backdrop, like on paper — PDFs
    /// without an explicit background would otherwise show the view's color through.
    /// `zoom`: only that part of the region (normalized, y down), enlarged to fill `rect`.
    static func draw(_ page: PDFPage, region: PageRegion, in rect: CGRect, zoom: CGRect = unzoomed,
                     context: CGContext) {
        let dest = fittedRect(for: page, region: region, in: rect, zoom: zoom, yUp: true)
        guard dest.width > 0 else { return }
        let src = region.rect(in: CGRect(origin: .zero, size: displaySize(of: page)))
        let scale = dest.width / src.width
        // Visible: the zoomed part (y up: zoom.maxY counts from the top).
        let visible = CGRect(x: dest.minX + zoom.minX * dest.width, y: dest.maxY - zoom.maxY * dest.height,
                             width: zoom.width * dest.width, height: zoom.height * dest.height)
        context.saveGState()
        context.clip(to: visible)
        context.setFillColor(.white)
        context.fill(visible)
        context.translateBy(x: dest.minX - src.minX * scale, y: dest.minY - src.minY * scale)
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .high
        // draw(with:to:) moves the crop box to the origin and applies the page rotation.
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
    }

    /// Bitmap of a page region, for thumbnails and lists.
    static func image(of page: PDFPage, region: PageRegion, maxPixelSize: CGSize) -> NSImage? {
        cgImage(of: page, region: region, maxPixelSize: maxPixelSize)
            .map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }

    static func cgImage(of page: PDFPage, region: PageRegion, maxPixelSize: CGSize) -> CGImage? {
        let fitted = fittedRect(for: page, region: region, in: CGRect(origin: .zero, size: maxPixelSize))
        let w = Int(fitted.width.rounded()), h = Int(fitted.height.rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        draw(page, region: region, in: CGRect(x: 0, y: 0, width: w, height: h), context: ctx)
        return ctx.makeImage()
    }
}
