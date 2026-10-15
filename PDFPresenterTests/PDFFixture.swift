import Foundation
import PDFKit
@testable import PDFPresenter

/// Builds small PDFs in code: page labels (Beamer overlays), text annotations, and pages split
/// into a red left and a blue right half (to check regions).
enum PDFFixture {
    struct Page {
        var label: String? = nil
        var note: String? = nil
    }

    static func data(pages: [Page], size: CGSize = CGSize(width: 400, height: 300), rotation: Int = 0) -> Data {
        var objects: [String] = []   // 1-based object numbers = index + 1
        func add(_ s: String) -> Int { objects.append(s); return objects.count }

        let w = Int(size.width), h = Int(size.height)
        let content = "1 0 0 rg 0 0 \(w / 2) \(h) re f 0 0 1 rg \(w / 2) 0 \(w - w / 2) \(h) re f"
        let catalog = add("")   // filled in below
        let pagesObj = add("")
        var kids: [Int] = []
        for page in pages {
            let stream = add("<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream")
            var annots = ""
            if let note = page.note {
                let a = add("<< /Type /Annot /Subtype /Text /Rect [10 10 30 30] /Contents (\(note)) >>")
                annots = " /Annots [\(a) 0 R]"
            }
            kids.append(add("<< /Type /Page /Parent \(pagesObj) 0 R /MediaBox [0 0 \(w) \(h)] /Rotate \(rotation) /Contents \(stream) 0 R\(annots) >>"))
        }
        objects[pagesObj - 1] = "<< /Type /Pages /Kids [\(kids.map { "\($0) 0 R" }.joined(separator: " "))] /Count \(kids.count) >>"
        var labels = ""
        if pages.contains(where: { $0.label != nil }) {
            let nums = pages.enumerated().map { "\($0.offset) << /P (\($0.element.label ?? "\($0.offset + 1)")) >>" }
            labels = " /PageLabels << /Nums [\(nums.joined(separator: " "))] >>"
        }
        objects[catalog - 1] = "<< /Type /Catalog /Pages \(pagesObj) 0 R\(labels) >>"

        var out = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (i, obj) in objects.enumerated() {
            offsets.append(out.utf8.count)
            out += "\(i + 1) 0 obj\n\(obj)\nendobj\n"
        }
        let xref = out.utf8.count
        out += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { out += String(format: "%010d 00000 n \n", o) }
        out += "trailer\n<< /Size \(objects.count + 1) /Root \(catalog) 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(out.utf8)
    }

    static func document(pages: [Page], size: CGSize = CGSize(width: 400, height: 300), rotation: Int = 0) -> PDFDocument {
        PDFDocument(data: data(pages: pages, size: size, rotation: rotation))!
    }

    /// Labels 1, 2, 2, 2, 3: slide 2 has three overlays.
    static let overlayPages: [Page] = ["1", "2", "2", "2", "3"].map { Page(label: $0) }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PDFPresenterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
