import CoreGraphics

/// Part of a slide the audience sees enlarged. Rects are normalized to the slide region
/// (0…1, y down) and keep the slide's aspect ratio — square in normalized coordinates — so the
/// zoomed view fills the same screen area as the whole slide.
enum SlideZoom {
    /// Strongest zoom: a selection is at least 1/8 of the slide wide.
    static let maxFactor: CGFloat = 8
    /// A click instead of a drag zooms this much around the clicked point.
    static let clickFactor: CGFloat = 2

    /// Zoom rect for a drag from `a` to `b`: the dragged rect widened to the slide's aspect
    /// ratio around its center and moved inside the slide. nil when it would cover the whole slide.
    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect? {
        let w = abs(b.x - a.x), h = abs(b.y - a.y)
        let isClick = max(w, h) < 0.02
        let side = isClick ? 1 / clickFactor : min(max(w, h, 1 / maxFactor), 1)
        guard side < 1 else { return nil }
        let center = isClick ? a : CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        return CGRect(x: min(max(center.x - side / 2, 0), 1 - side),
                      y: min(max(center.y - side / 2, 0), 1 - side),
                      width: side, height: side)
    }
}
