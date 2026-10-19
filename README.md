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
  - **Slide times:** how long the audience saw each slide (overlays together, talk time only – pauses and waiting for the first page turn don't count). The presenter view shows the current slide's time next to the timer; afterwards the page list and the overview show it per slide, and *Presentation → Slide Times…* (or the stopwatch in the toolbar) lists all slides with bars, the total and “Copy as Text”. Starts over with a new presentation or R; kept in memory only.
  - **Skip slides:** right-click a page in the page list or the overview → “Skip Slide in Presentation” (applies to all overlays of the slide). Paging (keys, clicks, clickers) passes over skipped pages; “Up Next”, the upcoming pages and the schedule leave them out; jumps (page number, overview, links, Home/End) still reach them. Stored as pdfpc's `hidden` in the `.pdfpc` file, so pdfpc skips them too.
- **Remember the last page:** a PDF opens where you left off.
  - **Freeze (F):** the audience keeps the current slide while you browse in the presenter view (e.g. for questions). F or Esc again shows your slide again.
  - **Laser pointer (L):** the mouse pointer over the current slide (presenter view or audience) appears as a red dot for the audience – also with clickers that move the mouse pointer.
  - **Spotlight (C):** the slide is dimmed for the audience except a soft circle around the mouse pointer (the presenter view shows it lighter); same tracking as the laser pointer, so it works from either window and while zoomed. Size in *Settings*. L and C switch between dot and spotlight.
  - **Zoom (M):** drag a rectangle on the current slide of the presenter view or on the audience view (or click for 2×) – the presenter view frames the slide and shows a hint while selecting; the audience sees that part enlarged, drawn as vectors (sharp). Pointer, drawings, videos and links follow. The presenter view shows the whole slide with the zoomed part framed. M, Esc or a page turn return to the whole slide.
  - **Swap displays (S):** audience and presenter view switch displays (wrong projector detected, cables swapped). The choice is remembered.
  - **Links in the PDF** (table of contents, Beamer navigation, URLs) are clickable – in the audience view and on the current slide of the presenter view. Internal links jump to the page, URLs open the browser, “Back” actions return to the page before the last link. A click outside a link advances the audience view.
  - **Unplugging and replugging the projector:** the presentation keeps running. If the projector goes away, the audience view is hidden (or moves to a free third display), the presenter view stays visible and shows a notice. When the projector comes back, the audience view reappears there. If the projector is only plugged in during the presentation (started on the laptop alone), the audience view moves to it.
  - **Drawing:** pen (D), highlighter (H), eraser (E) – on the current slide of the presenter view or directly on the audience view. Colors via the color button, Z removes the slide's last stroke, X all of them. Esc ends drawing mode. Drawings are kept per slide while the document is open, but are not saved.
  - **Transitions from the PDF** (e.g. LaTeX Beamer `\transdissolve`, `\transwipe`, `\transpush`, `\transsplit…`, `\transbox…`, `\transblinds…`, `\transcover`, `\transuncover`) are played in the audience view – when advancing to the immediately following page; going back and jumps switch instantly. Can be turned off in the *Presentation* menu. Automatic advancing (`\transduration`) is not supported.
- **Settings** (⌘,): display, rehearsal window, presenter full screen, transitions, timer start, presenter layout and notes text size in one window (the menus offer the same options).
- **Help:** menu *Help → Presently Help* opens a help window with topics, search and the key list.
- **Updates** via [Sparkle](https://sparkle-project.org): Presently checks for new versions once a day and offers to install them; *Presently → Check for Updates…* checks right away. Automatic checks can be turned off in *Settings → Updates*.
- **Videos in the PDF** play inside the slide (audience view and current slide of the presenter view, one sound): LaTeX Beamer `\movie` (`multimedia` package; options `autostart`, `loop`/`repeat`/`palindrome`, `start`, `duration`, `showcontrols`), `\movie[externalviewer]` and pdfpc-style links `\href{run:clip.mp4?autostart&loop&start=5&stop=12}{…}`. Video files are external, next to the PDF; formats macOS can play (MP4, MOV, M4V …). A click on a video plays or pauses it instead of advancing; the presenter view shows a progress bar. Leaving the slide stops it. Not supported: `\sound`, `\hyperlinkmovie`, embedded media (media9/RichMedia).
- **Automatic reload:** if the PDF changes on disk (e.g. LaTeX recompiled), it is reloaded; the current page and the notes are kept. Half-written files are ignored.
- **Notes**
  - are stored in pdfpc format next to the PDF (`talk.pdf` → `talk.pdfpc`) – compatible with [pdfpc](https://pdfpc.github.io);
  - text annotations in the PDF (comments, `\pdfpcnote`) are shown as notes and hidden from the audience;
  - LaTeX Beamer with `show notes on second screen=right` (or left/top/bottom): the audience sees only the slide half, the notes half appears in the presenter view. Wide pages are detected automatically; set it manually in the menu *Presentation → Beamer Notes*. If the setting doesn't match the page format, a notice with “Show Whole Page” appears.
  - Beamer overlays (same page label) share one note;
  - editable during the presentation too: pencil icon or double-click on the notes, Esc ends editing. Page Up/Page Down (clicker) still turn pages meanwhile.

## Typst slides (Touying, Polylux)

Typst writes page labels for overlays (`#pause`, `#uncover` …), so overlays work as with Beamer; so do notes on a second screen (`config-common(show-notes-on-second-screen: right)`) and video links (`#link("run:clip.mp4?autostart")[…]`). Typst can't put speaker notes, skipped slides or transitions into the PDF itself – Touying and Polylux collect them as pdfpc metadata. Export it next to the PDF:

```bash
typst eval 'query(<pdfpc-file>).first().value' --in talk.typ > talk.pdfpc   # Typst 0.14+; older: typst query talk.typ --field value --one "<pdfpc-file>"
```

(Touying: `config-common(enable-pdfpc: true)`, notes with `#speaker-note[…]`; Polylux: `#pdfpc.speaker-note(…)`.) Presently then shows the notes (a note on any overlay applies to the whole slide), skips `hidden` slides, takes `duration` / `endTime` / `endSlide`, plays `defaultTransition` (pdfpc's `type:duration:angle:alignment:direction`) on every page turn and honors `disableMarkdown`. Notes edited in Presently go into the same file; exporting again from Typst overwrites them.

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
| C | spotlight on/off |
| M | zoom: select a part of the slide (drag or click) / whole slide again |
| S | swap displays |
| D / H / E | pen / highlighter / eraser (again: off) |
| Z / X | remove last stroke / all drawings on the slide |
| Esc | end note editing/input/overview/drawing mode/zoom/black screen/freeze, otherwise end the presentation |

Clickers usually send Page Up/Page Down, B or “.”, and F5/Esc for start/stop – all covered.

## Development

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Presently.xcodeproj -scheme Presently -skipPackagePluginValidation build
xcodebuild test -project Presently.xcodeproj -scheme Presently -skipPackagePluginValidation CODE_SIGN_IDENTITY=-
```

SwiftLint runs in every build as a package plugin (Xcode asks once to trust it; on the command line `-skipPackagePluginValidation` does that). `brew install swiftlint` and `swiftlint` lint without building.

## License

MIT – see [LICENSE](LICENSE).
