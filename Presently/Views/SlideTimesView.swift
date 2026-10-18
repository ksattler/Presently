import AppKit
import SwiftUI

/// Time per slide of the current or last presentation (menu Presentation → Slide Times…):
/// one row per slide with time and a bar, the total, and a plain-text copy.
struct SlideTimesView: View {
    @ObservedObject var session: PresentationSession
    @ObservedObject var deck: SlideDeck
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = session.timer.elapsed(at: context.date)
            let rows = Self.rows(session: session, deck: deck, elapsed: elapsed)
            let longest = rows.map(\.seconds).max() ?? 0
            VStack(alignment: .leading, spacing: 12) {
                Text("Slide Times").font(.title2.bold())
                if rows.isEmpty {
                    Text("Present the slides once; the time spent on each slide shows up here.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    List(rows, id: \.slide) { row in
                        HStack(spacing: 10) {
                            PageThumbnail(deck: deck, index: row.slide, region: deck.notesLayout.slideRegion,
                                          pixelSize: CGSize(width: 160, height: 120))
                                .aspectRatio(deck.slideAspectRatio, contentMode: .fit)
                                .frame(height: 36)
                            Text(deck.label(row.slide)).monospacedDigit().frame(width: 44, alignment: .leading)
                            GeometryReader { geo in
                                Capsule().fill(Color.accentColor.opacity(0.7))
                                    .frame(width: max(2, geo.size.width * (longest > 0 ? row.seconds / longest : 0)), height: 8)
                                    .frame(maxHeight: .infinity)
                            }
                            Text(PresentationTimer.format(row.seconds))
                                .monospacedDigit()
                                .frame(width: 64, alignment: .trailing)
                        }
                    }
                    .frame(minHeight: 260)
                }
                HStack {
                    Text("Total: \(PresentationTimer.format(session.slideTimes.total(elapsed: elapsed)))")
                        .monospacedDigit()
                    Spacer()
                    Button("Copy as Text") { copy(rows) }.disabled(rows.isEmpty)
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    struct Row {
        let slide: Int
        let seconds: TimeInterval
    }

    /// Slides with recorded time, in page order.
    static func rows(session: PresentationSession, deck: SlideDeck, elapsed: TimeInterval) -> [Row] {
        var result: [Row] = []
        var i = 0
        while i < deck.pageCount {
            let group = deck.overlayGroup(of: i)
            let seconds = session.slideTimes.seconds(of: group.lowerBound, elapsed: elapsed)
            if seconds >= 1 { result.append(Row(slide: group.lowerBound, seconds: seconds)) }
            i = group.upperBound + 1
        }
        return result
    }

    /// "label<TAB>mm:ss" per line, for spreadsheets and notes.
    private func copy(_ rows: [Row]) {
        let text = rows.map { "\(deck.label($0.slide))\t\(PresentationTimer.format($0.seconds))" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
