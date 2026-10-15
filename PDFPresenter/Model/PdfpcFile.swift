import Foundation

/// Speaker notes sidecar in pdfpc's JSON format (`talk.pdf` → `talk.pdfpc`, `pdfpcFormat` 2),
/// so notes are shared with pdfpc and tools that write its files.
///
/// Interpreted: `note`s per page, `duration` (minutes), `endTime` ("HH:MM") and our own
/// `pdfpresenterEndPage` (last page of the talk; later pages are backup). Every other key — top
/// level and per page — is kept and written back unchanged.
struct PdfpcFile {
    static let fileExtension = "pdfpc"

    /// Page index (0-based, pdfpc's `idx`) → note text (Markdown).
    var notes: [Int: String] = [:]
    /// Planned talk length in minutes; nil = none.
    var durationMinutes: Int?
    /// Planned end as wall-clock time; nil = none. pdfpc uses either this or `duration`.
    var endTime: DateComponents?
    /// Index of the talk's last page; nil = all pages. Own key: pdfpc's `endSlide` counts
    /// differently (user slides), so it is left alone.
    var endPage: Int?

    static let endPageKey = "pdfpresenterEndPage"

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
        if let t = root["endTime"] as? String { endTime = Self.parseTime(t) }
        if let e = root[Self.endPageKey] as? Int, e >= 0 { endPage = e }
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
        root["endTime"] = endTime.flatMap(Self.formatTime)
        root[Self.endPageKey] = endPage

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

    /// "HH:MM" (pdfpc's end-time format).
    static func parseTime(_ s: String) -> DateComponents? {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return DateComponents(hour: parts[0], minute: parts[1])
    }

    static func formatTime(_ c: DateComponents) -> String? {
        guard let h = c.hour, let m = c.minute else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    /// Position of a page within its run of equal labels (Beamer overlays share one label).
    static func overlayIndex(of idx: Int, labels: [String]) -> Int {
        var n = 0, i = idx
        while i > 0, labels[i - 1] == labels[idx] { n += 1; i -= 1 }
        return n
    }
}
