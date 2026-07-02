---
name: architektur
description: Erstellt den Architekturplan (architektur.md) für ein freigegebenes Issue, das "Architekturplan nötig: ja" markiert. Präzise, ohne Interpretationsspielraum; Review bis keine kritisch/hoch-Findings; menschliche Freigabe.
---

# Skill: Architekturplan

Voraussetzung: `issue.md` ist freigegeben und mit „Architekturplan nötig: ja“ markiert. Sonst diesen Schritt überspringen (→ `/impl-plan`).

1. Kontext: `~/.claude/ai-sdlc/konventionen.md`, Vorlage `~/.claude/ai-sdlc/vorlagen/architektur.md`, das freigegebene `issue.md` (inkl. beantworteter offener Fragen).
2. Sub-Agent **`architekt`** (Modell: opus) spawnen. Er verfasst `architektur.md`: knapp, eindeutig, ohne Interpretationsspielraum.
3. Review-Gate anwenden (`~/.claude/ai-sdlc/review-gate.md`) — Architektur ⇒ Reviewer **`reviewer-kritisch`** (opus).
4. Offene Fragen als `- [x]` + Antwort klären (keine offene `- [ ]` mehr), dann menschliche Freigabe; Statuszeile → `**Status:** Freigegeben`.
5. Commit (via `mechaniker`): `IS-<NNN>: Architekturplan erstellt`.

Danach: `/impl-plan`.
