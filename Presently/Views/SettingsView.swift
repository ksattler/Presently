import SwiftUI

/// Settings window (⌘,). Gathers what the Presentation and View menus and the schedule popover
/// also offer; all of it reads and writes the same UserDefaults keys.
struct SettingsView: View {
    var body: some View {
        TabView {
            PresentationSettings()
                .tabItem { Label("Presentation", systemImage: "play.rectangle") }
            PresenterViewSettings()
                .tabItem { Label("Presenter View", systemImage: "rectangle.split.3x1") }
        }
        .frame(width: 460)
    }
}

private struct PresentationSettings: View {
    @ObservedObject private var screens = PresentationScreens.shared
    @AppStorage(PageTransition.enabledKey) private var transitionsEnabled = true
    @AppStorage(PresentationSession.timerStartsOnFirstTurnKey) private var timerStartsOnFirstTurn = true

    var body: some View {
        Form {
            Picker("Present On", selection: $screens.selectedID) {
                Text("Automatic").tag(CGDirectDisplayID?.none)
                ForEach(screens.screens) { screen in
                    Text(screen.name).tag(CGDirectDisplayID?.some(screen.id))
                }
            }
            Toggle("Audience View in a Window (Rehearsal)", isOn: $screens.windowed)
            Toggle("Presenter View in Full Screen", isOn: $screens.presenterFullScreen)
            Toggle("Play Transitions from the PDF", isOn: $transitionsEnabled)
            Toggle("Timer starts on the first page turn", isOn: $timerStartsOnFirstTurn)
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)   // window as tall as the tab
    }
}

private struct PresenterViewSettings: View {
    @AppStorage(PresenterLayout.Key.currentOnRight) private var currentOnRight = false
    @AppStorage(PresenterLayout.Key.showsNext) private var showsNext = true
    @AppStorage(PresenterLayout.Key.showsNotes) private var showsNotes = true
    @AppStorage(PresenterLayout.Key.upcomingCount) private var upcomingCount = PresenterLayout.Default.upcomingCount
    @AppStorage(PresenterLayout.Key.notesFontSize) private var notesFontSize = PresenterLayout.Default.notesFontSize

    var body: some View {
        Form {
            Toggle("Current Slide on the Right", isOn: $currentOnRight)
            Toggle("Next Slide", isOn: $showsNext)
            Toggle("Notes", isOn: $showsNotes)
            Picker("Upcoming Pages", selection: $upcomingCount) {
                Text("Off").tag(0)
                ForEach(1...PresenterLayout.upcomingRange.upperBound, id: \.self) { Text($0, format: .number).tag($0) }
            }
            Stepper(value: $notesFontSize, in: PresenterLayout.notesFontSizeRange, step: 2) {
                Text("Notes text size: \(Int(notesFontSize)) pt").monospacedDigit()
            }
            HStack {
                Spacer()
                Button("Reset Layout") { PresenterLayout.reset() }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)   // window as tall as the tab
    }
}
