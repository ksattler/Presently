import PDFKit
import UniformTypeIdentifiers

/// A video (or sound) on a page, played inside its rectangle on the slide.
struct MediaClip: Equatable {
    var url: URL
    /// Rectangle in PDF page space (like `PDFAnnotation.bounds`).
    var bounds: CGRect
    var autostart = false
    var loops = false
    /// Seconds into the file where playback begins.
    var start: Double = 0
    /// Seconds played from `start`; nil = to the end.
    var duration: Double?
    /// Shows a progress bar in the audience view too (the presenter view always has one).
    var showsControls = false
}

/// Reads the videos of a page, as LaTeX Beamer's `multimedia` package writes them
/// (CoreGraphics; PDFKit exposes neither movie annotations nor launch actions):
/// - `\movie`: a `/Movie` annotation, file in `/Movie /F`, options in `/A` (`/Mode`, `/Start`,
///   `/Duration`, `/ShowControls`); `autostart` adds a `/S /Movie /Operation /Play` action that
///   names the movie by `/T` — in a widget's `/AA /PO` (pdfTeX) or the page's `/AA /O` (dvips).
/// - `\movie[externalviewer]` and pdfpc-style `\href{run:clip.mp4?autostart&loop}`: a link with
///   a launch action (or a `run:` URI) to a video file; options in the query.
/// Files are external, relative to the PDF. Formats AVFoundation can't play just don't start.
enum PageMedia {
    static func clips(on page: PDFPage, baseURL: URL?) -> [MediaClip] {
        guard let pageDict = page.pageRef?.dictionary else { return [] }
        var annots: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(pageDict, "Annots", &annots), let annots else { return [] }

        var movies: [(title: String?, clip: MediaClip)] = []
        var autostartTitles = Set<String>()
        var links: [MediaClip] = []
        if let title = playTitle(inAdditionalActions: pageDict, key: "O") { autostartTitles.insert(title) }

        for i in 0..<CGPDFArrayGetCount(annots) {
            var annot: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(annots, i, &annot), let annot else { continue }
            switch name(annot, "Subtype") {
            case "Movie":
                if let clip = movieClip(annot, baseURL: baseURL) { movies.append((string(annot, "T"), clip)) }
            case "Widget":
                if let title = playTitle(inAdditionalActions: annot, key: "PO") { autostartTitles.insert(title) }
            case "Link":
                if let clip = launchClip(annot, baseURL: baseURL) { links.append(clip) }
            default:
                break
            }
        }
        return movies.map { movie in
            var clip = movie.clip
            if let title = movie.title, autostartTitles.contains(title) { clip.autostart = true }
            return clip
        } + links
    }

    // MARK: Movie annotations

    private static func movieClip(_ annot: CGPDFDictionaryRef, baseURL: URL?) -> MediaClip? {
        var movie: CGPDFDictionaryRef?
        guard let bounds = rect(annot, "Rect"), CGPDFDictionaryGetDictionary(annot, "Movie", &movie), let movie,
              let path = fileSpec(movie, "F"), let url = resolve(path, baseURL: baseURL)
        else { return nil }
        var clip = MediaClip(url: url, bounds: bounds)
        var activation: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(annot, "A", &activation), let activation {
            if let mode = name(activation, "Mode") { clip.loops = mode == "Repeat" || mode == "Palindrome" }
            var controls: CGPDFBoolean = 0
            if CGPDFDictionaryGetBoolean(activation, "ShowControls", &controls) { clip.showsControls = controls != 0 }
            clip.start = time(activation, "Start") ?? 0
            clip.duration = time(activation, "Duration")
        }
        return clip
    }

    /// Title of the movie a `/S /Movie /Operation /Play` action in `/AA /<key>` starts.
    private static func playTitle(inAdditionalActions dict: CGPDFDictionaryRef, key: String) -> String? {
        var aa: CGPDFDictionaryRef?, action: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dict, "AA", &aa), let aa,
              CGPDFDictionaryGetDictionary(aa, key, &action), let action,
              name(action, "S") == "Movie", (name(action, "Operation") ?? "Play") == "Play"
        else { return nil }
        return string(action, "T")
    }

    /// PDF time (ISO 32000 13.4.4): seconds, or `[time timescale]`.
    private static func time(_ dict: CGPDFDictionaryRef, _ key: String) -> Double? {
        var number: CGPDFReal = 0
        if CGPDFDictionaryGetNumber(dict, key, &number) { return Double(number) }
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dict, key, &array), let array, CGPDFArrayGetCount(array) == 2 else { return nil }
        var t: CGPDFReal = 0, scale: CGPDFReal = 0
        guard CGPDFArrayGetNumber(array, 0, &t), CGPDFArrayGetNumber(array, 1, &scale), scale > 0 else { return nil }
        return Double(t / scale)
    }

    // MARK: Launch links

    private static func launchClip(_ annot: CGPDFDictionaryRef, baseURL: URL?) -> MediaClip? {
        var action: CGPDFDictionaryRef?
        guard let bounds = rect(annot, "Rect"), CGPDFDictionaryGetDictionary(annot, "A", &action), let action
        else { return nil }
        let target: String?
        switch name(action, "S") {
        case "Launch": target = fileSpec(action, "F")
        case "URI":    target = string(action, "URI").flatMap { $0.hasPrefix("run:") ? String($0.dropFirst(4)) : nil }
        default:       target = nil
        }
        guard let target, let parsed = parseRunTarget(target), let url = resolve(parsed.path, baseURL: baseURL)
        else { return nil }
        var clip = parsed.options
        clip.url = url
        clip.bounds = bounds
        return clip
    }

    /// pdfpc's `run:` syntax: `clip.mp4?autostart&loop&start=5&stop=12` (`noprogress` is ignored —
    /// the audience view shows no progress anyway). nil if the path isn't a video or sound file.
    static func parseRunTarget(_ target: String) -> (path: String, options: MediaClip)? {
        let parts = target.split(separator: "?", maxSplits: 1).map(String.init)
        guard let path = parts.first, isMedia(path) else { return nil }
        var clip = MediaClip(url: URL(fileURLWithPath: "/"), bounds: .zero)
        var stop: Double?
        for option in parts.count > 1 ? parts[1].split(separator: "&") : [] {
            let kv = option.split(separator: "=", maxSplits: 1).map(String.init)
            switch (kv[0], kv.count > 1 ? Double(kv[1]) : nil) {
            case ("autostart", _): clip.autostart = true
            case ("loop", _):      clip.loops = true
            case ("start", let s?): clip.start = max(0, s)
            case ("stop", let s?):  stop = s
            default: break
            }
        }
        if let stop, stop > clip.start { clip.duration = stop - clip.start }
        return (path, clip)
    }

    // MARK: Helpers

    static func isMedia(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension
        return UTType(filenameExtension: ext)?.conforms(to: .audiovisualContent) ?? false
    }

    /// Relative paths are relative to the PDF's folder.
    static func resolve(_ path: String, baseURL: URL?) -> URL? {
        let path = path.hasPrefix("file:") ? (URL(string: path)?.path ?? String(path.dropFirst(5))) : path
        guard isMedia(path) else { return nil }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return baseURL.map { $0.appendingPathComponent(path).standardizedFileURL }
    }

    /// A file specification: a string, or a dictionary with `/UF` or `/F`.
    private static func fileSpec(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        if let s = string(dict, key) { return s }
        var spec: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dict, key, &spec), let spec else { return nil }
        return string(spec, "UF") ?? string(spec, "F")
    }

    private static func rect(_ dict: CGPDFDictionaryRef, _ key: String) -> CGRect? {
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dict, key, &array), let array, CGPDFArrayGetCount(array) == 4 else { return nil }
        var v = [CGPDFReal](repeating: 0, count: 4)
        for i in 0..<4 { guard CGPDFArrayGetNumber(array, i, &v[i]) else { return nil } }
        let r = CGRect(x: v[0], y: v[1], width: v[2] - v[0], height: v[3] - v[1]).standardized
        return r.width > 0 && r.height > 0 ? r : nil
    }

    private static func name(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var ptr: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dict, key, &ptr), let ptr else { return nil }
        return String(cString: ptr)
    }

    private static func string(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var s: CGPDFStringRef?
        guard CGPDFDictionaryGetString(dict, key, &s), let s else { return nil }
        return CGPDFStringCopyTextString(s) as String?
    }
}
