import AppKit
import PDFKit

/// Draws (a region of) a PDF page as vector content, aspect-fit and centered.
enum PageRenderer {
    /// Page size as displayed: crop box with the page rotation applied.
    static func displaySize(of page: PDFPage) -> CGSize {
        let b = page.bounds(for: .cropBox)
        return page.rotation % 180 == 0 ? b.size : CGSize(width: b.height, height: b.width)
    }

    /// Aspect-fit rect of `region` inside `rect`.
    static func fittedRect(for page: PDFPage, region: PageRegion, in rect: CGRect) -> CGRect {
        let src = region.rect(in: CGRect(origin: .zero, size: displaySize(of: page)))
        guard src.width > 0, src.height > 0 else { return .zero }
        let scale = min(rect.width / src.width, rect.height / src.height)
        let size = CGSize(width: src.width * scale, height: src.height * scale)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// `context` must be y-up (unflipped). Pages get a white backdrop, like on paper — PDFs
    /// without an explicit background would otherwise show the view's color through.
    static func draw(_ page: PDFPage, region: PageRegion, in rect: CGRect, context: CGContext) {
        let dest = fittedRect(for: page, region: region, in: rect)
        guard dest.width > 0 else { return }
        let src = region.rect(in: CGRect(origin: .zero, size: displaySize(of: page)))
        let scale = dest.width / src.width
        context.saveGState()
        context.clip(to: dest)
        context.setFillColor(.white)
        context.fill(dest)
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
