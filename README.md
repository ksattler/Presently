# Presently

[![Tests](https://github.com/ksattler/Presently/actions/workflows/tests.yml/badge.svg)](https://github.com/ksattler/Presently/actions/workflows/tests.yml)

Small macOS app (macOS 14 or later) for presenting PDF slides.

## Features

- **Open a PDF** (⌘O, drag & drop onto the Dock icon, “Open Recent”). Page list, large preview, notes editor.
- **Present** with ⌘⏎, F5 or ▶︎ in the toolbar.
  - **Choose a display:** toolbar or menu *Presentation → Present On*. With several displays, “Automatic” picks the one the document window is *not* on. The choice is remembered.
  - **Rehearsal:** “Audience View in a Window” opens the audience view as a regular window.
  - **Presenter view** in the document window (optionally full screen): current and next slide, the upcoming pages, notes (Markdown, adjustable font size), elapsed time (can be paused), clock, overview of all pages.
  - **Adjust the layout:** the dividers between the current slide and the page column and between the next slide and the notes can be dragged. In the *View* menu (top): current slide left/right, show/hide next slide and notes, number of upcoming pages (0–8), reset. Applies to all documents.
  - **Schedule** (hourglass icon): talk duration *or* end time. Shows the remaining time and whether you are ahead of or behind schedule (slide progress versus time; overlays don't count separately). By default the timer only starts with the first page turn – you can open the presentation early and wait on the title slide.
  - **End of talk / backup:** right-click a page in the page list → “Talk Ends Here”. Later pages count as backup (dimmed, notice in the presenter view), don't count toward the schedule, and *End* jumps to the end of the talk first.
- **Remember the last page:** a PDF opens where you left off.
  - **Freeze (F):** the audience keeps the current slide while you browse in the presenter view (e.g. for questions). F or Esc again shows your slide again.
  - **Laser pointer (L):** the mouse pointer over the current slide (presenter view or audience) appears as a red dot for the audience – also with clickers that move the mouse pointer.
  - **Swap displays (S):** audience and presenter view switch displays (wrong projector detected, cables swapped). The choice is remembered.
  - **Links in the PDF** (table of contents, Beamer navigation, URLs) are clickable – in the audience view and on the current slide of the presenter view. Internal links jump to the page, URLs open the browser, “Back” actions return to the page before the last link. A click outside a link advances the audience view.
  - **Unplugging and replugging the projector:** the presentation keeps running. If the projector goes away, the audience view is hidden (or moves to a free third display), the presenter view stays visible and shows a notice. When the projector comes back, the audience view reappears there. If the projector is only plugged in during the presentation (started on the laptop alone), the audience view moves to it.
  - **Drawing:** pen (D), highlighter (H), eraser (E) – on the current slide of the presenter view or directly on the audience view. Colors via the color button, Z removes the slide's last stroke, X all of them. Esc ends drawing mode. Drawings are kept per slide while the document is open, but are not saved.
  - **Transitions from the PDF** (e.g. LaTeX Beamer `\transdissolve`, `\transwipe`, `\transpush`, `\transsplit…`, `\transbox…`, `\transblinds…`, `\transcover`, `\transuncover`) are played in the audience view – when advancing to the immediately following page; going back and jumps switch instantly. Can be turned off in the *Presentation* menu. Automatic advancing (`\transduration`) is not supported.
- **Settings** (⌘,): display, rehearsal window, presenter full screen, transitions, timer start, presenter layout and notes text size in one window (the menus offer the same options).
- **Help:** menu *Help → Presently Help* opens a help window with topics, search and the key list.
- **Automatic reload:** if the PDF changes on disk (e.g. LaTeX recompiled), it is reloaded; the current page and the notes are kept. Half-written files are ignored.
- **Notes**
  - are stored in pdfpc format next to the PDF (`talk.pdf` → `talk.pdfpc`) – compatible with [pdfpc](https://pdfpc.github.io);
  - text annotations in the PDF (comments, `\pdfpcnote`) are shown as notes and hidden from the audience;
  - LaTeX Beamer with `show notes on second screen=right` (or left/top/bottom): the audience sees only the slide half, the notes half appears in the presenter view. Wide pages are detected automatically; set it manually in the menu *Presentation → Beamer Notes*. If the setting doesn't match the page format, a notice with “Show Whole Page” appears.
  - Beamer overlays (same page label) share one note;
  - editable during the presentation too: pencil icon or double-click on the notes, Esc ends editing. Page Up/Page Down (clicker) still turn pages meanwhile.

## Keys (also presenters/clickers)

| Key | Action |
|---|---|
| → ↓ Page Down Space Click (outside links) | next |
| ← ↑ Page Up ⌫ Right-click | previous |
| ⇧ → / ⇧ ← | next / previous slide (skip overlays) |
| Home / End | first page / end of talk, End again: last page |
| Number + ⏎ | go to slide (label) or page |
| B or . / W or , | black / white screen (again: back) |
| Tab or O | overview |
| P / R | pause / reset timer |
| F | freeze audience view |
| L | laser pointer on/off |
| S | swap displays |
| D / H / E | pen / highlighter / eraser (again: off) |
| Z / X | remove last stroke / all drawings on the slide |
| Esc | end note editing/input/overview/drawing mode/black screen/freeze, otherwise end the presentation |

Clickers usually send Page Up/Page Down, B or “.”, and F5/Esc for start/stop – all covered.

## Development

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Presently.xcodeproj -scheme Presently build
xcodebuild test -project Presently.xcodeproj -scheme Presently CODE_SIGN_IDENTITY=-
```

## License

MIT – see [LICENSE](LICENSE).
