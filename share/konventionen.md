# Konventionen (Single Source of Truth)

Diese Datei enthält die geteilten Regeln des Workflows. Sie wird von allen Skills und
Sub-Agenten referenziert — **nirgends duplizieren**, nur hier ändern.

## Verzeichnis- & Namensschema (im Zielprojekt)

```
projektplan.md
issues/
  IS-<NNN>-<kurz-slug>/
    issue.md
    architektur.md      # nur wenn Issue "Architekturplan nötig: ja" markiert
    impl-plan.md
    zusammenfassung.md
```

## Issue-Keys

- Standard-Key: `IS-` + dreistellige Nummer (`IS-001`, `IS-002`, …), fortlaufend, im Projektplan vergeben.
- Weicht ein bestehendes Projekt vom Key ab: den **vorhandenen** Key des Projekts übernehmen.

## Review-Kategorien

- **kritisch** — Blockiert Freigabe/Betrieb: falsch, unsicher, Datenverlust/Fehlfunktion oder Widerspruch zum Issue.
- **hoch** — Deutlicher Mangel, muss vor Freigabe behoben werden: fehlende Abdeckung eines Akzeptanzkriteriums, Lücke, echter Interpretationsspielraum.
- **mittel** — Sollte behoben werden, blockiert aber nicht: Verständlichkeit, Redundanz, kleinere Robustheit.
- **niedrig** — Optional/kosmetisch: Stil, Formulierung.

**Gate-Regel:** Ein Artefakt ist erst dann freigabereif, wenn **keine kritisch/hoch-Findings** mehr offen sind. Ablauf siehe `review-gate.md`.

## Dokument-Grundregeln (Issue, Architektur, Impl-Plan)

- **Offene Fragen** stehen — falls vorhanden — als **letzter** Abschnitt, jeweils als Checkbox `- [ ]`, und müssen vom Menschen beantwortet werden (`- [x]` + Antwort), **bevor** die nächste Phase beginnt. Keine offenen Fragen ⇒ Abschnitt weglassen. Solange eine offene `- [ ]` im Abschnitt steht, ist das Gate **nicht** passierbar.
- **Out of Scope**: jeder Punkt referenziert entweder ein **konkretes zukünftiges Issue** (aus dem Projektplan) **oder** wird als **dauerhaft abgelehnt** markiert. Nichts Schwebendes.
- **Kein Scope-Creep**: Es wird ausschließlich geplant/umgesetzt, was im Issue dokumentiert ist.

## Freigabe-Prinzip

An jedem Planungs-Gate (Issue, Architektur, Impl-Plan) gibt **der Mensch** explizit frei. Der Agent fragt aktiv nach Freigabe und arbeitet nicht eigenmächtig über ein Gate hinaus.

## Status- & Freigabe-Marker (maschinell prüfbar)

Damit der Orchestrator Gates nicht überspringt, hängen Freigabe, offene Fragen und
Projektfortschritt an eindeutigen Textmarkern statt an Interpretation:

- **Freigabe:** Jedes Planungsartefakt trägt genau **eine** Statuszeile. Im Entwurf: `**Status:** Entwurf`.
  Erst nach menschlicher Freigabe ersetzt der zuständige Skill sie durch `**Status:** Freigegeben`.
  „Freigegeben“ = **exakt diese Zeile**, nicht das bloße Vorkommen des Wortes.
- **Offene Fragen:** immer als Checkbox `- [ ]` (nie Freitext). Offene `- [ ]` im Abschnitt „Offene Fragen“ ⇒ Gate gesperrt.
- **Issue-Fortschritt:** Der Projektplan führt je Issue eine Status-Spalte (`offen` → `erledigt`).
  Der Abschluss-Skill setzt sie auf `erledigt`. „Nächstes offenes Issue“ = erste Zeile mit Status ≠ `erledigt`.
  Sind **alle** Issues `erledigt`, ist das Projekt fertig — der Orchestrator terminiert.

## Commit-Konvention

- Format: `IS-<NNN>: <kurz, was getan wurde>`
- Ein Commit je freigegebenem Planungsartefakt (Issue / Architektur / Impl-Plan).
- Ein Commit je review-gesichertem (Bündel von) Implementierungsschritt(en).
- Projektweite Artefakte ohne Issue-Bezug: `PROJEKT: <kurz>`.
- **Alle** Commits und das Abhaken im Impl-Plan werden an den `mechaniker`-Sub-Agenten (haiku) delegiert — reine Mechanik, kein teures Modell.

## Abschluss

Nach vollständiger Implementierung + Reviews: kurze **Zusammenfassung** (was wurde getan)
+ **Scope-Abgleich** Issue ↔ (Architektur) ↔ Impl-Plan ↔ Implementierung. Nichts darf umgesetzt
sein, das nicht im Issue dokumentiert war.
