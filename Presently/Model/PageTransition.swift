import PDFKit

/// A page's transition effect (PDF `/Trans` dictionary, ISO 32000 12.4.4.1), as LaTeX Beamer
/// writes it with `\transdissolve`, `\transwipe`, `\transpush` etc. Played when the audience
/// view moves forward onto that page.
struct PageTransition: Equatable {
    /// The 12 PDF styles (raw value = `/S` name) and our own ones, which neither PDF nor pdfpc know.
    enum Style: String, CaseIterable, Identifiable {
        case replace = "R", dissolve = "Dissolve", fade = "Fade", glitter = "Glitter"
        case wipe = "Wipe", push = "Push", cover = "Cover", uncover = "Uncover", fly = "Fly"
        case split = "Split", blinds = "Blinds", box = "Box"
        case fadeThroughBlack = "FadeThroughBlack", zoom = "Zoom", flip = "Flip", cube = "Cube"

        var id: Self { self }

        /// Part of the PDF spec — and of pdfpc, whose transition names are the same.
        var isStandard: Bool { ![.fadeThroughBlack, .zoom, .flip, .cube].contains(self) }

        /// Name in pdfpc's transition string (ours use the same scheme).
        var pdfpcName: String { self == .replace ? "replace" : rawValue.lowercased() }

        /// Which of the parameters the style uses.
        var hasDirection: Bool { [.wipe, .push, .cover, .uncover, .fly, .glitter, .flip, .cube].contains(self) }
        var hasLineOrientation: Bool { [.split, .blinds].contains(self) }
        var hasInOut: Bool { [.split, .box, .zoom].contains(self) }

        var title: String {
            switch self {
            case .replace:          String(localized: "No Transition")
            case .dissolve:         String(localized: "Dissolve")
            case .fade:             String(localized: "Fade")
            case .glitter:          String(localized: "Glitter")
            case .wipe:             String(localized: "Wipe")
            case .push:             String(localized: "Push")
            case .cover:            String(localized: "Cover")
            case .uncover:          String(localized: "Uncover")
            case .fly:              String(localized: "Fly In")
            case .split:            String(localized: "Split")
            case .blinds:           String(localized: "Blinds")
            case .box:              String(localized: "Box")
            case .fadeThroughBlack: String(localized: "Fade through Black")
            case .zoom:             String(localized: "Zoom")
            case .flip:             String(localized: "Flip")
            case .cube:             String(localized: "Cube")
            }
        }
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

    /// UserDefaults: play transitions at all (from the PDF and the document's own).
    static let enabledKey = "pdfTransitionsEnabled"
    static let durationRange: ClosedRange<Double> = 0.05...5

    /// nil: no `/Trans` entry. An unknown style (newer PDF versions) becomes a dissolve.
    static func parse(_ page: PDFPage) -> PageTransition? {
        guard let cg = page.pageRef, let dict = cg.dictionary else { return nil }
        var trans: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dict, "Trans", &trans), let trans else { return nil }

        var t = PageTransition(style: .replace)
        if let s = name(trans, "S") {
            guard let style = Style(rawValue: s), style.isStandard else { return PageTransition(style: .dissolve) }  // unknown: something soft
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
    /// Also reads our own styles in the same scheme (`presentlyTransition`).
    static func parse(pdfpc s: String) -> PageTransition? {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let type = parts.first?.lowercased(), !type.isEmpty,
              let style = Style.allCases.first(where: { $0.pdfpcName == type })
        else { return nil }
        var t = PageTransition(style: style)
        if parts.count > 1, let d = Double(parts[1]) {
            t.duration = min(max(d, durationRange.lowerBound), durationRange.upperBound)
        }
        if parts.count > 2, let a = Int(parts[2]) { t.direction = ((a % 360) + 360) % 360 }
        if parts.count > 3 { t.horizontal = parts[3].lowercased() != "vertical" }
        if parts.count > 4 { t.inward = parts[4].lowercased() != "outward" }
        return t
    }

    /// The pdfpc transition string, complete so that pdfpc reads it as meant.
    var pdfpcString: String {
        let d = duration == duration.rounded() ? String(Int(duration)) : String(duration)
        return [style.pdfpcName, d, String(direction), horizontal ? "horizontal" : "vertical", inward ? "inward" : "outward"]
            .joined(separator: ":")
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
