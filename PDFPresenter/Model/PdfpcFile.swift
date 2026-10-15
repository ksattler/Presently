import Foundation

/// Speaker notes sidecar in pdfpc's JSON format (`talk.pdf` → `talk.pdfpc`, `pdfpcFormat` 2),
/// so notes are shared with pdfpc and tools that write its files.
///
/// Only `note`s per page and `duration` are interpreted. Every other key — top level and per
/// page — is kept and written back unchanged.
struct PdfpcFile {
    static let fileExtension = "pdfpc"

    /// Page index (0-based, pdfpc's `idx`) → note text (Markdown).
    var notes: [Int: String] = [:]
    /// Planned talk length in minutes; nil = none.
    var durationMinutes: Int?

    private var topLevel: [String: Any] = [:]
    private var pageExtras: [Int: [String: Any]] = [:]

    init() {}

    static func url(forPDF pdfURL: URL) -> URL {
        pdfURL.deletingPathExtension().appendingPathExtension(fileExtension)
    }

    enum ParseError: Error { case notJSON, unsupportedFormat }

    init(data: Data) throws {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ParseError.notJSON   // pdfpc's old INI-like format (before 4.5) isn't supported
        }
        if let format = root["pdfpcFormat"] as? Int, format > 2 { throw ParseError.unsupportedFormat }
        topLevel = root
        topLevel["pages"] = nil
        if let d = root["duration"] as? Int, d > 0 { durationMinutes = d }
        for page in root["pages"] as? [[String: Any]] ?? [] {
            guard let idx = page["idx"] as? Int else { continue }
            if let note = page["note"] as? String, !note.isEmpty { notes[idx] = note }
            var extra = page
            extra["note"] = nil
            pageExtras[idx] = extra
        }
    }

    /// pdfpc's `label` and `overlay` are derived from the PDF's page labels; pages without a
    /// note or other data are left out, as pdfpc does.
    func serialized(pageLabels: [String]) throws -> Data {
        var root = topLevel
        root["pdfpcFormat"] = 2
        if let durationMinutes, durationMinutes > 0 { root["duration"] = durationMinutes } else { root["duration"] = nil }

        var pages: [[String: Any]] = []
        let indices = Set(notes.keys).union(pageExtras.keys).sorted()
        for idx in indices {
            var page = pageExtras[idx] ?? [:]
            let note = notes[idx] ?? ""
            if note.isEmpty && page.keys.allSatisfy({ ["idx", "label", "overlay"].contains($0) }) { continue }
            page["idx"] = idx
            if pageLabels.indices.contains(idx) {
                page["label"] = pageLabels[idx]
                page["overlay"] = Self.overlayIndex(of: idx, labels: pageLabels)
            }
            page["note"] = note.isEmpty ? nil : note
            pages.append(page)
        }
        root["pages"] = pages
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    /// Position of a page within its run of equal labels (Beamer overlays share one label).
    static func overlayIndex(of idx: Int, labels: [String]) -> Int {
        var n = 0, i = idx
        while i > 0, labels[i - 1] == labels[idx] { n += 1; i -= 1 }
        return n
    }
}
