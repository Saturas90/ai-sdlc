---
name: issue
description: Erstellt ein einzelnes Issue (issue.md) samt Kontextpaket (kontext.md) mit Problembeschreibung, Einordnung, Akzeptanzkriterien, Out of Scope und offenen Fragen. Reviewt es, bis keine kritisch/hoch-Findings offen sind, und holt die menschliche Freigabe. Key IS-NNN.
---

# Skill: Issue erstellen

1. Kontext: `~/.claude/ai-sdlc/konventionen.md`, Vorlagen `~/.claude/ai-sdlc/vorlagen/issue.md` und `kontext.md`, sowie `projektplan.md` (welches Issue ist dran: Key, Titel, „Architektur nötig?“).
2. Nächsten freien Key bestimmen (`IS-<NNN>`, dreistellig; vorhandenen Projekt-Key übernehmen). Ordner anlegen: `issues/IS-<NNN>-<slug>/`.
3. Sub-Agent **`issue-autor`** (Modell: sonnet) spawnen. Übergabe: passende Projektplan-Zeile + Vorlagen- und Konventionspfad. Er verfasst `issue.md` (Fachexperte, für Einsteiger verständlich), setzt „Architekturplan nötig: ja/nein“ und legt `kontext.md` an.
4. Offene Fragen aus dem Entwurf **vor** dem Review dem Nutzer vorlegen; Antworten im Issue nachtragen und die Frage auf `- [x]` setzen.
5. Review-Gate (`~/.claude/ai-sdlc/review-gate.md`), Prüftiefe S; Reviewer nach Abschnitt 1 (`reviewer`, bei sicherheits-/datenkritischem Inhalt `reviewer-kritisch`) → bei kritisch/hoch zurück an `issue-autor` **nur mit den deduplizierten Findings** → nächste Runde. Runde mit nur mittel/niedrig → einarbeiten lassen + Fixcheck, keine weitere Runde. Neue offene Fragen aus dem Review sofort klären.
6. Erst wenn **keine** offene `- [ ]` mehr im Abschnitt „Offene Fragen“ steht: menschliche Freigabe einholen (bzw. stehende Freigabe); danach die Statuszeile durch `**Status:** Freigegeben` ersetzen.
7. „Stand“ in `kontext.md` (bzw. die dort verwiesene projekteigene Übergabe) überschreiben (nächster Schritt, offene Entscheidungen), dann Commit (via `mechaniker`): `IS-<NNN>: Issue erstellt` (mit `kontext.md` bzw. der projekteigenen Übergabe, sofern versioniert).

Danach: `/architektur` (falls nötig) sonst `/impl-plan`.
