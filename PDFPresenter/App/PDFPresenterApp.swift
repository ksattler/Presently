import SwiftUI

@main
struct PDFPresenterApp: App {
    var body: some Scene {
        DocumentGroup(viewing: PDFFile.self) { file in
            ContentView(file: file.document, fileURL: file.fileURL)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            AppCommands()
        }
    }
}

struct PresentationActions {
    var isPresenting: Bool
    var canPresent: Bool
    var start: () -> Void
    var stop: () -> Void
    var swapScreens: () -> Void
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

    var body: some Commands {
        CommandMenu("Präsentation") {
            if actions?.isPresenting == true {
                Button("Präsentation beenden") { actions?.stop() }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Bildschirme tauschen") { actions?.swapScreens() }
            } else {
                Button("Präsentation starten") { actions?.start() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!(actions?.canPresent ?? false))
            }
            Divider()
            PresentationScreenMenu()
            Divider()
            if let deck {
                Picker("Beamer-Notizen", selection: Binding(get: { deck.notesLayout }, set: { deck.notesLayout = $0 })) {
                    ForEach(NotesLayout.allCases) { Text($0.title).tag($0) }
                }
            }
        }
    }
}
