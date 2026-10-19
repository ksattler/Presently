import Combine
import Sparkle
import SwiftUI

/// Update checks via Sparkle. The feed (`SUFeedURL`) and the signing key (`SUPublicEDKey`) are in
/// Info.plist; `scripts/release.sh` publishes a signed appcast.xml with every release.
/// Debug builds and test runs don't start the updater: their build number would always look outdated.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    @Published private(set) var canCheckForUpdates = false
    private let controller: SPUStandardUpdaterController?

    private init() {
        #if DEBUG
        controller = nil
        #else
        controller = NSClassFromString("XCTestCase") == nil
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
        #endif
        controller?.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Sparkle stores it in UserDefaults (`SUEnableAutomaticChecks`) itself.
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }
}

/// Menu item in the app menu, after "About Presently".
struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
