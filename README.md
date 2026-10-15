# PDF Presenter

Kleine macOS-App (ab macOS 14) zum Präsentieren von PDF-Folien.

## Funktionen

- **PDF öffnen** (⌘O, Drag & Drop aufs Dock-Symbol, „Zuletzt benutzt“). Seitenliste, große Vorschau, Notizen-Editor.
- **Präsentieren** mit ⌘⏎, F5 oder ▶︎ in der Symbolleiste.
  - **Bildschirm wählen:** Symbolleiste oder Menü *Präsentation → Präsentieren auf*. „Automatisch“ nimmt bei mehreren Bildschirmen den, auf dem das Dokumentfenster *nicht* liegt. Die Wahl bleibt gespeichert.
  - **Probe:** „Publikumsansicht im Fenster“ öffnet die Publikumsansicht als normales Fenster.
  - **Referentenansicht** im Dokumentfenster (optional im Vollbild): aktuelle und nächste Folie, die folgenden Seiten, Notizen (Markdown, Schriftgröße einstellbar), verstrichene Zeit (anhaltbar), Uhrzeit, Übersicht aller Seiten.
  - **Aufbau anpassen:** Die Trenner zwischen aktueller Folie und Seitenspalte sowie zwischen nächster Folie und Notizen lassen sich ziehen. Im Menü *Ansicht* (oben): aktuelle Folie links/rechts, nächste Folie und Notizen ein-/ausblenden, Anzahl der folgenden Seiten (0–8), Zurücksetzen. Gilt für alle Dokumente.
  - **Zeitplan** (Sanduhr-Symbol): Vortragsdauer *oder* Endzeit. Angezeigt werden Restzeit und ob du vor oder hinter dem Plan liegst (Folienfortschritt gegenüber Zeit, Overlays zählen nicht extra). Der Timer startet standardmäßig erst beim ersten Blättern – du kannst die Präsentation vorher öffnen und auf der Titelfolie warten.
  - **Vortragsende / Backup:** Rechtsklick auf eine Seite in der Seitenliste → „Vortrag endet hier“. Spätere Seiten gelten als Backup (blasser, Hinweis in der Referentenansicht), zählen nicht zum Zeitplan, und *Ende* springt zuerst zum Vortragsende.
- **Letzte Seite merken:** Ein PDF öffnet dort, wo du zuletzt warst.
  - **Einfrieren (F):** Das Publikum behält die aktuelle Folie, während du in der Referentenansicht blätterst (z. B. bei Rückfragen). Nochmal F oder Esc zeigt wieder deine Folie.
  - **Laserpointer (L):** Der Mauszeiger über der aktuellen Folie (Referentenansicht oder Publikum) erscheint als roter Punkt beim Publikum – auch mit Klickern, die den Mauszeiger bewegen.
  - **Bildschirme tauschen (S):** Publikum und Referentenansicht wechseln die Displays (falscher Beamer erkannt, Kabel vertauscht). Die Wahl wird gespeichert.
  - **Links im PDF** (Inhaltsverzeichnis, Beamer-Navigation, URLs) sind anklickbar – in der Publikumsansicht und auf der aktuellen Folie der Referentenansicht. Interne Links springen zur Seite, URLs öffnen den Browser, „Zurück“-Aktionen gehen zur Seite vor dem letzten Link. Ein Klick außerhalb eines Links blättert beim Publikum weiter.
  - **Beamer ab- und anstecken:** Die Präsentation läuft weiter. Fällt der Beamer weg, wird die Publikumsansicht ausgeblendet (oder wandert auf einen freien dritten Bildschirm), die Referentenansicht bleibt sichtbar und zeigt einen Hinweis. Kommt der Beamer zurück, erscheint die Publikumsansicht wieder dort. Wird der Beamer erst während der Präsentation eingesteckt (Start nur am Laptop), wandert die Publikumsansicht auf ihn.
  - **Zeichnen:** Stift (D), Textmarker (H), Radierer (E) – auf der aktuellen Folie der Referentenansicht oder direkt auf der Publikumsansicht. Farben über den Farbknopf, Z entfernt den letzten Strich der Folie, X alle. Esc beendet den Zeichenmodus. Zeichnungen bleiben pro Folie erhalten, solange das Dokument offen ist, werden aber nicht gespeichert.
  - **Übergänge aus dem PDF** (z. B. LaTeX Beamer `\transdissolve`, `\transwipe`, `\transpush`, `\transsplit…`, `\transbox…`, `\transblinds…`, `\transcover`, `\transuncover`) werden in der Publikumsansicht abgespielt – beim Weiterblättern auf die direkt folgende Seite; Zurück und Sprünge wechseln sofort. Abschaltbar im Menü *Präsentation*. Automatisches Weiterblättern (`\transduration`) wird nicht unterstützt.
- **Automatisch neu laden:** Ändert sich das PDF auf der Platte (z. B. LaTeX neu kompiliert), wird es neu geladen; die aktuelle Seite und die Notizen bleiben. Halb geschriebene Dateien werden ignoriert.
- **Notizen**
  - werden im pdfpc-Format neben dem PDF gespeichert (`vortrag.pdf` → `vortrag.pdfpc`) – kompatibel mit [pdfpc](https://pdfpc.github.io);
  - Text-Annotationen im PDF (Kommentare, `\pdfpcnote`) werden als Notizen angezeigt und für das Publikum ausgeblendet;
  - LaTeX-Beamer mit `show notes on second screen=right` (bzw. left/top/bottom): das Publikum sieht nur die Folienhälfte, die Notizhälfte erscheint in der Referentenansicht. Breite Seiten werden automatisch erkannt; von Hand im Menü *Präsentation → Beamer-Notizen*. Passt die Einstellung nicht zum Seitenformat, erscheint ein Hinweis mit „Ganze Seite zeigen“.
  - Beamer-Overlays (gleiche Seitenbeschriftung) teilen sich eine Notiz;
  - auch während der Präsentation bearbeitbar: Stift-Symbol oder Doppelklick auf die Notizen, Esc beendet das Bearbeiten. Bild↑/Bild↓ (Klicker) blättern dabei weiter.

## Tasten (auch Presenter/Klicker)

| Taste | Funktion |
|---|---|
| → ↓ Bild↓ Leertaste Klick (außerhalb von Links) | weiter |
| ← ↑ Bild↑ ⌫ Rechtsklick | zurück |
| ⇧ → / ⇧ ← | nächste / vorige Folie (Overlays überspringen) |
| Pos1 / Ende | erste Seite / Vortragsende, nochmal Ende: letzte Seite |
| Nummer + ⏎ | zu Folie (Beschriftung) bzw. Seite springen |
| B oder . / W oder , | Schwarz- / Weißbild (nochmal: zurück) |
| Tab oder O | Übersicht |
| P / R | Timer anhalten / zurücksetzen |
| F | Publikumsansicht einfrieren |
| L | Laserpointer an/aus |
| S | Bildschirme tauschen |
| D / H / E | Stift / Textmarker / Radierer (nochmal: aus) |
| Z / X | letzten Strich / alle Zeichnungen der Folie entfernen |
| Esc | Notiz-Bearbeitung/Eingabe/Übersicht/Zeichenmodus/Schwarzbild/Einfrieren beenden, sonst Präsentation beenden |

Klicker senden in der Regel Bild↑/Bild↓, B bzw. „.“ und F5/Esc für Start/Stopp – alles abgedeckt.

## Entwicklung

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project PDFPresenter.xcodeproj -scheme PDFPresenter build
xcodebuild test -project PDFPresenter.xcodeproj -scheme PDFPresenter CODE_SIGN_IDENTITY=-
```
