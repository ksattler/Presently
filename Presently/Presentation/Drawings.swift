import CoreGraphics
import SwiftUI

/// Freehand annotations on slides during a talk. Points are normalized to the shown slide
/// region (0…1, y down), widths to the slide width — so presenter and audience views of any
/// size show the same drawing. Kept per page for the lifetime of the window, not saved.
///
/// Separate from the session so mouse drags only re-render the drawing layers.
@MainActor
final class Drawings: ObservableObject {
    enum Tool: Equatable { case pen, highlighter, eraser }

    struct Stroke: Equatable {
        var isHighlighter: Bool
        var color: PenColor
        var width: CGFloat
        var points: [CGPoint]
    }

    enum PenColor: String, CaseIterable, Identifiable {
        case red, blue, green, black, white, yellow
        var id: String { rawValue }

        var color: Color {
            switch self {
            case .red:    return Color(red: 0.9, green: 0.1, blue: 0.1)
            case .blue:   return Color(red: 0.1, green: 0.35, blue: 0.95)
            case .green:  return Color(red: 0.1, green: 0.65, blue: 0.2)
            case .black:  return .black
            case .white:  return .white
            case .yellow: return Color(red: 1, green: 0.85, blue: 0)
            }
        }

        var title: String {
            switch self {
            case .red: return String(localized: "Red")
            case .blue: return String(localized: "Blue")
            case .green: return String(localized: "Green")
            case .black: return String(localized: "Black")
            case .white: return String(localized: "White")
            case .yellow: return String(localized: "Yellow")
            }
        }
    }

    /// nil = not drawing (clicks and keys behave as usual).
    @Published var tool: Tool?
    @Published var penColor: PenColor = .red
    @Published var highlighterColor: PenColor = .yellow
    @Published private(set) var strokes: [Int: [Stroke]] = [:]
    /// Stroke being drawn and its page.
    @Published private(set) var current: (page: Int, stroke: Stroke)?

    static let penWidth: CGFloat = 0.004
    static let highlighterWidth: CGFloat = 0.03
    static let eraserRadius: CGFloat = 0.015

    func strokes(on page: Int) -> [Stroke] {
        var all = strokes[page] ?? []
        if let current, current.page == page { all.append(current.stroke) }
        return all
    }

    var hasStrokes: Bool { strokes.values.contains { !$0.isEmpty } }

    // MARK: Input

    func begin(at p: CGPoint, page: Int) {
        switch tool {
        case .pen:
            current = (page, Stroke(isHighlighter: false, color: penColor, width: Self.penWidth, points: [p]))
        case .highlighter:
            current = (page, Stroke(isHighlighter: true, color: highlighterColor, width: Self.highlighterWidth, points: [p]))
        case .eraser:
            erase(at: p, page: page)
        case nil:
            break
        }
    }

    func move(to p: CGPoint, page: Int) {
        if tool == .eraser { erase(at: p, page: page); return }
        guard var c = current, c.page == page else { return }
        // Skip points closer than ~1 px on a 1000 px slide: less data, same look.
        if let last = c.stroke.points.last, hypot(p.x - last.x, p.y - last.y) < 0.001 { return }
        c.stroke.points.append(p)
        current = c
    }

    func end() {
        guard let c = current else { return }
        current = nil
        strokes[c.page, default: []].append(c.stroke)
    }

    // MARK: Editing

    func undo(page: Int) {
        guard var list = strokes[page], !list.isEmpty else { return }
        list.removeLast()
        strokes[page] = list
    }

    func clear(page: Int) {
        strokes[page] = nil
    }

    func erase(at p: CGPoint, page: Int) {
        guard let list = strokes[page] else { return }
        let kept = list.filter { stroke in
            let reach = Self.eraserRadius + stroke.width / 2
            return !Self.stroke(stroke, passesWithin: reach, of: p)
        }
        if kept.count != list.count { strokes[page] = kept }
    }

    nonisolated static func stroke(_ stroke: Stroke, passesWithin distance: CGFloat, of p: CGPoint) -> Bool {
        let pts = stroke.points
        guard let first = pts.first else { return false }
        if pts.count == 1 { return hypot(p.x - first.x, p.y - first.y) <= distance }
        for i in 1..<pts.count where segmentDistance(p, pts[i - 1], pts[i]) <= distance { return true }
        return false
    }

    nonisolated static func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        let t = len2 > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) : 0
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// Smooth path through the points (midpoint quadratic curves), in view coordinates.
    nonisolated static func path(for points: [CGPoint], in slide: CGRect) -> Path {
        let pts = points.map { CGPoint(x: slide.minX + $0.x * slide.width, y: slide.minY + $0.y * slide.height) }
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count == 1 { path.addLine(to: first); return path }
        for i in 1..<pts.count {
            let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
            path.addQuadCurve(to: mid, control: pts[i - 1])
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }
}
