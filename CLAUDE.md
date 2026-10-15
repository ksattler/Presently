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
PresentationSession   @MainActor ObservableObject: current page, black/white screen, typed page
                      number, overview, PresentationTimer; handle(PresentKeyAction)
PresentationController audience window (borderless on a display, or windowed for rehearsal),
                      NSEvent monitor for keys/clicks, display sleep off, presenter full screen
PresentationScreens   connected displays + persisted choice (UserDefaults)
SlideDeck             PDFDocument, page labels, NotesLayout, notes (pdfpc sidecar + PDF annotations)
PageRenderer          vector drawing of a PageRegion (PDFPageView) and cached thumbnails
```

## Conventions

- **Keys:** all presentation keys go through `PresentKeyAction` → `PresentationSession.handle`. ⌘/⌥/⌃ combinations are never handled (menu shortcuts keep working). `handle(.exit)` returns false when there is nothing left to close — only then the controller ends the presentation. Keys are ignored while an `NSText` is first responder.
- **Notes:** the editable source is the pdfpc sidecar (`talk.pdf` → `talk.pdfpc`, format 2). `PdfpcFile` keeps every key it doesn't interpret — don't drop unknown keys. Text annotations in the PDF are read-only notes and are hidden (`shouldDisplay = false`) so the audience doesn't see their icons. Beamer overlays (consecutive pages with equal labels) share one note via `noteOwner(for:)`.
- **No document undo:** text input must not use the window's/document's `UndoManager` (marks the read-only PDF as edited, autosave fails). Use `NotesTextView` (own undo manager), not `TextEditor`.
- **Beamer notes on page:** `NotesLayout` picks the slide half (`slideRegion`) for the audience and the notes half for the presenter. Regions are in y-up page display space (rotation applied).
- **Rendering:** large views draw vectors via `PDFPageView` (`PageRenderer.draw`); lists use `SlideDeck.thumbnail` (NSCache). `PDFPage.draw(with:to:)` already applies rotation and moves the crop box to the origin.
- **Tests** build PDFs in code (`PDFFixture`: page labels, text annotations, red/blue halves).
