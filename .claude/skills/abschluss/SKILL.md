---
name: abschluss
description: Schließt ein Issue ab: erstellt eine kurze Zusammenfassung (zusammenfassung.md) und gleicht Issue ↔ Architektur ↔ Impl-Plan ↔ Implementierung ab (Scope-Treue).
---

# Skill: Abschluss

Voraussetzung: alle Impl-Plan-Schritte `[x]`. Im Arbeitsbaum-Modus (`~/.claude/ai-sdlc/arbeitsbaeume.md`;
`wt` = `pwsh -NoProfile -File "$HOME/.claude/ai-sdlc/tools/wt.ps1"`, nie das Programm `wt`, Ergebnis nur mit
Schlusszeile `WT: …` werten) zusätzlich: `wt status` zeigt den Issue-Branch vollständig integriert
(Worktree-Zeile mit `integriert` bzw. „Branch integriert, ohne Worktree“); erst dann läuft der Abschluss im
Hauptcheckout, Commits per `wt commit`. Zum Schluss `wt finish -Key <KEY>` aus dem Hauptcheckout, nachdem
Fenster, Prozesse und aus dem Worktree gestartete Programme beendet sind (`arbeitsbaeume.md` Abschnitt 8).

1. Vorlage `~/.claude/ai-sdlc/vorlagen/zusammenfassung.md`. Kontext: `issue.md`, ggf. `architektur.md`, `impl-plan.md`, `kontext.md`, Commits des Issues (Liste und Diff-Statistik; Volltext nur gezielt).
2. Kurze **Zusammenfassung** schreiben: was wurde getan (bewusst knapp), Review-Ergebnis je Phase in einer Zeile, vertagte Findings aus `kontext.md` › Vertagt mit Ziel.
3. **Scope-Abgleich:** jedes Akzeptanzkriterium erfüllt? Architektur eingehalten? Impl-Plan vollständig? Nichts umgesetzt, was nicht im Issue stand? Abweichungen explizit benennen.
4. Review-Gate mit Prüftiefe S (`reviewer`) auf Zusammenfassung und Scope-Abgleich (`~/.claude/ai-sdlc/review-gate.md`); Runde mit nur mittel/niedrig → einarbeiten + Fixcheck, keine weitere Runde. Was dabei vertagt wird, direkt in der Zusammenfassung nachtragen.
5. Bei Abweichung (umgesetzt ohne Issue-Deckung): **melden** und mit dem Nutzer klären — nicht stillschweigend akzeptieren.
6. Im `projektplan.md` den Status dieses Issues auf `erledigt` setzen (via `mechaniker`) — sonst terminiert der Orchestrator nicht und könnte das Issue erneut wählen. Im Arbeitsbaum-Modus vorher `git diff --quiet -- projektplan.md` (zeigt es fremde Änderungen, anhalten und den Menschen fragen) und direkt danach Schritt 7.
7. Commit (via `mechaniker`): `IS-<NNN>: Abschluss & Zusammenfassung`. Im Arbeitsbaum-Modus vorher die zugehörigen Tests, wenn ein Test oder Gate die committeten Dateien liest.

Danach: `/naechster-schritt` für das nächste Issue.
