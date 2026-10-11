---
name: issue
description: Erstellt ein einzelnes Issue (issue.md) samt Kontextpaket (kontext.md) mit Problembeschreibung, Einordnung, Akzeptanzkriterien, Out of Scope und offenen Fragen. Reviewt es, bis keine kritisch/hoch-Findings offen sind, und holt die menschliche Freigabe. Key IS-NNN.
---

# Skill: Issue erstellen

1. Kontext: `~/.claude/ai-sdlc/konventionen.md`, Vorlagen `~/.claude/ai-sdlc/vorlagen/issue.md` und `kontext.md`, sowie `projektplan.md` (welches Issue ist dran: Key, Titel, „Architektur nötig?“).
2. Nächsten freien Key bestimmen (`IS-<NNN>`, dreistellig; vorhandenen Projekt-Key übernehmen). Ordner anlegen: `issues/IS-<NNN>-<slug>/`. Im Arbeitsbaum-Modus (`~/.claude/ai-sdlc/arbeitsbaeume.md` Abschnitt 5) eine neu vergebene Nummer sofort per Reservierungs-Commit festschreiben, damit parallele Sessions sie nicht doppelt vergeben: vorher `git diff --quiet -- projektplan.md` (zeigt es fremde Änderungen, anhalten und den Menschen fragen), dann über `mechaniker` per `wt commit` (`pwsh -NoProfile -File "$HOME/.claude/ai-sdlc/tools/wt.ps1"`, nie das Programm `wt`): `projektplan.md` ohne fremde Änderungen, nur die neue Zeile.
3. Sub-Agent **`issue-autor`** (Modell: sonnet) spawnen. Übergabe: passende Projektplan-Zeile + Vorlagen- und Konventionspfad. Er verfasst `issue.md` (Fachexperte, für Einsteiger verständlich), setzt „Architekturplan nötig: ja/nein“ und legt `kontext.md` an.
4. Offene Fragen aus dem Entwurf **vor** dem Review dem Nutzer vorlegen; Antworten im Issue nachtragen und die Frage auf `- [x]` setzen.
5. Review-Gate (`~/.claude/ai-sdlc/review-gate.md`), Prüftiefe S; Reviewer nach Abschnitt 1 (`reviewer`, bei sicherheits-/datenkritischem Inhalt `reviewer-kritisch`) → bei kritisch/hoch zurück an `issue-autor` **nur mit den deduplizierten Findings** → nächste Runde. Runde mit nur mittel/niedrig → einarbeiten lassen + Fixcheck, keine weitere Runde. Neue offene Fragen aus dem Review sofort klären.
6. Erst wenn **keine** offene `- [ ]` mehr im Abschnitt „Offene Fragen“ steht: menschliche Freigabe einholen (bzw. stehende Freigabe); danach die Statuszeile durch `**Status:** Freigegeben` ersetzen.
7. „Stand“ in `kontext.md` (bzw. die dort verwiesene projekteigene Übergabe) überschreiben (nächster Schritt, offene Entscheidungen), dann Commit (via `mechaniker`): `IS-<NNN>: Issue erstellt` (mit `kontext.md` bzw. der projekteigenen Übergabe, sofern versioniert). Vor jedem Commit (im Arbeitsbaum-Modus auch der Reservierung in Schritt 2) statt der Gate-Kette die Tests und Gate-Schritte, die die committeten Dateien lesen (`~/.claude/ai-sdlc/konventionen.md` › Tests & Gates).

Danach: `/architektur` (falls nötig) sonst `/impl-plan`.
