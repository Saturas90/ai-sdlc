---
name: projektplan
description: Erstellt oder aktualisiert den Projektplan (projektplan.md) mit Ziel, grobem Ablauf und der Issue-Liste (IS-Keys). Startpunkt jedes neuen Tool-Projekts im SDLC-Workflow.
---

# Skill: Projektplan

Zweck: `projektplan.md` im Projekt-Root erstellen/pflegen.

1. Kontext: `~/.claude/ai-sdlc/konventionen.md`, Vorlage `~/.claude/ai-sdlc/vorlagen/projektplan.md`.
2. Existiert `projektplan.md`? Falls ja → aktualisieren, nicht überschreiben.
3. Mit dem Nutzer klären: Ziel, Meilensteine, Issue-Liste. Je Issue: Key (`IS-<NNN>`, dreistellig), Titel, 1-Satz-Ziel, „Architektur nötig?“, Abhängigkeiten. Offene Punkte als Rückfrage — nicht raten.
4. Entwurf schreiben.
5. Review-Gate anwenden (`~/.claude/ai-sdlc/review-gate.md`); mittel/niedrig-Findings auflisten.
6. Um Freigabe bitten. Nach Freigabe committen (via `mechaniker`): `PROJEKT: Projektplan erstellt/aktualisiert`.

Kein Scope-Creep: Der Plan **listet** Issues, implementiert nichts. Danach: `/issue` bzw. `/naechster-schritt`.
