import AppKit

/// The standard About panel (icon, name, version, copyright from `NSHumanReadableCopyright`)
/// with the presentation keys as credits.
enum AboutPanel {
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Keys and what they do, in the order of `PresentKeyAction`.
    static var shortcuts: [(keys: String, action: String)] {
        [
            (String(localized: "→ ↓ Page Down Space"), String(localized: "Next page")),
            (String(localized: "← ↑ Page Up ⌫"), String(localized: "Previous page")),
            (String(localized: "⇧ + arrow"), String(localized: "Skip overlays")),
            (String(localized: "Home / End"), String(localized: "First / last page")),
            (String(localized: "Number ⏎"), String(localized: "Go to page")),
            (String(localized: "Tab / O"), String(localized: "Overview")),
            ("B / W", String(localized: "Black / white screen")),
            ("F", String(localized: "Freeze audience view")),
            ("L", String(localized: "Laser pointer")),
            ("C", String(localized: "Spotlight")),
            ("M", String(localized: "Zoom in / whole slide")),
            ("S", String(localized: "Swap displays")),
            ("D / H / E", String(localized: "Pen / highlighter / eraser")),
            ("Z / X", String(localized: "Undo / clear drawing")),
            ("P / R", String(localized: "Start or pause / reset timer")),
            ("Esc", String(localized: "Close, then end")),
            ("⌘⏎ / F5", String(localized: "Start presentation")),
        ]
    }

    static var credits: NSAttributedString {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let rows = shortcuts
        // Right edge of the key column: the widest key, so the descriptions get the rest.
        let keyColumn = rows.map { ($0.keys as NSString).size(withAttributes: [.font: font]).width }.max()!.rounded(.up) + 4
        let gap: CGFloat = 10
        let rowStyle = NSMutableParagraphStyle()
        rowStyle.tabStops = [NSTextTab(textAlignment: .right, location: keyColumn),
                            NSTextTab(textAlignment: .left, location: keyColumn + gap)]
        rowStyle.headIndent = keyColumn + gap   // wrapped descriptions stay in their column
        let heading = NSMutableParagraphStyle()
        heading.alignment = .center
        heading.paragraphSpacing = 6

        let text = NSMutableAttributedString(
            string: String(localized: "Keyboard Shortcuts") + "\n",
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize),
                         .foregroundColor: NSColor.labelColor, .paragraphStyle: heading])
        for (i, row) in rows.enumerated() {
            text.append(NSAttributedString(string: "\t\(row.keys)\t", attributes: [
                .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: rowStyle]))
            text.append(NSAttributedString(string: row.action + (i < rows.count - 1 ? "\n" : ""), attributes: [
                .font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: rowStyle]))
        }
        return text
    }
}
