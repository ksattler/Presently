import AppKit
import SwiftUI

/// Runs a presentation for one document window: opens the audience window on the chosen
/// display, routes keys (keyboard and clickers) and mouse clicks to the session, keeps the
/// display awake and optionally puts the presenter window into full screen.
@MainActor
final class PresentationController: NSObject, NSWindowDelegate {
    /// Only one presentation runs at a time; starting another ends the first.
    private static weak var active: PresentationController?

    private var audienceWindow: NSWindow?
    private weak var session: PresentationSession?
    private weak var presenterWindow: NSWindow?
    private var monitor: Any?
    private var savedOptions: NSApplication.PresentationOptions = []
    private var madePresenterFullScreen = false
    private var activity: NSObjectProtocol?
    private var fullScreenObserver: NSObjectProtocol?
    /// Display the audience should be on (chosen at start or by swapping). Kept while that
    /// display is disconnected, so the audience view returns when it comes back.
    private var audienceDisplayID: CGDirectDisplayID?
    private var screenObserver: NSObjectProtocol?
    private var placementTask: Task<Void, Never>?

    private final class AudienceWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    var isShowing: Bool { audienceWindow != nil }
    var window: NSWindow? { audienceWindow }

    func start(session: PresentationSession, presenterWindow: NSWindow?) {
        guard audienceWindow == nil else { return }
        if let other = Self.active, other !== self { other.stop() }
        let screens = PresentationScreens.shared
        guard let screen = screens.targetScreen(presenterWindow: presenterWindow) else { return }
        Self.active = self
        self.session = session
        self.presenterWindow = presenterWindow
        session.deck.saveNow()
        session.begin()

        let w: NSWindow
        if screens.windowed {
            w = AudienceWindow(contentRect: Self.rehearsalFrame(in: screen.visibleFrame), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                               backing: .buffered, defer: false)
            w.title = String(localized: "Audience – \(presenterWindow?.title ?? String(localized: "Presentation"))")
        } else {
            w = AudienceWindow(contentRect: screen.frame, styleMask: [.borderless],
                               backing: .buffered, defer: false, screen: screen)
            w.setFrame(screen.frame, display: false)
            w.level = .mainMenu + 1   // above menu bar and Dock of that display
            w.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
            savedOptions = NSApp.presentationOptions
            hideMenuBar(ifOn: screen)
        }
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        w.contentView = NSHostingView(rootView: AudienceView(session: session))
        w.delegate = self
        audienceWindow = w
        if !screens.windowed {
            audienceDisplayID = screen.displayID
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedulePlacementUpdate() }
            }
        }

        installMonitor()
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Presentation running")

        if !screens.windowed, screens.presenterFullScreen, let pw = presenterWindow,
           pw.screen != screen, !pw.styleMask.contains(.fullScreen) {
            pw.toggleFullScreen(nil)
            madePresenterFullScreen = true
        }

        w.alphaValue = 0
        w.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; w.animator().alphaValue = 1 }
        if !screens.windowed { NSCursor.setHiddenUntilMouseMoves(true) }
    }

    /// The audience window for rehearsal: 16:9, centered, at most the display's visible area.
    nonisolated static func rehearsalFrame(in visible: CGRect) -> CGRect {
        let size = CGSize(width: min(960, visible.width), height: min(540, visible.height))
        return CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
    }

    func stop() {
        guard let w = audienceWindow else { return }
        audienceWindow = nil
        w.delegate = nil
        w.orderOut(nil)
        w.contentView = nil
        w.close()
        tearDown()
    }

    private func tearDown() {
        removeMonitor()
        if let fullScreenObserver { NotificationCenter.default.removeObserver(fullScreenObserver) }
        fullScreenObserver = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        placementTask?.cancel()
        placementTask = nil
        audienceDisplayID = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        NSApp.presentationOptions = savedOptions
        savedOptions = []
        if madePresenterFullScreen, let pw = presenterWindow, pw.styleMask.contains(.fullScreen) {
            pw.toggleFullScreen(nil)
        }
        madePresenterFullScreen = false
        session?.end()
        session?.deck.saveNow()   // notes edited during the talk
        presenterWindow?.makeKeyAndOrderFront(nil)
        if Self.active === self { Self.active = nil }
    }

    func windowWillClose(_ notification: Notification) {
        // Closed by the user (windowed mode) or the system (display disconnected).
        audienceWindow = nil
        tearDown()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        // Usually the system moving the window off a disconnected display. Don't just cover
        // whatever display it landed on (that may be the presenter's) — decide again.
        schedulePlacementUpdate()
    }

    // MARK: Displays connected / disconnected

    enum AudiencePlacement: Equatable {
        case show(CGDirectDisplayID)
        case hide
    }

    /// Where the audience view goes when the set of displays changes: its own display if
    /// connected; otherwise another display that isn't the presenter's; otherwise nowhere
    /// (hidden — the talk goes on from the presenter view until the projector is back).
    /// Started on the presenter's only display and a projector gets plugged in: onto the projector.
    nonisolated static func audiencePlacement(intended: CGDirectDisplayID, presenter: CGDirectDisplayID?,
                                              available: [CGDirectDisplayID]) -> AudiencePlacement {
        if available.contains(intended) {
            if intended == presenter, let other = available.first(where: { $0 != intended }) { return .show(other) }
            return .show(intended)
        }
        if let other = available.first(where: { $0 != presenter }), presenter != nil { return .show(other) }
        if presenter == nil, let first = available.first { return .show(first) }
        return .hide
    }

    /// Display changes arrive in bursts, and `NSScreen.screens` settles a moment later.
    private func schedulePlacementUpdate() {
        placementTask?.cancel()
        placementTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.updateAudiencePlacement()
        }
    }

    private func updateAudiencePlacement() {
        guard let aw = audienceWindow, aw.styleMask == .borderless, let intended = audienceDisplayID,
              let session else { return }
        let screens = NSScreen.screens
        let presenterID = presenterWindow?.screen?.displayID
        let update = Self.placementUpdate(intended: intended, presenter: presenterID,
                                          available: screens.compactMap(\.displayID))
        audienceDisplayID = update.intended
        switch update.placement {
        case .hide:
            if aw.isVisible {
                aw.orderOut(nil)
                NSApp.presentationOptions = savedOptions
                presenterWindow?.makeKeyAndOrderFront(nil)
            }
            session.audienceDisconnected = true
        case .show(let id):
            guard let screen = screens.first(where: { $0.displayID == id }) else { return }
            if aw.frame != screen.frame { aw.setFrame(screen.frame, display: true) }
            hideMenuBar(ifOn: screen)
            if !aw.isVisible { aw.makeKeyAndOrderFront(nil) }
            session.audienceDisconnected = false
        }
    }

    struct PlacementUpdate: Equatable {
        var placement: AudiencePlacement
        /// The audience's display from now on.
        var intended: CGDirectDisplayID
    }

    /// Everything `updateAudiencePlacement` decides, from display IDs only. The audience never
    /// lands on the presenter's display while another one is free, so the presenter window
    /// never has to make way.
    nonisolated static func placementUpdate(intended: CGDirectDisplayID, presenter: CGDirectDisplayID?,
                                            available: [CGDirectDisplayID]) -> PlacementUpdate {
        let placement = audiencePlacement(intended: intended, presenter: presenter, available: available)
        var update = PlacementUpdate(placement: placement, intended: intended)
        // Moved off the presenter's display (projector plugged in later): that's home now.
        // Not when standing in for a disconnected display — it should come back there.
        if case .show(let id) = placement, intended == presenter { update.intended = id }
        return update
    }

    /// Menu bar and Dock can still slide in on hover on the display that has them: auto-hide
    /// them while the audience window covers that display.
    private func hideMenuBar(ifOn screen: NSScreen) {
        NSApp.presentationOptions = Self.presentationOptions(coveringMenuBarDisplay: screen == NSScreen.screens.first,
                                                             saved: savedOptions)
    }

    nonisolated static func presentationOptions(coveringMenuBarDisplay: Bool,
                                                saved: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        coveringMenuBarDisplay ? [.autoHideMenuBar, .autoHideDock] : saved
    }

    // MARK: Swapping displays

    /// Only for a full-screen audience window, with more than one display.
    var canSwapScreens: Bool {
        audienceWindow?.styleMask == .borderless && presenterWindow != nil && NSScreen.screens.count > 1
    }

    /// Audience and presenter trade displays (wrong projector detected, cables swapped). The
    /// new audience display is remembered as the chosen one.
    func swapScreens() {
        guard canSwapScreens, let aw = audienceWindow, let pw = presenterWindow,
              let audienceID = aw.screen?.displayID,
              let targets = Self.swapTargets(audience: audienceID, presenter: pw.screen?.displayID,
                                             available: NSScreen.screens.compactMap(\.displayID)),
              let audienceScreen = NSScreen.screens.first(where: { $0.displayID == targets.audience }),
              let presenterScreen = NSScreen.screens.first(where: { $0.displayID == targets.presenter })
        else { return }
        PresentationScreens.shared.selectedID = targets.audience
        audienceDisplayID = targets.audience
        aw.setFrame(audienceScreen.frame, display: true)
        hideMenuBar(ifOn: audienceScreen)
        movePresenter(pw, to: presenterScreen)
        aw.makeKeyAndOrderFront(nil)
    }

    /// Displays after a swap. Normally the two trade places; if both are on one display (a
    /// move that didn't happen, a display reconnected), the audience stays and the presenter
    /// goes to another display — so the presenter view can always be brought back.
    nonisolated static func swapTargets(audience: CGDirectDisplayID, presenter: CGDirectDisplayID?,
                                        available: [CGDirectDisplayID]) -> (audience: CGDirectDisplayID, presenter: CGDirectDisplayID)? {
        if let presenter, presenter != audience, available.contains(presenter) {
            return (presenter, audience)
        }
        guard let other = available.first(where: { $0 != audience }) else { return nil }
        return (audience, other)
    }

    private func movePresenter(_ pw: NSWindow, to screen: NSScreen) {
        let place = { [weak pw] in
            guard let pw else { return }
            let from = pw.screen?.visibleFrame ?? screen.visibleFrame
            pw.setFrame(Self.frame(pw.frame, movedFrom: from, to: screen.visibleFrame), display: true)
        }
        guard pw.styleMask.contains(.fullScreen) else { place(); return }
        // A full-screen window can't be moved: leave full screen, move, enter it again.
        let targetDisplayID = screen.displayID
        if let o = fullScreenObserver { NotificationCenter.default.removeObserver(o) }
        fullScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification, object: pw, queue: .main
        ) { [weak self, weak pw] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let o = self.fullScreenObserver { NotificationCenter.default.removeObserver(o) }
                self.fullScreenObserver = nil
                // AppKit restores the pre-full-screen frame right after this notification —
                // moving now would be undone. Move on the next turn, re-enter full screen only
                // once the window really is on the target display.
                DispatchQueue.main.async {
                    place()
                    DispatchQueue.main.async {
                        guard self.audienceWindow != nil, let pw, pw.screen?.displayID == targetDisplayID,
                              !pw.styleMask.contains(.fullScreen) else { return }
                        pw.toggleFullScreen(nil)
                    }
                }
            }
        }
        pw.toggleFullScreen(nil)
    }

    /// `frame` moved from one display area to another at the same relative position, shrunk
    /// to fit if the target is smaller.
    nonisolated static func frame(_ frame: CGRect, movedFrom from: CGRect, to target: CGRect) -> CGRect {
        let w = min(frame.width, target.width), h = min(frame.height, target.height)
        let rx = from.width > 0 ? (frame.midX - from.minX) / from.width : 0.5
        let ry = from.height > 0 ? (frame.midY - from.minY) / from.height : 0.5
        let x = min(max(target.minX + rx * target.width - w / 2, target.minX), target.maxX - w)
        let y = min(max(target.minY + ry * target.height - h / 2, target.minY), target.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: Events

    /// Click position on the audience slide, normalized to the slide region (y down).
    private func audienceSlidePoint(_ event: NSEvent) -> CGPoint? {
        guard let session, let view = audienceWindow?.contentView,
              let page = session.deck.page(session.audienceIndex) else { return nil }
        let area = view.convert(view.bounds, to: nil)   // window coordinates, y up
        let slide = PageRenderer.fittedRect(for: page, region: session.deck.notesLayout.slideRegion, in: area,
                                            zoom: session.audienceZoom, yUp: true)
        return Self.normalized(event.locationInWindow, in: slide)
    }

    /// A point in window coordinates (y up) relative to the slide's rect: 0…1, y down.
    nonisolated static func normalized(_ p: CGPoint, in slide: CGRect) -> CGPoint? {
        guard slide.width > 0, slide.height > 0 else { return nil }
        return CGPoint(x: (p.x - slide.minX) / slide.width, y: (slide.maxY - p.y) / slide.height)
    }

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let session = self.session, session.isPresenting else { return event }
            let source: EventSource = event.window == nil ? .other
                : event.window === self.audienceWindow ? .audience
                : event.window === self.presenterWindow ? .presenter : .other
            let isKey = event.type == .keyDown
            let input = EventInput(
                kind: isKey ? .key : event.type == .rightMouseDown ? .rightClick : .leftClick,
                source: source,
                clickCount: isKey ? 0 : event.clickCount,
                audienceTakesDrags: session.drawings.tool != nil || session.isSelectingZoom,
                editingText: event.window?.firstResponder is NSText,
                keyCode: isKey ? event.keyCode : 0,
                characters: isKey ? event.charactersIgnoringModifiers : nil,
                modifiers: event.modifierFlags)

            switch Self.route(input) {
            case .passThrough:
                return event
            case .clickOnAudience:
                // A link on the slide is followed; anywhere else a click advances.
                if let p = self.audienceSlidePoint(event),
                   session.click(atNormalized: p, pageIndex: session.audienceIndex, unfreeze: true) { return nil }
                session.handle(.next)
                return nil
            case .previous:
                session.handle(.previous)
                return nil
            case .key(let action):
                if source == .audience, self.audienceWindow?.styleMask == .borderless { NSCursor.setHiddenUntilMouseMoves(true) }
                if action == .swapScreens { self.swapScreens(); return nil }
                if !session.handle(action), action == .exit { self.stop() }
                return nil
            }
        }
    }

    enum EventSource { case audience, presenter, other }

    /// What the event monitor needs to know about an event, without `NSEvent`.
    struct EventInput {
        enum Kind { case key, leftClick, rightClick }
        var kind: Kind
        var source: EventSource
        var clickCount = 1
        /// A drawing tool or the zoom selection is active: the audience view takes clicks itself.
        var audienceTakesDrags = false
        /// A text view has focus (notes editor, timer duration).
        var editingText = false
        var keyCode: UInt16 = 0
        var characters: String? = nil
        var modifiers: NSEvent.ModifierFlags = []
    }

    enum EventRoute: Equatable {
        /// Not ours: the event goes on to the window.
        case passThrough
        /// Follow a link at the click, else next page.
        case clickOnAudience
        case previous
        case key(PresentKeyAction)
    }

    /// How the event monitor handles an event during a presentation.
    nonisolated static func route(_ e: EventInput) -> EventRoute {
        switch (e.kind, e.source) {
        case (.leftClick, .audience):
            // Drawing or selecting a zoom; a double click's second click doesn't turn twice.
            return e.audienceTakesDrags || e.clickCount != 1 ? .passThrough : .clickOnAudience
        case (.rightClick, .audience):
            return .previous
        case (.key, .audience), (.key, .presenter):
            // Typing in the presenter window (notes, timer duration) stays there — except the
            // clicker's page keys, so the talk can go on while a note is being edited.
            if e.editingText, !isClickerPageKey(e.keyCode) { return .passThrough }
            return PresentKeyAction(keyCode: e.keyCode, characters: e.characters, modifiers: e.modifiers).map { .key($0) } ?? .passThrough
        default:
            return .passThrough
        }
    }

    /// Page Up / Page Down: what clickers send for back / next. Plain keyboards rarely use them
    /// for text editing, so they keep turning pages while a text field has focus.
    nonisolated static func isClickerPageKey(_ keyCode: UInt16) -> Bool {
        keyCode == PresentKeyAction.KeyCode.pageUp || keyCode == PresentKeyAction.KeyCode.pageDown
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
