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
        case .none:   return "Keine (ganze Seite)"
        case .right:  return "Notizen rechts"
        case .left:   return "Notizen links"
        case .bottom: return "Notizen unten"
        case .top:    return "Notizen oben"
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

    /// Guess from the page size: two 4:3 (8:3) or 16:9 (32:9) slides side by side are far wider
    /// than any normal slide format. Stacked layouts aren't guessed — a 4:6 page is ambiguous.
    static func detect(pageSize: CGSize) -> NotesLayout {
        guard pageSize.height > 0 else { return .none }
        return pageSize.width / pageSize.height >= 2.3 ? .right : .none
    }
}
