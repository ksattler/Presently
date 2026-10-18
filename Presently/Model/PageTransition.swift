import PDFKit

/// A page's transition effect (PDF `/Trans` dictionary, ISO 32000 12.4.4.1), as LaTeX Beamer
/// writes it with `\transdissolve`, `\transwipe`, `\transpush` etc. Played when the audience
/// view moves forward onto that page.
struct PageTransition: Equatable {
    enum Style: String {
        case replace = "R", dissolve = "Dissolve", fade = "Fade", glitter = "Glitter"
        case wipe = "Wipe", push = "Push", cover = "Cover", uncover = "Uncover", fly = "Fly"
        case split = "Split", blinds = "Blinds", box = "Box"
    }

    var style: Style
    /// Seconds (`/D`, default 1).
    var duration: Double = 1
    /// `/Dm`: split and blinds lines are horizontal (`/H`, default) or vertical.
    var horizontal = true
    /// `/M`: split and box move inward (`/I`, default) or outward.
    var inward = true
    /// `/Di`: direction of motion in degrees, counterclockwise from left-to-right (default 0).
    var direction = 0

    /// UserDefaults: play transitions at all.
    static let enabledKey = "pdfTransitionsEnabled"
    static let durationRange: ClosedRange<Double> = 0.05...5

    /// nil: no `/Trans` entry. An unknown style (newer PDF versions) becomes a dissolve.
    static func parse(_ page: PDFPage) -> PageTransition? {
        guard let cg = page.pageRef, let dict = cg.dictionary else { return nil }
        var trans: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dict, "Trans", &trans), let trans else { return nil }

        var t = PageTransition(style: .replace)
        if let s = name(trans, "S") {
            guard let style = Style(rawValue: s) else { return PageTransition(style: .dissolve) }  // unknown: something soft
            t.style = style
        }
        var d: CGPDFReal = 0
        if CGPDFDictionaryGetNumber(trans, "D", &d) { t.duration = min(max(Double(d), durationRange.lowerBound), durationRange.upperBound) }
        if let dm = name(trans, "Dm") { t.horizontal = dm != "V" }
        if let m = name(trans, "M") { t.inward = m != "O" }
        var di: CGPDFInteger = 0
        if CGPDFDictionaryGetInteger(trans, "Di", &di) { t.direction = ((Int(di) % 360) + 360) % 360 }
        return t
    }

    /// pdfpc's transition string (`defaultTransition` in the `.pdfpc` file, as Typst's Touying
    /// and Polylux write it — Typst can't put `/Trans` into the PDF):
    /// `type[:duration[:angle[:alignment[:direction]]]]`, e.g. `push:1:0:horizontal:outward`.
    static func parse(pdfpc s: String) -> PageTransition? {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let type = parts.first?.lowercased(), !type.isEmpty else { return nil }
        let style: Style
        if type == "replace" { style = .replace } else {
            guard let s = Style(rawValue: type.prefix(1).uppercased() + type.dropFirst()) else { return nil }
            style = s
        }
        var t = PageTransition(style: style)
        if parts.count > 1, let d = Double(parts[1]) {
            t.duration = min(max(d, durationRange.lowerBound), durationRange.upperBound)
        }
        if parts.count > 2, let a = Int(parts[2]) { t.direction = ((a % 360) + 360) % 360 }
        if parts.count > 3 { t.horizontal = parts[3].lowercased() != "vertical" }
        if parts.count > 4 { t.inward = parts[4].lowercased() != "outward" }
        return t
    }

    private static func name(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var ptr: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dict, key, &ptr), let ptr else { return nil }
        return String(cString: ptr)
    }

    /// Unit vector of the motion in view space with y up (`/Di` 0 = to the right, 90 = up).
    var motion: CGVector {
        let r = Double(direction) * .pi / 180
        return CGVector(dx: cos(r).rounded(), dy: sin(r).rounded())
    }

    /// Transitions play only when moving forward to the directly following page; going back
    /// or jumping is instant (as in Acrobat and pdfpc).
    static func plays(from old: Int, to new: Int) -> Bool { new == old + 1 }
}
