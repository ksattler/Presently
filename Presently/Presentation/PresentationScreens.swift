import AppKit
import SwiftUI

/// The displays a presentation can run on, and which one the user picked.
@MainActor
final class PresentationScreens: ObservableObject {
    static let shared = PresentationScreens()

    struct Screen: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let name: String
    }

    @Published private(set) var screens: [Screen] = []
    /// Chosen display; nil = automatic. Persisted, so a projector setup survives a restart.
    @Published var selectedID: CGDirectDisplayID? {
        didSet { defaults.set(selectedID.map { Int($0) } ?? 0, forKey: Self.displayKey) }
    }
    /// Rehearsal: the audience view opens as a normal window instead of covering a display.
    @Published var windowed: Bool {
        didSet { defaults.set(windowed, forKey: Self.windowedKey) }
    }
    /// Put the presenter view (document window) into full screen while presenting, if it's on
    /// another display than the audience.
    @Published var presenterFullScreen: Bool {
        didSet { defaults.set(presenterFullScreen, forKey: Self.presenterFullScreenKey) }
    }

    private static let displayKey = "presentationDisplayID"
    private static let windowedKey = "presentationWindowed"
    private static let presenterFullScreenKey = "presenterFullScreen"
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.integer(forKey: Self.displayKey)
        selectedID = stored == 0 ? nil : CGDirectDisplayID(stored)
        windowed = defaults.bool(forKey: Self.windowedKey)
        presenterFullScreen = defaults.object(forKey: Self.presenterFullScreenKey) as? Bool ?? true
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        screens = NSScreen.screens.compactMap { s in s.displayID.map { Screen(id: $0, name: s.localizedName) } }
    }

    /// Display to present on. Automatic: with several displays, one the presenter window is
    /// *not* on (the projector while the laptop shows the presenter view); otherwise the
    /// presenter's display. A chosen display that is no longer connected falls back to automatic.
    nonisolated static func target(available: [CGDirectDisplayID], selected: CGDirectDisplayID?,
                                   presenterDisplay: CGDirectDisplayID?) -> CGDirectDisplayID? {
        if let selected, available.contains(selected) { return selected }
        if available.count > 1, let presenterDisplay, let other = available.first(where: { $0 != presenterDisplay }) {
            return other
        }
        return presenterDisplay.flatMap { available.contains($0) ? $0 : nil } ?? available.first
    }

    func targetScreen(presenterWindow: NSWindow?) -> NSScreen? {
        let all = NSScreen.screens
        let id = Self.target(available: all.compactMap(\.displayID), selected: selectedID,
                             presenterDisplay: presenterWindow?.screen?.displayID)
        return all.first { $0.displayID == id } ?? presenterWindow?.screen ?? NSScreen.main
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// Menu content: "Present On" automatic / one of the connected displays, plus options.
struct PresentationScreenMenu: View {
    @ObservedObject private var screens = PresentationScreens.shared

    var body: some View {
        Picker("Present On", selection: $screens.selectedID) {
            Text("Automatic").tag(CGDirectDisplayID?.none)
            ForEach(screens.screens) { screen in
                Text(screen.name).tag(CGDirectDisplayID?.some(screen.id))
            }
        }
        .pickerStyle(.inline)
        Divider()
        Toggle("Audience View in a Window (Rehearsal)", isOn: $screens.windowed)
        Toggle("Presenter View in Full Screen", isOn: $screens.presenterFullScreen)
    }
}
