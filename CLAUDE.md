# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

PDF Presenter is a small native macOS app (SwiftUI + PDFKit) that presents PDF slides: audience view full screen on a chosen display, presenter view with current/next slide, upcoming pages, speaker notes and timer. Clickers work (they emulate keyboard keys). Display selection and the presentation window are derived from `../Slidescape` (`Views/Present/`).

UI strings and docs are German; code, comments and commit messages are English.

## Commands

```bash
xcodegen generate     # regenerate PDFPresenter.xcodeproj from project.yml — required after adding/removing files
xcodebuild -project PDFPresenter.xcodeproj -scheme PDFPresenter build
xcodebuild test -project PDFPresenter.xcodeproj -scheme PDFPresenter CODE_SIGN_IDENTITY=-
xcodebuild test ... -only-testing:PDFPresenterTests/SlideDeckTests    # single test class
```

## Architecture

```
PDFPresenterApp       DocumentGroup(viewing: PDFFile) — read-only, the PDF is never written
ContentView           per window: BrowseView (page list, preview, notes editor) or PresenterView
PresentationSession   @MainActor ObservableObject: current page, frozen audience page, black/white
                      screen, typed page number, overview, PresentationTimer, LaserPointer,
                      FileWatcher → reloadFromDisk(); handle(PresentKeyAction)
PresentationController audience window (borderless on a display, or windowed for rehearsal),
                      NSEvent monitor for keys/clicks, display sleep off, presenter full screen
PresentationScreens   connected displays + persisted choice (UserDefaults)
SlideDeck             PDFDocument, page labels, NotesLayout, notes (pdfpc sidecar + PDF annotations)
PageRenderer          vector drawing of a PageRegion (PDFPageView) and bitmaps
ThumbnailRenderer     actor with its own PDFDocument copy: thumbnails off the main thread
TalkPlan / TalkLimit  remaining time, pace, talk progress; LastPageStore (UserDefaults)
```

## Conventions

- **Keys:** all presentation keys go through `PresentKeyAction` → `PresentationSession.handle`. ⌘/⌥/⌃ combinations are never handled (menu shortcuts keep working). `handle(.exit)` returns false when there is nothing left to close — only then the controller ends the presentation. Keys are ignored while an `NSText` is first responder (notes editor in the presenter view), except Page Up / Page Down (`isClickerPageKey`) so a clicker keeps working.
- **Notes:** the editable source is the pdfpc sidecar (`talk.pdf` → `talk.pdfpc`, format 2). `PdfpcFile` keeps every key it doesn't interpret — don't drop unknown keys. Text annotations in the PDF are read-only notes and are hidden (`shouldDisplay = false`) so the audience doesn't see their icons. Beamer overlays (consecutive pages with equal labels) share one note via `noteOwner(for:)`.
- **No document undo:** text input must not use the window's/document's `UndoManager` (marks the read-only PDF as edited, autosave fails). Use `NotesTextView` (own undo manager), not `TextEditor`.
- **Beamer notes on page:** `NotesLayout` picks the slide half (`slideRegion`) for the audience and the notes half for the presenter. Regions are in y-up page display space (rotation applied).
- **Rendering:** large views draw vectors via `PDFPageView` (`PageRenderer.draw`); lists use `SlideDeck.thumbnail` (NSCache). `PDFPage.draw(with:to:)` already applies rotation and moves the crop box to the origin.
- **Audience page:** the audience shows `session.audienceIndex` (frozen page or current), never `currentIndex` directly.
- **Laser pointer:** `LaserPointer` is a separate ObservableObject so mouse moves don't re-render the presenter view. Positions are normalized to the shown slide region (0…1, y down) so views of different sizes agree. Mouse tracking uses an AppKit tracking area with `.activeAlways` (`LaserPointerLayer`) — SwiftUI hover doesn't fire in the presenter window while the audience window is key.
- **Links:** `PDFLinks` maps a normalized slide point to PDF page space (`page.transform(for: .cropBox)` inverted — handles rotation and Beamer half regions) and resolves `LinkTarget`. Audience clicks are resolved in the controller's event monitor (link first, else next); the presenter's current slide uses `LaserPointerLayer(onClick:)`. `PDFPage.document` is weak — tests must keep the `PDFDocument` alive.
- **Swapping displays:** `PresentationController.swapScreens()`, targets from `swapTargets` (if both windows share a display, the presenter moves away — the way back from a covered presenter view). A full-screen presenter window must leave full screen before it can move; AppKit restores the old frame right after `didExitFullScreenNotification`, so the move happens on the next run-loop turn and full screen is re-entered only once the window is on the target display.
- **Display changes:** never adopt whatever display the system moved the audience window to (`windowDidChangeScreen`) — `updateAudiencePlacement()` decides via `audiencePlacement(intended:presenter:available:)` (debounced 300 ms): own display, else a free non-presenter display, else hidden (`session.audienceDisconnected`). `audienceDisplayID` survives a disconnect so the view returns; it only changes on swap or when leaving the presenter's display.
- **Drawing:** `Drawings` (own ObservableObject, like `LaserPointer`) stores strokes per page in normalized slide coordinates; widths are fractions of the slide width. `DrawingLayer` must sit *above* `LaserPointerLayer` (whose click handler would otherwise take the drags); its AppKit input view accepts first mouse. While a tool is active the controller lets audience clicks through instead of advancing. Not persisted.
- **Reload:** `FileWatcher` re-arms after rename/delete (atomic saves) and debounces chunked writes. `SlideDeck.reload(pdf:)` swaps pages/labels and bumps `revision`; anything caching per page must key on `revision`. Unparseable files are ignored (old version stays).
- **Thumbnails:** never render PDFKit objects of the main-thread `SlideDeck.pdf` off the main thread — the `ThumbnailRenderer` actor owns a separate `PDFDocument` built from the same data (recreated on reload; results from before a reload are dropped via `revision`).
- **Sidecar keys:** `duration` / `endTime` ("HH:MM") are pdfpc's; the talk's end page is our own `pdfpresenterEndPage` (pdfpc's `endSlide` counts user slides — not mapped). The last shown page lives in UserDefaults (`LastPageStore`), so merely viewing a PDF never creates a sidecar.
- **Timer start:** `timerStartsOnFirstTurn` (UserDefaults, default true): `begin()` arms the timer, the first change of `currentIndex` starts it.
- **Tests** build PDFs in code (`PDFFixture`: page labels, text annotations, red/blue halves).
