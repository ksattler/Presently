import AppKit

/// Keys that control a running presentation. Includes what presenter remotes ("clickers")
/// send: most emulate a keyboard with Page Up / Page Down, some use the arrow keys, Return or
/// Backspace, Home / End, and "B" or "." for a black screen (Logitech, Kensington, Microsoft).
enum PresentKeyAction: Equatable {
    case next, previous, first, last
    case nextSlide, previousSlide   // skip overlays
    case exit                       // Escape: clear input / close overview / stop drawing / unblank / unfreeze first
    case black, white
    case digit(Int)                 // typed page number, confirmed with Return
    case confirm                    // Return
    case toggleOverview
    case toggleTimer, resetTimer
    case toggleFreeze               // audience keeps the current page while the presenter browses
    case togglePointer              // laser pointer
    case toggleSpotlight            // laser pointer as a spotlight
    case toggleZoom                 // select a part of the slide to enlarge for the audience / back
    case swapScreens                // audience and presenter trade displays
    case pen, highlighter, eraser   // drawing tools (toggle)
    case undoDrawing, clearDrawing  // on the current page
    case ignore                     // consumed without effect (F5 from a clicker's start button)

    enum KeyCode {
        static let right: UInt16 = 124, left: UInt16 = 123, down: UInt16 = 125, up: UInt16 = 126
        static let space: UInt16 = 49, tab: UInt16 = 48, returnKey: UInt16 = 36, enter: UInt16 = 76
        static let pageDown: UInt16 = 121, pageUp: UInt16 = 116, home: UInt16 = 115, end: UInt16 = 119
        static let backspace: UInt16 = 51, escape: UInt16 = 53, f5: UInt16 = 96
    }

    /// ⌘, ⌥ and ⌃ combinations are never handled, so menu shortcuts (⌘Q, ⌘W, …) keep working.
    init?(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags = []) {
        let mods = modifiers.intersection([.command, .option, .control, .shift])
        guard mods.intersection([.command, .option, .control]).isEmpty else { return nil }
        let shift = mods.contains(.shift)

        switch keyCode {
        case KeyCode.right, KeyCode.down, KeyCode.pageDown:
            self = shift ? .nextSlide : .next; return
        case KeyCode.left, KeyCode.up, KeyCode.pageUp, KeyCode.backspace:
            self = shift ? .previousSlide : .previous; return
        case KeyCode.space:
            self = shift ? .previous : .next; return
        case KeyCode.returnKey, KeyCode.enter: self = .confirm; return
        case KeyCode.home:    self = .first; return
        case KeyCode.end:     self = .last; return
        case KeyCode.escape:  self = .exit; return
        case KeyCode.tab:     self = .toggleOverview; return
        case KeyCode.f5:      self = .ignore; return
        default: break
        }

        switch characters?.lowercased() {
        case "b", ".": self = .black
        case "w", ",": self = .white
        case "p":      self = .toggleTimer
        case "r":      self = .resetTimer
        case "o":      self = .toggleOverview
        case "f":      self = .toggleFreeze
        case "l":      self = .togglePointer
        case "c":      self = .toggleSpotlight
        case "m":      self = .toggleZoom
        case "s":      self = .swapScreens
        case "d":      self = .pen
        case "h":      self = .highlighter
        case "e":      self = .eraser
        case "z":      self = .undoDrawing
        case "x":      self = .clearDrawing
        case let c? where c.count == 1 && c.first!.isASCII && c.first!.isNumber:
            self = .digit(Int(c)!)
        default: return nil
        }
    }
}
