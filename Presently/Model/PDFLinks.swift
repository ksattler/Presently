import PDFKit

/// Where a link annotation in the PDF leads.
enum LinkTarget: Equatable {
    case page(Int)
    case url(URL)
    case named(PDFActionNamedName)
}

/// Finds link annotations under a point of the shown slide.
enum PDFLinks {
    /// Point in PDF page space (what `PDFAnnotation.bounds` uses) for a point normalized to the
    /// shown region (0…1, y down — as views and `LaserPointer` report it).
    static func pagePoint(forNormalized p: CGPoint, page: PDFPage, region: PageRegion) -> CGPoint {
        let r = region.rect(in: CGRect(origin: .zero, size: PageRenderer.displaySize(of: page)))
        let display = CGPoint(x: r.minX + p.x * r.width, y: r.maxY - p.y * r.height)
        // transform(for:) maps page space to the rotated box space `draw(with:to:)` renders.
        return display.applying(page.transform(for: .cropBox).inverted())
    }

    static func target(atNormalized p: CGPoint, page: PDFPage, region: PageRegion) -> LinkTarget? {
        guard (0...1).contains(p.x), (0...1).contains(p.y) else { return nil }
        let point = pagePoint(forNormalized: p, page: page, region: region)
        // Topmost first: later annotations are drawn above earlier ones.
        for annotation in page.annotations.reversed()
        where annotation.type == "Link" && annotation.bounds.contains(point) {
            if let target = target(of: annotation, in: page.document) { return target }
        }
        return nil
    }

    static func target(of annotation: PDFAnnotation, in document: PDFDocument?) -> LinkTarget? {
        let destination = annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination
        if let page = destination?.page, let document {
            let index = document.index(for: page)
            if index != NSNotFound { return .page(index) }
        }
        if let url = annotation.url ?? (annotation.action as? PDFActionURL)?.url { return .url(url) }
        if let named = annotation.action as? PDFActionNamed { return .named(named.name) }
        return nil
    }
}
