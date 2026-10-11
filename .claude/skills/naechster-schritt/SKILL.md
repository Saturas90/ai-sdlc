---
name: naechster-schritt
description: Orchestrator des SDLC-Workflows. Erkennt anhand vorhandener Dateien den Stand des aktuellen Issues/Projekts und startet die passende nächste Phase (Projektplan → Issue → optional Architektur → Impl-Plan → Implementierung → Abschluss). Nutzen, wenn unklar ist, was als Nächstes zu tun ist, oder um den Workflow zu treiben.
---

# Orchestrator: Nächster Schritt

Ziel: den korrekten nächsten Workflow-Schritt bestimmen und **nur diesen** anstoßen — token­sparsam, ohne Inhalte breit einzulesen.

## Stand erkennen

Prüfe **nur** Datei-Existenz, die Statuszeile `**Status:** Freigegeben`, Checkboxen und die
Projektplan-Status-Spalte (Marker: `konventionen.md` → „Status- & Freigabe-Marker“). Keine Inhalte breit einlesen.
„Freigegeben“ heißt: die Datei enthält die Zeile `**Status:** Freigegeben` — nicht das bloße Wort.

1. Kein `projektplan.md` → **Projektplan** → `/projektplan`.
2. **Alle** Projektplan-Issues haben Status `erledigt` → **Projekt fertig**, terminieren (nichts weiter tun, dem Nutzer melden).
3. Sonst **aktives Issue** = erste Projektplan-Zeile mit Status ≠ `erledigt`. Für dieses Issue der Reihe nach:
   1. kein `issues/IS-<NNN>-*/issue.md` → **Issue** → `/issue`.
   2. `issue.md` ohne `**Status:** Freigegeben` **oder** offene `- [ ]` im Abschnitt „Offene Fragen“ → im Issue-Schritt bleiben (Review/Fragen/Freigabe offen) → `/issue`.
   3. „Architekturplan nötig: ja“ und `architektur.md` fehlt bzw. ohne `**Status:** Freigegeben` bzw. mit offenen „Offene Fragen“ → **Architektur** → `/architektur`.
   4. `impl-plan.md` fehlt bzw. ohne `**Status:** Freigegeben` bzw. mit offenen „Offene Fragen“ → **Impl-Plan** → `/impl-plan`.
   5. `impl-plan.md` freigegeben mit offenen `[ ]`-**Schritten** → **Implementierung** → `/implementieren`.
   6. alle Impl-Schritte `[x]`, keine `zusammenfassung.md` → **Abschluss** → `/abschluss`.
   7. `zusammenfassung.md` vorhanden, aber Projektplan-Status noch ≠ `erledigt` → Status via `mechaniker` auf `erledigt` setzen (im Arbeitsbaum-Modus vorher `git diff --quiet -- projektplan.md` — zeigt es fremde Änderungen, anhalten und den Menschen fragen), danach die Tests und Gate-Schritte, die `projektplan.md` lesen (`~/.claude/ai-sdlc/konventionen.md` › Tests & Gates), dann sofort committen (via `mechaniker`, im Arbeitsbaum-Modus per `wt commit`), dann zurück zu 2.

Hinweis: „offene `- [ ]`“ ist je nach Abschnitt zu unterscheiden — Akzeptanzkriterien und Impl-Schritte sind eigene Checkbox-Listen; für das Fragen-Gate zählt nur der Abschnitt „Offene Fragen“.

Hat das aktive Issue eine `kontext.md`, nur deren Abschnitt „Stand“ lesen bzw. die dort verwiesene
projekteigene Übergabe (nächster Schritt, offene Entscheidungen, ggf. laufendes Gate mit Runde). Ein laufendes Gate setzt die Phase dort fort, statt den
Entwurf neu zu erzeugen. Widerspricht der Stand Markern, Häkchen oder git: nicht raten, sondern nachfragen.

**Arbeitsbaum-Modus** (Projekt-CLAUDE.md hat `## Arbeitsbäume (ai-sdlc)`, Regeln in
`~/.claude/ai-sdlc/arbeitsbaeume.md`; `wt` = `pwsh -NoProfile -File "$HOME/.claude/ai-sdlc/tools/wt.ps1"`, nie
das Programm `wt`, Ergebnis nur mit Schlusszeile `WT: …` werten): zusätzlich einmal `wt status`. Hat ein Issue
einen Worktree, Häkchen und Stand dort lesen (Pfad aus `wt status`). Uncommittete Dateien oder Änderungen der
letzten 30 Minuten im Worktree, bei einem Issue in Planung im Issue-Ordner des Hauptcheckouts → fragen, ob eine
andere Session daran arbeitet. Bei mehreren parallelen Sessions das Issue als Argument übernehmen; ohne
Argument ist das aktive Issue das erste nicht erledigte, an dem keine andere Session arbeitet. Nicht
integrierte Commits auf dem Issue-Branch gehen Regel 3.6 vor → `/implementieren`: bei `je Einheit` integriert
es zuerst und arbeitet dann weiter; bei `**Integration:** am Ende` arbeitet es ohne Vorab-Integration weiter,
solange Schritte offen sind, und integriert nach dem letzten `[x]` (Schlussintegration). `/abschluss` erst,
wenn `wt status` den Branch als integriert zeigt (Worktree-Zeile mit `integriert` bzw. „Branch integriert,
ohne Worktree“).

## Regeln

- An jedem menschlichen Freigabe-Gate **anhalten** und nachfragen; nicht eigenmächtig über Gates hinweg arbeiten (stehende Freigabe: `konventionen.md`).
- Immer nur **einen** Schritt anstoßen, nicht mehrere Phasen auf einmal.
- Eine Session je Phase bzw. Impl-Einheit: Ist die laufende Session schon groß, nach dem nächsten Gate eine neue vorschlagen, statt weiterzuarbeiten.
- Konventionen: `~/.claude/ai-sdlc/konventionen.md` (nur bei Bedarf lesen).

## Modell-Hinweis (Kosten)

Orchestrierung und Status-Erkennung sind leichtgewichtig → Session ruhig auf **Sonnet** laufen lassen. Teure Modelle nur dort, wo die Phase sie vorgibt (Architektur = Opus). Die Phasen delegieren die eigentliche Arbeit an spezialisierte Sub-Agenten mit passendem Modell; Erhebungen an `rechercheur`, nie an `general-purpose`.
