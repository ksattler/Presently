import SwiftUI

/// Shown in the document window while presenting: current and next slide, upcoming pages,
/// speaker notes, elapsed time and clock. The audience sees `AudienceView`.
struct PresenterView: View {
    @ObservedObject var session: PresentationSession
    @ObservedObject var deck: SlideDeck
    let stop: () -> Void
    let swapScreens: () -> Void
    @ObservedObject private var screens = PresentationScreens.shared
    @AppStorage("presenterNotesFontSize") private var notesFontSize: Double = 22
    @AppStorage("presenterUpcomingCount") private var upcomingCount = 4
    @State private var isEditingNotes = false

    private var index: Int { session.currentIndex }
    private var nextIndex: Int? { index + 1 < deck.pageCount ? index + 1 : nil }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            NotesLayoutWarning(deck: deck)
            Divider()
            if session.showsOverview {
                OverviewGrid(session: session, deck: deck)
            } else {
                main
            }
            Divider()
            bottomBar
        }
        .background(Color.black.opacity(0.92))
        .environment(\.colorScheme, .dark)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 16) {
            Text("Folie \(deck.label(index))")
                .font(.title2.monospacedDigit().bold())
            Text("Seite \(index + 1) / \(deck.pageCount)")
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)
            if !session.pageInput.isEmpty {
                Label("Gehe zu \(session.pageInput) ⏎", systemImage: "arrow.right.to.line")
                    .font(.title3.monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }
            if session.audienceDisconnected {
                Label("Beamer getrennt – Publikumsansicht kehrt beim Wiederverbinden zurück", systemImage: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.red.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
            if deck.isBackup(index) {
                Label("Backup", systemImage: "archivebox")
                    .font(.title3)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.purple.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                    .help("Nach dem markierten Vortragsende")
            }
            if let frozen = session.frozenIndex {
                Label(frozen == index ? "Eingefroren" : "Eingefroren – Publikum sieht Folie \(deck.label(frozen))",
                      systemImage: "snowflake")
                    .font(.title3)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
            if let error = session.reloadError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(1)
            }
            if let blank = session.blank {
                Label(blank == .black ? "Schwarz" : "Weiß", systemImage: "rectangle.fill")
                    .font(.title3)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
            Spacer()
            PresentationClock(session: session, deck: deck)
            Button("Beenden", action: stop)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Main area

    private var main: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                caption("Aktuell")
                PDFPageView(page: deck.page(index), region: deck.notesLayout.slideRegion,
                            background: .black)
                    .overlay {
                        LaserPointerLayer(pointer: session.pointer, page: deck.page(index),
                                          region: deck.notesLayout.slideRegion) { point in
                            session.followLink(atNormalized: point, pageIndex: index)
                        }
                    }
                    // Above the pointer layer, whose click handler would take the drags.
                    .overlay {
                        DrawingLayer(drawings: session.drawings, page: deck.page(index), pageIndex: index,
                                     region: deck.notesLayout.slideRegion)
                    }
                    .overlay(alignment: .center) { blankBadge.allowsHitTesting(false) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            VStack(alignment: .leading, spacing: 6) {
                caption(nextCaption)
                Group {
                    if let nextIndex {
                        PDFPageView(page: deck.page(nextIndex), region: deck.notesLayout.slideRegion, background: .black)
                    } else {
                        Color.black.overlay(Text("Ende der Präsentation").foregroundStyle(.secondary))
                    }
                }
                .aspectRatio(slideAspect, contentMode: .fit)
                notes
            }
            .frame(minWidth: 260, idealWidth: 420, maxWidth: 520)
        }
        .padding(16)
        .frame(maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) { upcoming }
    }

    private var nextCaption: String {
        guard let nextIndex else { return "Nächste" }
        return deck.label(nextIndex) == deck.label(index) ? "Nächste (Overlay)" : "Nächste: Folie \(deck.label(nextIndex))"
    }

    @ViewBuilder private var blankBadge: some View {
        if let blank = session.blank {
            Text(blank == .black ? "Publikum sieht Schwarz" : "Publikum sieht Weiß")
                .font(.title3.bold())
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                caption("Notizen")
                if isEditingNotes, deck.overlayGroup(of: index).count > 1 {
                    Text("alle Overlays").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { notesFontSize = max(12, notesFontSize - 2) } label: { Image(systemName: "textformat.size.smaller") }
                    .help("Kleinere Schrift")
                Button { notesFontSize = min(72, notesFontSize + 2) } label: { Image(systemName: "textformat.size.larger") }
                    .help("Größere Schrift")
                Button { isEditingNotes.toggle() } label: {
                    Image(systemName: isEditingNotes ? "checkmark.circle.fill" : "pencil")
                }
                .help(isEditingNotes ? "Bearbeiten beenden (Esc)" : "Notizen bearbeiten (Doppelklick)")
            }
            .buttonStyle(.borderless)

            if let region = deck.notesLayout.notesRegion {
                PDFPageView(page: deck.page(index), region: region, background: .black)
                    .frame(maxHeight: .infinity)
            }
            if isEditingNotes {
                notesEditor
            } else {
                let text = deck.note(for: index)
                if !text.isEmpty || deck.notesLayout.notesRegion == nil {
                    ScrollView {
                        Group {
                            if text.isEmpty {
                                Text("Keine Notizen für diese Folie.").foregroundStyle(.tertiary)
                            } else {
                                NotesText(text: text)
                            }
                        }
                        .font(.system(size: notesFontSize))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { isEditingNotes = true }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// Edits the pdfpc note of the current page. Keys go into the text; the clicker's
    /// Page Up / Page Down still turn pages (see `PresentationController`), Escape ends editing.
    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            NotesTextView(text: Binding(get: { deck.editableNote(for: index) },
                                        set: { deck.setNote($0, for: index) }),
                          fontSize: notesFontSize, textColor: .white, focusOnAppear: true,
                          onEscape: { isEditingNotes = false })
                .padding(4)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.6)))
            if let embedded = deck.embeddedNotes[index], !embedded.isEmpty {
                Text("Im PDF: \(embedded)")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(3)
            }
            if deck.fileURL == nil {
                Text("Nicht speicherbar (keine Datei)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// Strip of the pages after the next one.
    @ViewBuilder private var upcoming: some View {
        let start = index + 2
        let pages = Array(start..<min(start + upcomingCount, deck.pageCount))
        if upcomingCount > 0 {
            HStack(spacing: 10) {
                ForEach(pages, id: \.self) { i in
                    Button { session.go(to: i) } label: {
                        VStack(spacing: 2) {
                            PageThumbnail(deck: deck, index: i, region: deck.notesLayout.slideRegion,
                                          pixelSize: CGSize(width: 320, height: 240))
                                .aspectRatio(slideAspect, contentMode: .fit)
                            Text(deck.label(i)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Zu Seite \(i + 1) springen")
                }
                Spacer(minLength: 0)
            }
            .frame(height: 110)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 18) {
            Button { session.handle(.previous) } label: { Label("Zurück", systemImage: "chevron.left") }
                .disabled(index == 0)
            Toggle(isOn: Binding(get: { session.frozenIndex != nil }, set: { _ in session.handle(.toggleFreeze) })) {
                Label("Einfrieren", systemImage: "snowflake")
            }
            .toggleStyle(.button)
            .help("Publikum behält die aktuelle Folie, während du blätterst (F)")
            PointerToggle(pointer: session.pointer) { session.handle(.togglePointer) }
            DrawingTools(session: session, drawings: session.drawings)
            Button(action: swapScreens) { Label("Tauschen", systemImage: "arrow.left.arrow.right") }
                .help("Publikum und Referentenansicht tauschen die Bildschirme (S)")
                .disabled(screens.windowed || screens.screens.count < 2)
            Text("← → Bild↑↓ Leertaste · ⇧ Overlays überspringen · Nummer ⏎ springen · B/W Schwarz/Weiß · F Einfrieren · L Laserpointer · S Bildschirme tauschen · D/H/E Stift/Marker/Radierer · Z/X Rückgängig/Löschen · Tab Übersicht · P Timer · Doppelklick Notizen bearbeiten · Esc Ende")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
            Button { session.handle(.next) } label: { Label("Weiter", systemImage: "chevron.right") }
                .disabled(session.isAtEnd)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(.headline).foregroundStyle(.secondary).lineLimit(1)
    }

    private var slideAspect: CGFloat { deck.slideAspectRatio }
}

/// Pen, highlighter, eraser, colors, undo and clear for the current page.
private struct DrawingTools: View {
    @ObservedObject var session: PresentationSession
    @ObservedObject var drawings: Drawings

    var body: some View {
        HStack(spacing: 6) {
            toolToggle(.pen, "Stift", "pencil.tip", key: "D")
            toolToggle(.highlighter, "Textmarker", "highlighter", key: "H")
            toolToggle(.eraser, "Radierer", "eraser", key: "E")
            Menu {
                Picker("Stift", selection: $drawings.penColor) {
                    ForEach(Drawings.PenColor.allCases) { Text($0.title).tag($0) }
                }
                Picker("Textmarker", selection: $drawings.highlighterColor) {
                    ForEach(Drawings.PenColor.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Circle().fill(drawings.penColor.color).frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white.opacity(0.6)))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Farben")
            Button { session.handle(.undoDrawing) } label: { Image(systemName: "arrow.uturn.backward") }
                .help("Letzten Strich dieser Folie entfernen (Z)")
                .disabled(drawings.strokes[session.currentIndex]?.isEmpty ?? true)
            Button { session.handle(.clearDrawing) } label: { Image(systemName: "trash") }
                .help("Zeichnungen dieser Folie löschen (X)")
                .disabled(drawings.strokes[session.currentIndex]?.isEmpty ?? true)
        }
    }

    private func toolToggle(_ tool: Drawings.Tool, _ title: String, _ icon: String, key: String) -> some View {
        Toggle(isOn: Binding(get: { drawings.tool == tool }, set: { _ in session.selectTool(tool) })) {
            Image(systemName: icon)
        }
        .toggleStyle(.button)
        .help("\(title) (\(key))")
    }
}

private struct PointerToggle: View {
    @ObservedObject var pointer: LaserPointer
    let toggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { pointer.isEnabled }, set: { _ in toggle() })) {
            Label("Laserpointer", systemImage: "circle.circle.fill")
        }
        .toggleStyle(.button)
        .help("Mauszeiger über der aktuellen Folie erscheint als roter Punkt beim Publikum (L)")
    }
}

/// Elapsed talk time (pausable), remaining time and pace if a limit is set, and wall clock.
/// Separate view so the ticking doesn't re-evaluate the rest of the presenter view.
struct PresentationClock: View {
    @ObservedObject var session: PresentationSession
    @ObservedObject var deck: SlideDeck
    @State private var editingPlan = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = session.timer.elapsed(at: context.date)
            let remaining = deck.talkLimit.remaining(elapsed: elapsed, now: context.date)
            HStack(spacing: 12) {
                if session.timerWaitsForFirstTurn {
                    Label("Start beim Blättern", systemImage: "timer")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    Label(PresentationTimer.format(elapsed), systemImage: session.timer.isRunning ? "timer" : "pause.circle")
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(session.timer.isRunning ? .primary : Color.orange)
                }
                Button { session.handle(.toggleTimer) } label: {
                    Image(systemName: session.timer.isRunning ? "pause.fill" : "play.fill")
                }
                .help(session.timer.isRunning ? "Timer anhalten (P)" : "Timer starten (P)")
                Button { session.handle(.resetTimer) } label: { Image(systemName: "arrow.counterclockwise") }
                    .help("Timer zurücksetzen (R)")

                if let remaining {
                    Text("Rest \(PresentationTimer.format(remaining))")
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(remaining < 0 ? Color.red : remaining < 120 ? Color.orange : Color.secondary)
                    // Pace only once the talk runs and while on the talk's own slides.
                    if !session.timerWaitsForFirstTurn, let progress = deck.talkProgress(at: session.currentIndex) {
                        let pace = TalkPlan.paceOffset(elapsed: elapsed, remaining: remaining, progress: progress)
                        Text(TalkPlan.formatPace(pace))
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(abs(pace) < 30 ? Color.secondary : pace > 0 ? Color.green : Color.orange)
                            .help("Folienfortschritt gegenüber verstrichener Zeit")
                    }
                }
                Button { editingPlan.toggle() } label: { Image(systemName: "hourglass") }
                    .help("Vortragsdauer oder Endzeit festlegen")
                    .popover(isPresented: $editingPlan) { TalkPlanEditor(session: session, deck: deck).padding() }

                Text(context.date, format: .dateTime.hour().minute())
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Talk limit (none / duration / end time) and when the timer starts.
struct TalkPlanEditor: View {
    @ObservedObject var session: PresentationSession
    @ObservedObject var deck: SlideDeck

    private enum Kind: Hashable { case none, duration, endTime }

    private var kind: Binding<Kind> {
        Binding(get: {
            switch deck.talkLimit {
            case .none: return .none
            case .duration: return .duration
            case .endTime: return .endTime
            }
        }, set: { kind in
            switch kind {
            case .none: deck.talkLimit = .none
            case .duration: deck.talkLimit = .duration(minutes: 20)
            case .endTime:
                // Default: a round time about 30 minutes from now.
                let c = Calendar.current.dateComponents([.hour, .minute], from: Date().addingTimeInterval(30 * 60))
                deck.talkLimit = .endTime(hour: c.hour ?? 12, minute: (c.minute ?? 0) / 5 * 5)
            }
        })
    }

    var body: some View {
        Form {
            Picker("Begrenzung", selection: kind) {
                Text("Keine").tag(Kind.none)
                Text("Dauer").tag(Kind.duration)
                Text("Endzeit").tag(Kind.endTime)
            }
            .pickerStyle(.segmented)
            switch deck.talkLimit {
            case .none:
                EmptyView()
            case .duration(let minutes):
                Stepper(value: Binding(get: { minutes }, set: { deck.talkLimit = .duration(minutes: $0) }),
                        in: 1...600, step: 5) {
                    Text("\(minutes) Minuten").monospacedDigit()
                }
            case .endTime(let hour, let minute):
                DatePicker("Ende um", selection: Binding(
                    get: { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() },
                    set: {
                        let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                        deck.talkLimit = .endTime(hour: c.hour ?? hour, minute: c.minute ?? minute)
                    }), displayedComponents: .hourAndMinute)
            }
            Toggle("Timer startet beim ersten Blättern", isOn: Binding(
                get: { session.timerStartsOnFirstTurn }, set: { session.timerStartsOnFirstTurn = $0 }))
            if deck.endPage != nil {
                Text("Vortrag endet nach Folie \(deck.label(deck.endPage!)); danach Backup.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 300)
    }
}

/// All pages as a grid; click jumps there.
struct OverviewGrid: View {
    @ObservedObject var session: PresentationSession
    @ObservedObject var deck: SlideDeck

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                    ForEach(0..<deck.pageCount, id: \.self) { i in
                        Button {
                            session.go(to: i)
                            session.showsOverview = false
                        } label: {
                            VStack(spacing: 4) {
                                PageThumbnail(deck: deck, index: i, region: deck.notesLayout.slideRegion)
                                    .aspectRatio(deck.slideAspectRatio, contentMode: .fit)
                                    .overlay(RoundedRectangle(cornerRadius: 4)
                                        .stroke(i == session.currentIndex ? Color.accentColor : .clear, lineWidth: 3))
                                Text("\(deck.label(i))  ·  \(i + 1)\(deck.isBackup(i) ? "  · Backup" : "")").font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(i)
                    }
                }
                .padding(16)
            }
            .onAppear { proxy.scrollTo(session.currentIndex, anchor: .center) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
