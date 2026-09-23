---
name: architektur
description: "Führt die Architekturphase für ein freigegebenes Issue strikt nach der CLAUDE.md des Repositories aus. Explizit mit $architektur verwenden, wenn CLAUDE.md bzw. das Issue einen Architekturentwurf verlangt; überspringt die Phase, wenn sie nicht nötig ist, und implementiert keinen Code."
---

# Architektur

1. Repository-Root bestimmen und `CLAUDE.md` als einzige normative Quelle für Workflow, Pfade, Vorlage und Review-Gate verwenden. Fehlt sie, anhalten; nichts aus `~/.claude` übernehmen.
2. Prüfen, ob das Issue nach den Projektregeln freigegeben ist und ob eine Architekturphase nötig ist. Bei fehlender Freigabe anhalten; bei entbehrlicher Architektur knapp auf `$impl-plan` verweisen.
3. Nur das freigegebene Issue, die einschlägigen `CLAUDE.md`-Abschnitte und die dort verlinkte Architekturvorlage lesen. Referenzen gezielt und token-sparsam öffnen.
4. Normale Architekturentscheidungen mit `architekt` (Sol/high) erarbeiten; kritische Sicherheits-, Daten-, Berechtigungs-, Migrations-, Konkurrenz- oder Recovery-Entscheidungen mit `architekt_kritisch` (Astra/xhigh). Rein redaktionelle Nachzüge bereits freigegebener Entscheidungen mit Terra/medium, bei Bedarf `dokumentierer`. Scope, Pfad, Freigaben und Vorlage knapp übergeben; keine vollständige Gesprächsvererbung oder zusätzliche Autoren. Keine nicht angeforderte Produktfunktion aufnehmen.
5. Das fertige Architekturartefakt sequenziell nach `CLAUDE.md` unabhängig kalt prüfen: `reviewer_kritisch` (Astra/xhigh) für kritische Entscheidungen, `reviewer` (Terra/high) für normale Änderungen und redaktionelle Nachzüge. Blockierende Findings gebündelt beheben und den vollständigen Scope erneut prüfen. Keine gleichzeitigen Änderungen am Prüfgegenstand oder parallelen Reviews ohne ausdrücklichen Nutzerwunsch.
6. Offene Fragen mit dem Nutzer klären und gemäß Vorlage dokumentieren. Am vorgeschriebenen menschlichen Freigabe-Gate anhalten.
7. Nach expliziter Freigabe nur die erlaubte Statusänderung durchführen. Weder Implementierungsplan noch Code automatisch beginnen.
