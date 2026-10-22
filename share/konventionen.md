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
  Kontext nur Status und bei Fehler der Tail (≤ 40 Zeilen). Keine eigenen Mutationsläufe der Implementierer —
  Testwirksamkeit belegt die Mutationsphase (`review-gate.md`).
  - *Schnelle Gates* fahren Implementierer, Fix-Durchgänge und die Hauptsession bei trivialen Einheiten, dazu
    gezielte Tests. Befehl: im Arbeitsbaum-Modus der Projektwert `schnelleGates`; fehlt er, ist er leer oder
    ohne Modus die Zeile in `kontext.md` › Tests & Prüfbefehle bzw. die Verifikationsstrategie des Impl-Plans.
    Den Formatter anwenden — ohne Arbeitsbaum-Modus nur auf die eigenen Dateien; Lint und Typcheck über das
    ganze Projekt, ohne Arbeitsbaum-Modus nur prüfend. Befunde allein in fremden uncommitteten Dateien oder auch
    auf HEAD ohne die eigenen Dateien (fremde Ursache) nicht beheben, sondern dem Menschen melden.
  - *Gate-Kette:* einmal je Einheit nach Review-Gate und Fixes vor dem Commit, in einem Aufruf und nur prüfend
    (Formatter im Prüfmodus; verändert sie Dateien, gilt sie als rot), von der Hauptsession im Hintergrund
    gestartet (nicht `mechaniker`). Zeigt `git status --porcelain -uall` uncommittete Dateien außerhalb der
    eigenen Pfade, läuft sie auf HEAD plus den eigenen Dateien in einem eigenen Worktree — außerhalb des Repos an
    kurzem Pfad oder im Repo unter einem eigenen Ordner mit Punkt, den die versionierte `.gitignore` ausschließt
    (z. B. `.claude/worktrees/`; nie in Build-, Abhängigkeits- oder Ausgabeordnern; erfasst ein Test-, Lint- oder
    Build-Werkzeug ihn dennoch: melden; eine Projektregel hat Vorrang); gitignorierte Laufzeitvoraussetzungen dort
    bereitstellen (fehlen sie: melden); Abbau wie bei den
    Gate-Worktrees von `wt`: Junctions und Symlinks darin zuerst als Links entfernen, nie ihre Ziele (scheitert
    das bei einem Link oder ist der Worktree nicht vollständig lesbar: stehen lassen, nichts weiter löschen,
    melden), dann `git worktree remove --force`. Ebenso die Nachprüfung der Drift-Prüfung; die Gegenprobe auf HEAD ohne die
    eigenen Dateien läuft immer in einem solchen Worktree. Den geprüften HEAD (Gate-Basis bzw. Stand der letzten
    grünen Drift-Prüfung) gibt die Hauptsession dem `mechaniker` mit. Im Arbeitsbaum-Modus läuft die Kette
    stattdessen einmal je Integration (`arbeitsbaeume.md` Abschnitt 4).
  - *Planungs-, Doku- und Abschluss-Commits* außerhalb einer Impl-Einheit, die weder Code noch Tests noch
    Konfiguration ändern, fahren statt der Kette die Tests und Gate-Schritte, die die committeten Dateien lesen —
    auch über Ordner oder Glob und bei Umbenennung für den alten Pfad (z. B. die Doku-Leser des Wächter-Sets).
    Rot allein durch fremde uncommittete Dateien oder schon auf HEAD (fremde Ursache): nicht beheben, sondern dem
    Menschen melden.
- **Wächter-Set:** Tests, die Quellbaum, Repository oder Doku als Daten lesen (Architektur- und
  Import-Scanner, Repo-Scanner, Doku- und Verzeichnisleser), ohne Tests mit Docker, Datenbank oder geteilten
  Sperren. Den Befehl führt die Projekt-CLAUDE.md, `kontext.md` übernimmt ihn; ein neuer solcher Test gehört
  ins Set.
- **Drift-Prüfung** (vor dem Commit einer Impl-Einheit, ohne Arbeitsbaum-Modus): Steht HEAD unmittelbar vor dem
  Commit nicht mehr auf der Gate-Basis (HEAD beim Start der grünen Kette), weil fremde Commits hinzukamen — auch
  während einer Drift-Prüfung —, läuft die Kette nicht erneut, wenn (1) die fremden Commits keine eigenen Pfade
  berühren (sonst anhalten und dem Menschen melden, wie in `review-gate.md` 3.1), (2) weder sie noch die eigene
  Änderung Infrastruktur berühren — Testkonfiguration und -hilfen (z. B. conftest), per Konfiguration geladene
  Test-Plugins, Abhängigkeits-Manifeste und Lockfiles, Migrationen samt neuer Nummern, CI-Workflows,
  Gate-Skripte, Build- und Formatter-Konfiguration, Container-Konfiguration der Tests; eine Pfadliste der
  Projekt-CLAUDE.md hat Vorrang — und (3) auf dem neuen HEAD plus den eigenen Dateien grün laufen (Nachprüfung):
  die schnellen Gates (Formatter nur prüfend), die gezielten Tests der Einheit, die von den fremden Commits
  geänderten oder neuen Tests und das Wächter-Set. Sonst die Kette auf dem neuen Stand erneut; ohne Wächter-Set
  immer. Der Commit nennt im Text `Gate-Basis: <rev>`, `Drift-über: <revs>` und `Drift-Prüfung: grün`. Zeigt eine
  spätere Kette rote Tests, die zu einem solchen Commit passen, behebt dessen Issue sie vorrangig (Bug-Issue).
  Solange main bekannt rot ist, keine Commits per Drift-Prüfung. Markierung: `main-rot.md` direkt in der Wurzel
  der Gate-Ablage des Hauptcheckouts (Standard `.gate-logs/main-rot.md`, nicht im Issue-Unterordner; Rev, rote
  Tests, Verursacher); an legt sie, wer die Kette auch auf HEAD ohne die eigenen Dateien rot sieht, entfernt, wer
  sie dort wieder grün sieht oder den Fix der roten Tests mit grüner Kette committet hat — nur, wenn sie seit dem
  Start dieser Kette unverändert ist, sonst melden —, oder der Mensch.
- **Agenten:** immer typisiert aufrufen (`subagent_type` bzw. `agentType`), nie `general-purpose` für
  SDLC-Arbeit; Erhebung und Recherche → `rechercheur`. Je Plan-Einheit ein frischer `implementierer`
  (`[K]` und `Prüftiefe: L`: `implementierer-kritisch`; max-Eskalation: `review-gate.md` Abschnitt 4);
  triviale Einheiten (eine Datei, keine Logikänderung) erledigt die Hauptsession selbst. Einen
  Autor-Agenten nur für die Fixrunden derselben Einheit fortsetzen, höchstens zweimal (sein Kontext wächst
  je Runde um 100–200K) — danach frisch, mit Findings und `kontext.md` als Übergabe.
- **Übergaben kompakt:** Findings an Autoren dedupliziert, je Zeile Kategorie, Datei:Zeile, Maßnahme —
  keine Linsen-Rohberichte, keine Verify-Protokolle. Agenten- und Workflow-Rückgaben knapp, Details in Dateien.
- **Sessions:** eine Session je Phase bzw. Impl-Einheit; der Zustand liegt in Dateien (Statuszeilen,
  Häkchen, „Stand“ in `kontext.md`; mitten im Gate zusätzlich die Angaben aus `review-gate.md` 2.4; im
  Arbeitsbaum-Modus liegt beides für ein Issue mit Worktree dort, siehe `wt status`). Ab geschätzt ~200K
  Kontext am nächsten Einheits- bzw. Rundenende übergeben und eine neue Session vorschlagen; über ~300K
  keine neue Einheit beginnen.

## Freigabe-Prinzip

An jedem Planungs-Gate (Issue, Architektur, Impl-Plan) gibt **der Mensch** explizit frei. Der Agent fragt aktiv nach Freigabe und arbeitet nicht eigenmächtig über ein Gate hinaus.

**Stehende Freigabe (opt-in):** Hat der Mensch sie erteilt (Projekt-CLAUDE.md, gespeicherte
Nutzervorgabe/Memory oder ausdrücklich in der Session), gilt ein Planungsartefakt als freigegeben, sobald das
Review-Gate erfüllt, der Fixcheck ohne offenen Befund durchlaufen ist und keine Entscheidung des Menschen
aussteht (kein offener oder gemeldeter Blocker, kein Fix mit Entscheidungsbedarf, keine offene Meldung
„unklare Herkunft“, kein Fixcheck-Befund ab hoch außerhalb der Fixes): Statuszeile setzen, Prüftiefe, Runden,
Ergebnis, offene Mittel/Niedrig und Vertagtes transparent nennen, committen. Offene Fragen beantwortet immer
der Mensch.

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

## Arbeitsbäume (opt-in)

Enthält die Projekt-CLAUDE.md den Abschnitt `## Arbeitsbäume (ai-sdlc)`, gilt `arbeitsbaeume.md`
(Arbeitsbaum-Modus): Implementierung je Issue im eigenen Worktree auf einem kurzlebigen Branch, Integration
je Einheit (per Plan-Zeile auch erst am Ende) per `wt integrate` (Rebase, eine Gate-Kette, Fast-Forward nach
main); Planung, Abschluss und S-Bugfixes bleiben im Hauptcheckout. Ohne den Abschnitt bleibt alles wie
hier beschrieben.

## Commit-Konvention

- Format: `IS-<NNN>: <kurz, was getan wurde>`
- Ein Commit je freigegebenem Planungsartefakt (Issue / Architektur / Impl-Plan), jeweils mit `kontext.md`.
- Ein Commit je review-gesichertem (Bündel von) Implementierungsschritt(en); im Arbeitsbaum-Modus auf dem
  Issue-Branch, eine Einheit bleibt ein Commit (Nachbesserung per `--amend` vor der Integration). Ausnahme bei
  mehreren Commits auf dem Branch (Integration am Ende): Korrekturen aus einem Konflikt-Review als eigener
  Commit `IS-<NNN>: Konfliktkorrektur`, ein Fix nach rotem Gate als eigener Commit `IS-<NNN>: Gate-Fix`
  (`arbeitsbaeume.md` Abschnitt 2).
- Projektweite Artefakte ohne Issue-Bezug: `PROJEKT: <kurz>`.
- Nur mit expliziter Dateiliste committen (`git commit -m … -- <dateien>`; neue Dateien vorher
  `git add -N -- <datei>`, bei Umbenennung alter und neuer Pfad, keine Verzeichnisse), nie `git add -A` oder
  `commit -a` — in einem geteilten Arbeitsbaum nähmen sie fremde Arbeit mit. Im Arbeitsbaum-Modus über
  `wt commit`; dort zusätzlich Reservierungs-Commits für neue Issue-Nummern (`IS-<NNN>: registriert`).
- **Alle** Commits und das Abhaken im Impl-Plan werden an den `mechaniker`-Sub-Agenten (haiku) delegiert — reine Mechanik, kein teures Modell.
  Im Arbeitsbaum-Modus führt die Hauptsession `git rebase <hauptbranch>`, `rebase --continue`,
  `rebase --abort`, `commit --amend`, `wt integrate` und `wt commit -Gate` selbst aus (`arbeitsbaeume.md`
  Abschnitt 1).

## Abschluss

Nach vollständiger Implementierung + Reviews: kurze **Zusammenfassung** (was wurde getan, Review-Ergebnis
je Phase in einer Zeile) + **Scope-Abgleich** Issue ↔ (Architektur) ↔ Impl-Plan ↔ Implementierung. Nichts
darf umgesetzt sein, das nicht im Issue dokumentiert war.
