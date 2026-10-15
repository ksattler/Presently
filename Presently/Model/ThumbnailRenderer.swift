import CoreGraphics
import PDFKit

/// Renders thumbnails off the main thread. Has its own `PDFDocument` built from the same data:
/// PDFKit objects must not be shared across threads, so the main-thread document (used for
/// the vector views) is never touched here.
actor ThumbnailRenderer {
    private let pdf: PDFDocument?

    init(data: Data?) {
        pdf = data.flatMap(PDFDocument.init(data:))
        if let pdf { _ = SlideDeck.extractAnnotationNotes(from: pdf) }   // hide note icons here too
    }

    /// nil if cancelled (scrolled out of view) before it was this request's turn.
    func image(index: Int, region: PageRegion, maxPixelSize: CGSize) -> CGImage? {
        guard !Task.isCancelled, let page = pdf?.page(at: index) else { return nil }
        return PageRenderer.cgImage(of: page, region: region, maxPixelSize: maxPixelSize)
    }
}
