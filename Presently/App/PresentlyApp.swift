import SwiftUI

@main
struct PresentlyApp: App {
    init() {
        LegacySettings.migrate(from: "com.pdfpresenter.app", to: .standard)
    }

    var body: some Scene {
        DocumentGroup(viewing: PDFFile.self) { file in
            ContentView(file: file.document, fileURL: file.fileURL)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            AppCommands()
        }

        Window("Presently Help", id: HelpView.windowID) {
            HelpView()
        }
        .defaultSize(width: 820, height: 560)

        Settings {
            SettingsView()
        }
    }
}

struct PresentationActions {
    var isPresenting: Bool
    var canPresent: Bool
    var start: () -> Void
    var stop: () -> Void
    var swapScreens: () -> Void
    var showSlideTimes: () -> Void
}

private struct PresentationActionsKey: FocusedValueKey {
    typealias Value = PresentationActions
}

extension FocusedValues {
    var presentationActions: PresentationActions? {
        get { self[PresentationActionsKey.self] }
        set { self[PresentationActionsKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    @FocusedValue(\.presentationActions) private var actions
    @FocusedObject private var deck: SlideDeck?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Presently") { AboutPanel.show() }
        }
        CommandGroup(replacing: .help) {
            // No ⌘? here: the system reserves it for the Help menu search, which lists this item first.
            Button("Presently Help") { openWindow(id: HelpView.windowID) }
        }
        CommandMenu("Presentation") {
            if actions?.isPresenting == true {
                Button("End Presentation") { actions?.stop() }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Swap Displays") { actions?.swapScreens() }
            } else {
                Button("Start Presentation") { actions?.start() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!(actions?.canPresent ?? false))
            }
            Button("Slide Times…") { actions?.showSlideTimes() }
                .disabled(actions == nil)
            Divider()
            TransitionsToggle()
            Divider()
            PresentationScreenMenu()
            Divider()
            if let deck {
                // Only here, not in the toolbar: detected automatically, rarely changed by hand.
                Picker("Beamer Notes", selection: Binding(get: { deck.notesLayout }, set: { deck.notesLayout = $0 })) {
                    ForEach(NotesLayout.allCases) { Text($0.title).tag($0) }
                }
            }
        }
    }
}

private struct TransitionsToggle: View {
    @AppStorage(PageTransition.enabledKey) private var enabled = true

    var body: some View {
        Toggle("Play Transitions from the PDF", isOn: $enabled)
    }
}

/// Settings (display choice, presenter layout, last pages, …) from before the rename to
/// Presently lived under the old bundle ID. Copied once; keys already set in the new domain win.
enum LegacySettings {
    static let migratedKey = "migratedLegacySettings"

    static func migrate(from oldDomain: String, to defaults: UserDefaults) {
        guard !defaults.bool(forKey: migratedKey) else { return }
        defer { defaults.set(true, forKey: migratedKey) }
        guard let old = UserDefaults.standard.persistentDomain(forName: oldDomain) else { return }
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}
