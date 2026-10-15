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
            let size = CGSize(width: 960, height: 540)
            let frame = CGRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2,
                               width: size.width, height: size.height)
            w = AudienceWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                               backing: .buffered, defer: false)
            w.title = "Publikum – \(presenterWindow?.title ?? "Präsentation")"
        } else {
            w = AudienceWindow(contentRect: screen.frame, styleMask: [.borderless],
                               backing: .buffered, defer: false, screen: screen)
            w.setFrame(screen.frame, display: false)
            w.level = .mainMenu + 1   // above menu bar and Dock of that display
            w.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
            // Menu bar and Dock can still slide in on hover on the display that has them.
            if screen == NSScreen.screens.first {
                savedOptions = NSApp.presentationOptions
                NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
            }
        }
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        w.contentView = NSHostingView(rootView: AudienceView(session: session))
        w.delegate = self
        audienceWindow = w

        installMonitor()
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Präsentation läuft")

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
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        NSApp.presentationOptions = savedOptions
        savedOptions = []
        if madePresenterFullScreen, let pw = presenterWindow, pw.styleMask.contains(.fullScreen) {
            pw.toggleFullScreen(nil)
        }
        madePresenterFullScreen = false
        session?.end()
        presenterWindow?.makeKeyAndOrderFront(nil)
        if Self.active === self { Self.active = nil }
    }

    func windowWillClose(_ notification: Notification) {
        // Closed by the user (windowed mode) or the system (display disconnected).
        audienceWindow = nil
        tearDown()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let w = audienceWindow, let screen = w.screen, w.styleMask == .borderless else { return }
        w.setFrame(screen.frame, display: true)
    }

    // MARK: Events

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let session = self.session, session.isPresenting else { return event }
            let inAudience = event.window != nil && event.window === self.audienceWindow
            let inPresenter = event.window != nil && event.window === self.presenterWindow

            switch event.type {
            case .leftMouseDown where inAudience && event.clickCount == 1 && !session.showsOverview:
                session.handle(.next)
                return nil
            case .rightMouseDown where inAudience:
                session.handle(.previous)
                return nil
            case .keyDown where inAudience || inPresenter:
                // Typing in a text field of the presenter window (timer duration) stays there.
                if event.window?.firstResponder is NSText { return event }
                guard let action = PresentKeyAction(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
                                                    modifiers: event.modifierFlags)
                else { return event }
                if inAudience, self.audienceWindow?.styleMask == .borderless { NSCursor.setHiddenUntilMouseMoves(true) }
                if !session.handle(action), action == .exit { self.stop() }
                return nil
            default:
                return event
            }
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
