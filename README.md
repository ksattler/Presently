# PDF Presenter

Kleine macOS-App (ab macOS 14) zum Präsentieren von PDF-Folien.

## Funktionen

- **PDF öffnen** (⌘O, Drag & Drop aufs Dock-Symbol, „Zuletzt benutzt“). Seitenliste, große Vorschau, Notizen-Editor.
- **Präsentieren** mit ⌘⏎, F5 oder ▶︎ in der Symbolleiste.
  - **Bildschirm wählen:** Symbolleiste oder Menü *Präsentation → Präsentieren auf*. „Automatisch“ nimmt bei mehreren Bildschirmen den, auf dem das Dokumentfenster *nicht* liegt. Die Wahl bleibt gespeichert.
  - **Probe:** „Publikumsansicht im Fenster“ öffnet die Publikumsansicht als normales Fenster.
  - **Referentenansicht** im Dokumentfenster (optional im Vollbild): aktuelle und nächste Folie, die folgenden Seiten, Notizen (Markdown, Schriftgröße einstellbar), verstrichene Zeit (anhaltbar), Restzeit bei gesetzter Vortragsdauer, Uhrzeit, Übersicht aller Seiten.
  - **Einfrieren (F):** Das Publikum behält die aktuelle Folie, während du in der Referentenansicht blätterst (z. B. bei Rückfragen). Nochmal F oder Esc zeigt wieder deine Folie.
  - **Laserpointer (L):** Der Mauszeiger über der aktuellen Folie (Referentenansicht oder Publikum) erscheint als roter Punkt beim Publikum – auch mit Klickern, die den Mauszeiger bewegen.
- **Automatisch neu laden:** Ändert sich das PDF auf der Platte (z. B. LaTeX neu kompiliert), wird es neu geladen; die aktuelle Seite und die Notizen bleiben. Halb geschriebene Dateien werden ignoriert.
- **Notizen**
  - werden im pdfpc-Format neben dem PDF gespeichert (`vortrag.pdf` → `vortrag.pdfpc`) – kompatibel mit [pdfpc](https://pdfpc.github.io);
  - Text-Annotationen im PDF (Kommentare, `\pdfpcnote`) werden als Notizen angezeigt und für das Publikum ausgeblendet;
  - LaTeX-Beamer mit `show notes on second screen=right` (bzw. left/top/bottom): das Publikum sieht nur die Folienhälfte, die Notizhälfte erscheint in der Referentenansicht. Breite Seiten werden automatisch erkannt.
  - Beamer-Overlays (gleiche Seitenbeschriftung) teilen sich eine Notiz;
  - auch während der Präsentation bearbeitbar: Stift-Symbol oder Doppelklick auf die Notizen, Esc beendet das Bearbeiten. Bild↑/Bild↓ (Klicker) blättern dabei weiter.

## Tasten (auch Presenter/Klicker)

| Taste | Funktion |
|---|---|
| → ↓ Bild↓ Leertaste Klick | weiter |
| ← ↑ Bild↑ ⌫ Rechtsklick | zurück |
| ⇧ → / ⇧ ← | nächste / vorige Folie (Overlays überspringen) |
| Pos1 / Ende | erste / letzte Seite |
| Nummer + ⏎ | zu Folie (Beschriftung) bzw. Seite springen |
| B oder . / W oder , | Schwarz- / Weißbild (nochmal: zurück) |
| Tab oder O | Übersicht |
| P / R | Timer anhalten / zurücksetzen |
| F | Publikumsansicht einfrieren |
| L | Laserpointer an/aus |
| Esc | Notiz-Bearbeitung/Eingabe/Übersicht/Schwarzbild/Einfrieren beenden, sonst Präsentation beenden |

Klicker senden in der Regel Bild↑/Bild↓, B bzw. „.“ und F5/Esc für Start/Stopp – alles abgedeckt.

## Entwicklung

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project PDFPresenter.xcodeproj -scheme PDFPresenter build
xcodebuild test -project PDFPresenter.xcodeproj -scheme PDFPresenter CODE_SIGN_IDENTITY=-
```
