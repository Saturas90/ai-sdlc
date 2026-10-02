---
name: architektur
description: Erstellt den Architekturplan (architektur.md) für ein freigegebenes Issue, das "Architekturplan nötig: ja" markiert. Präzise, ohne Interpretationsspielraum; Review (Prüftiefe M) bis keine kritisch/hoch-Findings; menschliche Freigabe.
---

# Skill: Architekturplan

Voraussetzung: `issue.md` ist freigegeben und mit „Architekturplan nötig: ja“ markiert. Sonst diesen Schritt überspringen (→ `/impl-plan`).

1. Kontext: `~/.claude/ai-sdlc/konventionen.md`, Vorlage `~/.claude/ai-sdlc/vorlagen/architektur.md`, das freigegebene `issue.md` (inkl. beantworteter offener Fragen) und `kontext.md`.
2. Sub-Agent **`architekt`** (Modell: opus) spawnen. Er verfasst `architektur.md` (knapp, eindeutig, ohne Interpretationsspielraum) und ergänzt `kontext.md`.
3. Offene Fragen aus dem Entwurf **vor** dem Review klären (`- [x]` + Antwort).
4. Review-Gate anwenden (`~/.claude/ai-sdlc/review-gate.md`) — Prüftiefe M, Reviewer **`reviewer-architektur`** (opus, xhigh). Runde mit nur mittel/niedrig → einarbeiten + Fixcheck, keine weitere Runde; Konvergenz-Stopp ab Runde 3.
5. Keine offene `- [ ]` mehr, dann menschliche Freigabe (bzw. stehende Freigabe); Statuszeile → `**Status:** Freigegeben`.
6. „Stand“ in `kontext.md` (bzw. die dort verwiesene projekteigene Übergabe) überschreiben (nächster Schritt, offene Entscheidungen), dann Commit (via `mechaniker`): `IS-<NNN>: Architekturplan erstellt` (mit `kontext.md` bzw. der projekteigenen Übergabe, sofern versioniert).

Danach: `/impl-plan`.
