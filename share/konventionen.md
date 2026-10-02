# Konventionen (Single Source of Truth)

Diese Datei enthält die geteilten Regeln des Workflows. Sie wird von allen Skills und
Sub-Agenten referenziert — **nirgends duplizieren**, nur hier ändern. Ausnahme: knappe Kurzfassungen in
den Agenten-Bodies (Reviewer-Prüfpunkte, Lese- und Fix-Regeln), damit nicht jeder Spawn diese Datei lesen
muss. Definiert die Projekt-CLAUDE.md eigene Regeln, haben diese Vorrang.

## Verzeichnis- & Namensschema (im Zielprojekt)

```
projektplan.md
issues/
  IS-<NNN>-<kurz-slug>/
    issue.md
    kontext.md          # Kontextpaket: Einstieg für alle Agenten dieses Issues (kein Freigabe-Artefakt)
    architektur.md      # nur wenn Issue "Architekturplan nötig: ja" markiert
    impl-plan.md
    zusammenfassung.md
```

## Issue-Keys

- Standard-Key: `IS-` + dreistellige Nummer (`IS-001`, `IS-002`, …), fortlaufend, im Projektplan vergeben.
- Weicht ein bestehendes Projekt vom Key ab: den **vorhandenen** Key des Projekts übernehmen.

## Review-Kategorien

- **kritisch** — Blockiert Freigabe/Betrieb: falsch, unsicher, Datenverlust/Fehlfunktion oder Widerspruch zum Issue.
- **hoch** — Deutlicher Mangel, muss vor Freigabe behoben werden: fehlende Abdeckung eines Akzeptanzkriteriums, Lücke, echter Interpretationsspielraum (zwei plausible Lesarten mit unterschiedlichem Ergebnis).
- **mittel** — Sollte behoben werden, blockiert aber nicht: Verständlichkeit, Redundanz, kleinere Robustheit, eine Lücke, die nur zu einem sicheren Abbruch führt.
- **niedrig** — Optional/kosmetisch: Stil, Formulierung.

**Gate-Regel:** Ein Artefakt ist erst dann freigabereif, wenn **keine kritisch/hoch-Findings** mehr offen sind. Ablauf, Prüftiefe und Abschluss ohne Bestätigungsrunde: `review-gate.md`.

## Dokument-Grundregeln (Issue, Architektur, Impl-Plan)

- **Offene Fragen** stehen — falls vorhanden — als **letzter** Abschnitt, jeweils als Checkbox `- [ ]`, und müssen vom Menschen beantwortet werden (`- [x]` + Antwort), **bevor** die nächste Phase beginnt. Keine offenen Fragen ⇒ Abschnitt weglassen. Solange eine offene `- [ ]` im Abschnitt steht, ist das Gate **nicht** passierbar. Fragen, die schon im Entwurf stehen, klärt der Mensch **vor** dem ersten Review — ihre Antworten ändern das Artefakt.
- **Out of Scope**: jeder Punkt referenziert entweder ein **konkretes zukünftiges Issue** (aus dem Projektplan) **oder** wird als **dauerhaft abgelehnt** markiert. Nichts Schwebendes.
- **Kein Scope-Creep**: Es wird ausschließlich geplant/umgesetzt, was im Issue dokumentiert ist.

## Korrektur nach Review (alle erzeugenden Agenten)

- Nur die übergebenen Findings, je Finding minimal und lokal; nichts drumherum umformulieren.
- Vorgeschlagene Formulierungen aus Findings nicht ungeprüft übernehmen: Prämissen und jede neue
  Sachaussage gegen Code bzw. Quelle prüfen; keine Behauptungen über das Finding hinaus.
- Nahtstellen: dieselbe Regel, Zahl oder Benennung an allen Fundstellen gleichziehen (Grep).
- **Melden statt umsetzen** — immer: Fixes, die Scope oder Akzeptanzkriterien, Schnittstellen/Verträge,
  freigegebene Entscheidungen oder die Schrittstruktur ändern oder eine Entscheidung des Menschen brauchen.
  Zusätzlich nach einer Runde ohne Blocker (`review-gate.md` Abschnitt 3): Fixes, die eine neue Regel,
  Variante oder einen neuen Ablaufschritt einführen — also das Ergebnis eines schon eindeutig geregelten Falls ändern, ohne dass eine vorrangige
  Quelle es so vorgibt (Projekt-CLAUDE.md, freigegebenes Artefakt, Entscheidung des Menschen, normatives
  Dokument), oder eine Fallunterscheidung einführen, die andere Stellen mitbeachten müssen. Widersprechen sich
  zwei Stellen ohne klare Rangfolge: melden. Nicht darunter fallen Korrekturen (Angleichen an eine solche vorrangige Quelle, auch bei Zahlen; die Quelle
  an eine abweichende Kopie anzugleichen ist keine Korrektur) und Präzisierungen bestehender Aussagen,
  Verweise, Wortlaut, die Gliederung des Dokuments und lokale Robustheits-Fixes im Code ohne Vertragsänderung, die durch Tests abgedeckt sind (z. B. Validierung,
  Fehlerbehandlung).
  Gemeldete Mittel/Niedrig-Fixes werden standardmäßig vertagt (`kontext.md` › Vertagt). Ein gemeldeter Fix
  zu einem kritisch/hoch-Finding und alles mit Entscheidungsbedarf gehen an den Menschen; der Blocker bleibt
  bis zu seiner Entscheidung offen.
- Nicht zutreffende Findings mit Beleg ablehnen, statt sie irgendwie einzubauen.
- Rückgabe: Fix-Protokoll je Finding `umgesetzt (Fundstellen Datei:Zeile) | abgelehnt (Grund) | gemeldet (Grund)`
  — die Fundstellen braucht der Fixcheck für Zuordnung und Rücknahme.

## Kontext-Ökonomie (große Projekte)

- **Kontextpaket:** Je Issue `kontext.md` (Vorlage `vorlagen/kontext.md`, ≤ 8 KB): relevante Stellen als
  Anker (Datei:Symbol bzw. Datei:Zeilen), tragende Normauszüge mit Quelle, Tests, bewusst Irrelevantes,
  Vertagtes, Stand. `issue-autor` legt es an, `architekt` und `impl-planer` ergänzen, die Hauptsession pflegt
  „Vertagt“ und „Stand“. Fehlt es bei einem laufenden Issue, legt die erste Phase es an, die es braucht; eine
  bloße Aufzählung der Ordnerinhalte in der Projekt-CLAUDE.md schließt es nicht aus. Jeder Agent liest es
  zuerst, öffnet die Anker plus gezielte Suchen und trägt neue relevante Stellen nach; Reviewer begrenzt es nicht.
- **Lesen:** Dateien über 20 KB nie ganz — erst Gliederung (`grep -n '^#'`) bzw. Grep, dann den Abschnitt
  (offset/limit). Normdokumente (Constraints, Glossar, Archive, große ADRs) nur gezielt; tragende Normtexte
  als Auszug ins Kontextpaket statt „vollständig lesen“. Nach einem Edit nicht erneut lesen; unabhängige
  Edits und Reads in einer Antwort bündeln.
- **Budgets** (Projektwerte haben Vorrang): Issue ≤ 12 KB, Architektur ≤ 20 KB, Impl-Plan ≤ 20 KB,
  Zusammenfassung ≤ 6 KB, Kontextpaket ≤ 8 KB, jedes weitere geprüfte Dokument (Runbook, Verfahren,
  Vertrag, ADR) ≤ 25 KB. Gesprengtes Budget ⇒ Scope schneiden bzw. Dokument teilen, nicht weiterschreiben;
  beim Kontextpaket zuerst Anker und Schrittkarten kürzen — „Vertagt“ und „Stand“ werden nie gekürzt.
  Review-Historie gehört nicht ins Artefakt, sondern als Ergebniszeile in die Zusammenfassung.
- **Tests & Gates:** gezielt (Plan-Feld `Tests:`), im Vordergrund mit Zeitlimit; Ausgabe in eine Datei, im
  Kontext nur Status und bei Fehler der Tail (≤ 40 Zeilen). Die Gate-Kette des Projekts einmal je Einheit
  vor dem Commit, in einem Aufruf, Formatter anwenden statt prüfen. Keine eigenen Mutationsläufe der
  Implementierer — Testwirksamkeit belegt die Mutationsphase (`review-gate.md`).
- **Agenten:** immer typisiert aufrufen (`subagent_type` bzw. `agentType`), nie `general-purpose` für
  SDLC-Arbeit; Erhebung und Recherche → `rechercheur`. Je Plan-Einheit ein frischer `implementierer`;
  triviale Einheiten (eine Datei, keine Logikänderung) erledigt die Hauptsession selbst. Einen
  Autor-Agenten nur für die Fixrunden derselben Einheit fortsetzen, höchstens zweimal (sein Kontext wächst
  je Runde um 100–200K) — danach frisch, mit Findings und `kontext.md` als Übergabe.
- **Übergaben kompakt:** Findings an Autoren dedupliziert, je Zeile Kategorie, Datei:Zeile, Maßnahme —
  keine Linsen-Rohberichte, keine Verify-Protokolle. Agenten- und Workflow-Rückgaben knapp, Details in Dateien.
- **Sessions:** eine Session je Phase bzw. Impl-Einheit; der Zustand liegt in Dateien (Statuszeilen,
  Häkchen, „Stand“ in `kontext.md`; mitten im Gate zusätzlich die Angaben aus `review-gate.md` 2.4). Ab
  geschätzt ~200K Kontext am nächsten Einheits- bzw. Rundenende übergeben und eine neue Session
  vorschlagen; über ~300K keine neue Einheit beginnen.

## Freigabe-Prinzip

An jedem Planungs-Gate (Issue, Architektur, Impl-Plan) gibt **der Mensch** explizit frei. Der Agent fragt aktiv nach Freigabe und arbeitet nicht eigenmächtig über ein Gate hinaus.

**Stehende Freigabe (opt-in):** Hat der Mensch sie erteilt (Projekt-CLAUDE.md, gespeicherte
Nutzervorgabe/Memory oder ausdrücklich in der Session), gilt ein Planungsartefakt als freigegeben, sobald
das Review-Gate erfüllt, der Fixcheck ohne offenen Befund durchlaufen ist und keine Entscheidung des
Menschen aussteht (kein offener oder gemeldeter Blocker, kein Fix mit Entscheidungsbedarf, kein
Fixcheck-Befund ab hoch außerhalb der Fixes):
Statuszeile setzen, Prüftiefe, Runden, Ergebnis, offene Mittel/Niedrig und Vertagtes transparent nennen,
committen. Offene Fragen beantwortet immer der Mensch.

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
- Ein Commit je freigegebenem Planungsartefakt (Issue / Architektur / Impl-Plan), jeweils mit `kontext.md`.
- Ein Commit je review-gesichertem (Bündel von) Implementierungsschritt(en).
- Projektweite Artefakte ohne Issue-Bezug: `PROJEKT: <kurz>`.
- **Alle** Commits und das Abhaken im Impl-Plan werden an den `mechaniker`-Sub-Agenten (haiku) delegiert — reine Mechanik, kein teures Modell.

## Abschluss

Nach vollständiger Implementierung + Reviews: kurze **Zusammenfassung** (was wurde getan, Review-Ergebnis
je Phase in einer Zeile) + **Scope-Abgleich** Issue ↔ (Architektur) ↔ Impl-Plan ↔ Implementierung. Nichts
darf umgesetzt sein, das nicht im Issue dokumentiert war.
