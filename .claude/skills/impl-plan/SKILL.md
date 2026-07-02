---
name: impl-plan
description: Erstellt den Implementierungsplan (impl-plan.md) mit einzeln abhakbaren Schritten für ein freigegebenes Issue (+ ggf. Architektur). Präzise, ohne Interpretationsspielraum; Review-Gate; menschliche Freigabe.
---

# Skill: Implementierungsplan

Voraussetzung: Issue (und ggf. Architekturplan) freigegeben.

1. Kontext: `~/.claude/ai-sdlc/konventionen.md`, Vorlage `~/.claude/ai-sdlc/vorlagen/impl-plan.md`, `issue.md`, ggf. `architektur.md`.
2. Sub-Agent **`impl-planer`** (Modell: sonnet) spawnen. Er verfasst `impl-plan.md`: nummerierte, einzeln überprüfbare Schritte; komplexe Schritte als `[K]`; inkl. Verifikationsstrategie.
3. Review-Gate anwenden (`~/.claude/ai-sdlc/review-gate.md`).
4. Offene Fragen als `- [x]` + Antwort klären (keine offene `- [ ]` mehr), dann menschliche Freigabe; Statuszeile → `**Status:** Freigegeben`.
5. Commit (via `mechaniker`): `IS-<NNN>: Implementierungsplan erstellt`.

Danach: `/implementieren`.
