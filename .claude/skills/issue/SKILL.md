---
name: issue
description: Erstellt ein einzelnes Issue (issue.md) mit Problembeschreibung, Einordnung, Akzeptanzkriterien, Out of Scope und offenen Fragen. Reviewt es, bis keine kritisch/hoch-Findings offen sind, und holt die menschliche Freigabe. Key IS-NNN.
---

# Skill: Issue erstellen

1. Kontext: `~/.claude/ai-sdlc/konventionen.md`, Vorlage `~/.claude/ai-sdlc/vorlagen/issue.md`, sowie `projektplan.md` (welches Issue ist dran: Key, Titel, „Architektur nötig?“).
2. Nächsten freien Key bestimmen (`IS-<NNN>`, dreistellig; vorhandenen Projekt-Key übernehmen). Ordner anlegen: `issues/IS-<NNN>-<slug>/`.
3. Sub-Agent **`issue-autor`** (Modell: sonnet) spawnen. Übergabe: passende Projektplan-Zeile + Vorlage- und Konventionspfad. Er verfasst `issue.md` (Fachexperte, für Einsteiger verständlich) und setzt „Architekturplan nötig: ja/nein“.
4. Review-Gate (`~/.claude/ai-sdlc/review-gate.md`) anwenden: `reviewer` → bei kritisch/hoch zurück an `issue-autor` **nur mit diesen Findings** → wiederholen.
5. Offene Fragen: falls vorhanden, dem Nutzer vorlegen; Antworten im Issue nachtragen und die Frage auf `- [x]` setzen. Erst wenn **keine** offene `- [ ]` mehr im Abschnitt steht, weiter.
6. Menschliche Freigabe einholen; danach die Statuszeile durch `**Status:** Freigegeben` ersetzen.
7. Commit (via `mechaniker`): `IS-<NNN>: Issue erstellt`.

Danach: `/architektur` (falls nötig) sonst `/impl-plan`.
