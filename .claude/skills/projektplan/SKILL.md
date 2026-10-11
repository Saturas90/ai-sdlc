---
name: projektplan
description: Erstellt oder aktualisiert den Projektplan (projektplan.md) mit Ziel, grobem Ablauf und der Issue-Liste (IS-Keys). Startpunkt jedes neuen Tool-Projekts im SDLC-Workflow.
---

# Skill: Projektplan

Zweck: `projektplan.md` im Projekt-Root erstellen/pflegen.

1. Kontext: `~/.claude/ai-sdlc/konventionen.md`, Vorlage `~/.claude/ai-sdlc/vorlagen/projektplan.md`.
2. Existiert `projektplan.md`? Falls ja → aktualisieren, nicht überschreiben.
3. Mit dem Nutzer klären: Ziel, Meilensteine, Issue-Liste. Je Issue: Key (`IS-<NNN>`, dreistellig), Titel, 1-Satz-Ziel, „Architektur nötig?“, Abhängigkeiten. Offene Punkte als Rückfrage — nicht raten.
4. Entwurf schreiben. Im Arbeitsbaum-Modus (`~/.claude/ai-sdlc/arbeitsbaeume.md` Abschnitt 5) entstehen Entwurf und Review in `projektplan.entwurf.md` im Hauptcheckout (bei einer Aktualisierung als Kopie von `projektplan.md`; erste Zeile `Basis: <rev>` mit dem HEAD beim Anlegen; liegt schon ein Entwurf vor, ist er uncommittet und zählt als Aktivität: erst den Menschen fragen, ob dort eine Session läuft (`arbeitsbaeume.md` Abschnitt 8), dann dort fortsetzen).
5. Review-Gate anwenden (`~/.claude/ai-sdlc/review-gate.md`), Prüftiefe S; Runde mit nur mittel/niedrig → einarbeiten + Fixcheck, keine weitere Runde; mittel/niedrig-Findings auflisten.
6. Um Freigabe bitten. Nach Freigabe committen (via `mechaniker`): `PROJEKT: Projektplan erstellt/aktualisiert`; vorher statt der Gate-Kette die Tests und Gate-Schritte, die die Datei lesen (`~/.claude/ai-sdlc/konventionen.md` › Tests & Gates). Im Arbeitsbaum-Modus vorher `git diff --quiet -- projektplan.md` (zeigt es fremde Änderungen, anhalten und den Menschen fragen), die seit der Basis committeten Änderungen (`git diff <rev> HEAD -- projektplan.md`) in den Entwurf einspielen, ihn ohne die Basis-Zeile in einem Zug nach `projektplan.md` übernehmen, diese Tests und Gate-Schritte fahren, sofort per `wt commit` festschreiben (`pwsh -NoProfile -File "$HOME/.claude/ai-sdlc/tools/wt.ps1"`, nie das Programm `wt`) und die Entwurfsdatei löschen.

Kein Scope-Creep: Der Plan **listet** Issues, implementiert nichts. Danach: `/issue` bzw. `/naechster-schritt`.
