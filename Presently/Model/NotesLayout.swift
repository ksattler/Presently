import CoreGraphics

/// Part of a page that is shown. Rects are in display space of the page (rotation applied,
/// origin bottom-left, y up), as `PDFPage.draw(with:to:)` produces it.
enum PageRegion: Equatable, Hashable {
    case full, leftHalf, rightHalf, topHalf, bottomHalf

    func rect(in bounds: CGRect) -> CGRect {
        let w = bounds.width / 2, h = bounds.height / 2
        switch self {
        case .full:       return bounds
        case .leftHalf:   return CGRect(x: bounds.minX, y: bounds.minY, width: w, height: bounds.height)
        case .rightHalf:  return CGRect(x: bounds.minX + w, y: bounds.minY, width: w, height: bounds.height)
        case .topHalf:    return CGRect(x: bounds.minX, y: bounds.minY + h, width: bounds.width, height: h)
        case .bottomHalf: return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: h)
        }
    }
}

/// Where a PDF carries its speaker notes on the page itself, like LaTeX Beamer's
/// `\setbeameroption{show notes on second screen=right}`: each page holds the slide and its
/// notes side by side. The audience only sees the slide half.
enum NotesLayout: String, CaseIterable, Identifiable {
    case none, right, left, bottom, top

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:   return String(localized: "None (Whole Page)")
        case .right:  return String(localized: "Notes on the Right")
        case .left:   return String(localized: "Notes on the Left")
        case .bottom: return String(localized: "Notes Below")
        case .top:    return String(localized: "Notes Above")
        }
    }

    var slideRegion: PageRegion {
        switch self {
        case .none:   return .full
        case .right:  return .leftHalf
        case .left:   return .rightHalf
        case .bottom: return .topHalf
        case .top:    return .bottomHalf
        }
    }

    var notesRegion: PageRegion? {
        switch self {
        case .none:   return nil
        case .right:  return .rightHalf
        case .left:   return .leftHalf
        case .bottom: return .bottomHalf
        case .top:    return .topHalf
        }
    }

    /// Whether pages of this size can hold slide + notes in this layout. False e.g. for
    /// "notes right" on ordinary 16:9 slides: the audience would see half a slide.
    func fits(pageSize: CGSize) -> Bool {
        guard pageSize.height > 0 else { return true }
        let aspect = pageSize.width / pageSize.height
        switch self {
        case .none:          return true
        case .right, .left:  return aspect >= 2.3
        case .bottom, .top:  return aspect <= 1.0
        }
    }

    /// Guess from the page size: two 4:3 (8:3) or 16:9 (32:9) slides side by side are far wider
    /// than any normal slide format. Stacked layouts aren't guessed — a 4:6 page is ambiguous.
    static func detect(pageSize: CGSize) -> NotesLayout {
        guard pageSize.height > 0 else { return .none }
        return pageSize.width / pageSize.height >= 2.3 ? .right : .none
    }
}
