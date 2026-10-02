---
name: impl-plan
description: Erstellt den Implementierungsplan (impl-plan.md) mit einzeln abhakbaren Schritten samt Kontext-Ankern und gezielten Tests für ein freigegebenes Issue (+ ggf. Architektur). Präzise, ohne Interpretationsspielraum; Review-Gate; menschliche Freigabe.
---

# Skill: Implementierungsplan

Voraussetzung: Issue (und ggf. Architekturplan) freigegeben.

1. Kontext: `~/.claude/ai-sdlc/konventionen.md`, Vorlage `~/.claude/ai-sdlc/vorlagen/impl-plan.md`, `issue.md`, ggf. `architektur.md`, `kontext.md`.
2. Sub-Agent **`impl-planer`** (Modell: sonnet) spawnen. Er verfasst `impl-plan.md`: nummerierte, einzeln überprüfbare Schritte mit `Dateien:`, `Kontext:` und `Tests:`; komplexe Schritte als `[K]`, sicherheits-/datenkritische zusätzlich `Prüftiefe: L`; inkl. Verifikationsstrategie. Er ergänzt `kontext.md`.
3. Offene Fragen aus dem Entwurf **vor** dem Review klären (`- [x]` + Antwort).
4. Review-Gate anwenden (`~/.claude/ai-sdlc/review-gate.md`): Prüftiefe S, bei `[K]`- oder `Prüftiefe: L`-Schritten M; Reviewer nach Abschnitt 1 (`reviewer`; `reviewer-kritisch` bei `[K]`, `Prüftiefe: L` oder sicherheits-/datenkritischem Inhalt). Runde mit nur mittel/niedrig → einarbeiten + Fixcheck, keine weitere Runde; Konvergenz-Stopp ab Runde 3.
5. Keine offene `- [ ]` mehr, dann menschliche Freigabe (bzw. stehende Freigabe); Statuszeile → `**Status:** Freigegeben`.
6. „Stand“ in `kontext.md` (bzw. die dort verwiesene projekteigene Übergabe) überschreiben (nächster Schritt, offene Entscheidungen), dann Commit (via `mechaniker`): `IS-<NNN>: Implementierungsplan erstellt` (mit `kontext.md` bzw. der projekteigenen Übergabe, sofern versioniert).

Danach: `/implementieren`.
