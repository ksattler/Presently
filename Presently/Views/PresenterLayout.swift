import AppKit
import SwiftUI

/// Presenter view arrangement, stored in UserDefaults (same for all documents).
enum PresenterLayout {
    enum Key {
        static let currentFraction = "presenterCurrentFraction"
        static let nextFraction = "presenterNextFraction"
        static let currentOnRight = "presenterCurrentOnRight"
        static let showsNext = "presenterShowsNext"
        static let showsNotes = "presenterShowsNotes"
        static let upcomingCount = "presenterUpcomingCount"
        static let notesFontSize = "presenterNotesFontSize"
    }

    enum Default {
        static let currentFraction = 0.65   // width share of the current slide
        static let nextFraction = 0.4       // height share of the next slide in the side column
        static let upcomingCount = 4
        static let notesFontSize = 22.0
    }

    static let fractionRange: ClosedRange<Double> = 0.25...0.85
    static let upcomingRange: ClosedRange<Int> = 0...8
    static let notesFontSizeRange: ClosedRange<Double> = 12...72

    /// Divider drag: share at drag start plus the moved distance relative to the total length.
    /// `inverted` when the measured part is on the far side (current slide on the right).
    static func draggedFraction(start: Double, translation: CGFloat, total: CGFloat, inverted: Bool = false) -> Double {
        guard total > 0 else { return start }
        let delta = Double(translation / total) * (inverted ? -1 : 1)
        return min(max(start + delta, fractionRange.lowerBound), fractionRange.upperBound)
    }

    /// Pages of the upcoming strip: up to `count` pages after the current one (and after the
    /// next one, if that is shown), without skipped pages. Empty near the end.
    static func upcomingPages(after index: Int, showsNext: Bool, count: Int, pageCount: Int,
                              isHidden: (Int) -> Bool = { _ in false }) -> [Int] {
        guard index + 1 < pageCount else { return [] }
        let shown = (index + 1..<pageCount).filter { !isHidden($0) }
        return Array(shown.dropFirst(showsNext ? 1 : 0).prefix(max(count, 0)))
    }

    static func reset(_ defaults: UserDefaults = .standard) {
        for key in [Key.currentFraction, Key.nextFraction, Key.currentOnRight, Key.showsNext, Key.showsNotes, Key.upcomingCount] {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Draggable divider between two panes; reports the translation since the drag started.
struct SplitHandle: View {
    enum Axis { case horizontal, vertical }   // direction of movement
    let axis: Axis
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(Color.white.opacity(hovering ? 0.5 : 0.18))
                .frame(width: axis == .horizontal ? 4 : 44, height: axis == .horizontal ? 44 : 4)
        }
        .frame(width: axis == .horizontal ? 14 : nil, height: axis == .vertical ? 14 : nil)
        .contentShape(Rectangle())
        .onHover { inside in
            guard inside != hovering else { return }
            hovering = inside
            if inside {
                (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear { if hovering { NSCursor.pop(); hovering = false } }
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { onChanged(axis == .horizontal ? $0.translation.width : $0.translation.height) }
            .onEnded { _ in onEnded() })
        .help("Drag to change the layout")
    }
}

/// "View" menu of the presenter view.
struct PresenterLayoutMenu: View {
    @AppStorage(PresenterLayout.Key.currentOnRight) private var currentOnRight = false
    @AppStorage(PresenterLayout.Key.showsNext) private var showsNext = true
    @AppStorage(PresenterLayout.Key.showsNotes) private var showsNotes = true
    @AppStorage(PresenterLayout.Key.upcomingCount) private var upcomingCount = PresenterLayout.Default.upcomingCount

    var body: some View {
        Menu {
            Toggle("Current Slide on the Right", isOn: $currentOnRight)
            Divider()
            Toggle("Next Slide", isOn: $showsNext)
            Toggle("Notes", isOn: $showsNotes)
            Picker("Upcoming Pages", selection: $upcomingCount) {
                Text("Off").tag(0)
                ForEach(1...PresenterLayout.upcomingRange.upperBound, id: \.self) { Text($0, format: .number).tag($0) }
            }
            Divider()
            Button("Reset Layout") { PresenterLayout.reset() }
        } label: {
            Label("View", systemImage: "rectangle.split.3x1")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Layout of the presenter view")
    }
}
