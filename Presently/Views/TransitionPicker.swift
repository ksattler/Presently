import SwiftUI

/// Toolbar button of the document window: the document's transition (`SlideDeck.defaultTransition`),
/// played where a new slide begins. Saved in the pdfpc sidecar.
struct TransitionButton: View {
    @ObservedObject var deck: SlideDeck
    let currentIndex: Int
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            Label("Transition", systemImage: "rectangle.on.rectangle")
        }
        .help("Transition between slides")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            TransitionPicker(deck: deck, currentIndex: currentIndex)
        }
    }
}

struct TransitionPicker: View {
    @ObservedObject var deck: SlideDeck
    let currentIndex: Int
    @AppStorage(PageTransition.enabledKey) private var enabled = true
    @State private var showsSecondPage = false

    static let directions: [(angle: Int, symbol: String, title: LocalizedStringKey)] = [
        (0, "arrow.right", "Right"), (90, "arrow.up", "Up"), (180, "arrow.left", "Left"), (270, "arrow.down", "Down"),
    ]

    private var transition: Binding<PageTransition> {
        Binding(get: { deck.defaultTransition ?? PageTransition(style: .replace) },
                set: { deck.defaultTransition = $0.style == .replace ? nil : $0 })
    }

    /// Pages the preview switches between: the current one and the next slide (or the first).
    private var previewPages: (Int, Int)? {
        guard let other = deck.nextSlideStart(after: currentIndex) ?? (currentIndex > 0 ? 0 : nil) else { return nil }
        return (currentIndex, other)
    }

    var body: some View {
        let t = transition.wrappedValue
        Form {
            Picker("Transition", selection: transition.style) {
                Text(PageTransition.Style.replace.title).tag(PageTransition.Style.replace)
                Divider()
                ForEach(PageTransition.Style.allCases.filter { $0 != .replace }) { Text($0.title).tag($0) }
            }
            if t.style != .replace {
                Slider(value: transition.duration, in: 0.2...3, step: 0.1) {
                    Text("Duration: \(t.duration.formatted(.number.precision(.fractionLength(1)))) s").monospacedDigit()
                }
                if t.style.hasDirection {
                    Picker("Direction", selection: transition.direction) {
                        ForEach(Self.directions, id: \.angle) { d in
                            Label(d.title, systemImage: d.symbol).labelStyle(.iconOnly).tag(d.angle)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if t.style.hasLineOrientation {
                    Picker("Lines", selection: transition.horizontal) {
                        Text("Horizontal").tag(true)
                        Text("Vertical").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                if t.style.hasInOut {
                    Picker("Movement", selection: transition.inward) {
                        Text(t.style == .zoom ? "In" : "Inward").tag(true)
                        Text(t.style == .zoom ? "Out" : "Outward").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                if let (first, second) = previewPages {
                    let index = showsSecondPage ? second : first
                    VStack {
                        PDFPageView(page: deck.page(index), region: deck.notesLayout.slideRegion, pageIndex: index,
                                    transition: { _, _ in t })
                            .aspectRatio(deck.slideAspectRatio, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                        Button("Preview") { showsSecondPage.toggle() }
                    }
                }
            }
            Section {
                Text("Plays when a new slide begins, not between the overlays of a slide. Transitions in the PDF take precedence. Saved in the pdfpc file next to the PDF.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !enabled {
                    Toggle("Play Transitions", isOn: $enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }
}
