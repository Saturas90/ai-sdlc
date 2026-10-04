---
name: issue
description: "Erstellt oder vervollständigt genau ein Issue strikt nach der CLAUDE.md des aktiven Repositories. Explizit mit $issue verwenden, wenn die Issue-Phase des Projektworkflows ansteht; erstellt Problembeschreibung, Optionen, Akzeptanzkriterien, Out-of-Scope und offene Fragen, aber keinen Code."
---

# Issue

1. Repository-Root bestimmen und `CLAUDE.md` als normative Quelle für Pfade, Benennung, Statusmarker, Inhalt und Gates verwenden. Fehlt sie, anhalten. Keine Annahmen aus `~/.claude` übernehmen. Für den Codex-Reviewabschluss gilt die Ausnahme in `AGENTS.md`, auch bei einem Claude-Fixcheck-Verweis.
2. Den in `CLAUDE.md` benannten Projektplan und nur die für das aktive Issue nötigen Abschnitte lesen. Issue-Nummer und Ziel unmittelbar vor der Vergabe gegen HEAD, Working Tree, Projektplan und vorhandene Issue-Ordner prüfen.
3. Die von `CLAUDE.md` verlinkte Issue-Vorlage lesen. Genau ein Issue im dort vorgeschriebenen Pfad und Format erstellen oder vervollständigen, daneben das Kontextpaket `kontext.md` (siehe `AGENTS.md`), sofern `CLAUDE.md` es nicht ausschließt (eine bloße Aufzählung der Ordnerinhalte schließt es nicht aus); keine Architektur, keinen Implementierungsplan und keinen Code erzeugen.
4. Mit Terra/medium schreiben, lokal bei passendem aktivem Modell, sonst `issue_autor`. Nur erforderlichen Projektkontext, Pfade und Vorlage übergeben; keine vollständige Gesprächsvererbung oder doppelte Autorenspur. Neue kritische Sicherheits-/Architekturentscheidungen mit Astra klären.
5. Offene Fragen aus dem Entwurf zuerst mit dem Nutzer klären. Dann das fertige vollständige Artefakt unabhängig nach `CLAUDE.md` kalt prüfen: `reviewer` (Terra/high), für kritische Entscheidungen `reviewer_kritisch` (Astra/xhigh). Review-Schleife nach `AGENTS.md` („Stabil prüfen“, „Abschluss ohne Bestätigungsrunde“, „Konvergenz“). Autor und Reviewer arbeiten nacheinander; Parallelisierung nur auf ausdrücklichen Nutzerwunsch.
6. Weitere offene Fragen gemäß Projektregeln mit dem Nutzer klären und im Issue dokumentieren. Vor dem menschlichen Freigabe-Gate anhalten.
7. Nach expliziter Freigabe ausschließlich die in `CLAUDE.md` erlaubten Statusänderungen durchführen. Keine nächste Phase automatisch starten.
