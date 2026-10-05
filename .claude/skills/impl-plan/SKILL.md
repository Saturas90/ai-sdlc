---
name: impl-plan
description: Erstellt den Implementierungsplan (impl-plan.md) mit einzeln abhakbaren Schritten samt Kontext-Ankern und gezielten Tests für ein freigegebenes Issue (+ ggf. Architektur). Präzise, ohne Interpretationsspielraum; Review-Gate; menschliche Freigabe.
---

# Skill: Implementierungsplan

Voraussetzung: Issue (und ggf. Architekturplan) freigegeben. Im Arbeitsbaum-Modus
(`~/.claude/ai-sdlc/arbeitsbaeume.md` Abschnitt 5): Hat das Issue einen Worktree mit nicht integrierten
Commits oder wird dort gearbeitet, entsteht eine Neufreigabe des Plans im Worktree
(`EnterWorktree(path: <Pfad aus wt status>)`).

1. Kontext: `~/.claude/ai-sdlc/konventionen.md`, Vorlage `~/.claude/ai-sdlc/vorlagen/impl-plan.md`, `issue.md`, ggf. `architektur.md`, `kontext.md`.
2. Sub-Agent **`impl-planer`** (Modell: sonnet) spawnen. Er verfasst `impl-plan.md`: nummerierte, einzeln überprüfbare Schritte mit `Dateien:`, `Kontext:` und `Tests:`; komplexe Schritte als `[K]`, sicherheits-/datenkritische zusätzlich `Prüftiefe: L`; inkl. Verifikationsstrategie. Er ergänzt `kontext.md`. Im Arbeitsbaum-Modus setzt er die Zeile `**Integration:**` (Standard `je Einheit`; `am Ende (<Grund>)` nur nach `arbeitsbaeume.md` Abschnitt 2); ohne Arbeitsbaum-Modus löscht er diese Zeile samt Kommentar.
3. Offene Fragen aus dem Entwurf **vor** dem Review klären (`- [x]` + Antwort).
4. Review-Gate anwenden (`~/.claude/ai-sdlc/review-gate.md`): Prüftiefe S, bei `[K]`- oder `Prüftiefe: L`-Schritten M; Reviewer nach Abschnitt 1 (`reviewer`; `reviewer-kritisch` bei `[K]`, `Prüftiefe: L` oder sicherheits-/datenkritischem Inhalt). Runde mit nur mittel/niedrig → einarbeiten + Fixcheck, keine weitere Runde; Konvergenz-Stopp ab Runde 3.
5. Keine offene `- [ ]` mehr, dann menschliche Freigabe (bzw. stehende Freigabe); Statuszeile → `**Status:** Freigegeben`.
6. „Stand“ in `kontext.md` (bzw. die dort verwiesene projekteigene Übergabe) überschreiben (nächster Schritt, offene Entscheidungen), dann Commit (via `mechaniker`): `IS-<NNN>: Implementierungsplan erstellt` (mit `kontext.md` bzw. der projekteigenen Übergabe, sofern versioniert). Im Arbeitsbaum-Modus vorher die zugehörigen Tests, wenn ein Test oder Gate die committeten Dateien liest.

Danach: `/implementieren`.
