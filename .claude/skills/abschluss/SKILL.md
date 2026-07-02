---
name: abschluss
description: Schließt ein Issue ab: erstellt eine kurze Zusammenfassung (zusammenfassung.md) und gleicht Issue ↔ Architektur ↔ Impl-Plan ↔ Implementierung ab (Scope-Treue).
---

# Skill: Abschluss

Voraussetzung: alle Impl-Plan-Schritte `[x]`.

1. Vorlage `~/.claude/ai-sdlc/vorlagen/zusammenfassung.md`. Kontext: `issue.md`, ggf. `architektur.md`, `impl-plan.md`, Commits/Diff des Issues.
2. Kurze **Zusammenfassung** schreiben: was wurde getan (bewusst knapp).
3. **Scope-Abgleich:** jedes Akzeptanzkriterium erfüllt? Architektur eingehalten? Impl-Plan vollständig? Nichts umgesetzt, was nicht im Issue stand? Abweichungen explizit benennen.
4. Bei Abweichung (umgesetzt ohne Issue-Deckung): **melden** und mit dem Nutzer klären — nicht stillschweigend akzeptieren.
5. Im `projektplan.md` den Status dieses Issues auf `erledigt` setzen (via `mechaniker`) — sonst terminiert der Orchestrator nicht und könnte das Issue erneut wählen.
6. Commit (via `mechaniker`): `IS-<NNN>: Abschluss & Zusammenfassung`.

Danach: `/naechster-schritt` für das nächste Issue.
