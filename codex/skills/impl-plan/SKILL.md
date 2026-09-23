---
name: impl-plan
description: "Erstellt den Implementierungsplan eines freigegebenen Issues strikt nach der CLAUDE.md des Repositories. Explizit mit $impl-plan verwenden, wenn Issue und gegebenenfalls Architektur freigegeben sind; plant Dateien, Tests, Reihenfolge und Review-Punkte, implementiert aber nichts."
---

# Implementierungsplan

1. Repository-Root bestimmen und `CLAUDE.md` als einzige normative Quelle für Voraussetzungen, Pfad, Format, Testregeln und Gates verwenden. Fehlt sie, anhalten; keine Regeln aus `~/.claude` übernehmen.
2. Die Freigaben von Issue und gegebenenfalls Architektur anhand der in `CLAUDE.md` definierten Marker prüfen. Bei unerfüllter Voraussetzung anhalten.
3. Issue, gegebenenfalls Architektur, die einschlägigen `CLAUDE.md`-Abschnitte und die verlinkte Planvorlage lesen. Große Nachbardokumente nur gezielt öffnen.
4. Die Planerstellung mit Terra/high erledigen, bei Bedarf `impl_planer`; keine doppelte Autorenspur oder volle Gesprächsvererbung. Jeden Schritt einzeln prüfbar formulieren und alle von `CLAUDE.md` geforderten Angaben zu Zweck, vollständiger Dateiliste, Tests und Review aufnehmen. Sequenzielle Ausführung ist Standard. Kritische Einheiten mit `[K]` kennzeichnen, damit Implementierung und Review Astra/xhigh verwenden. Große Einheiten vor der Freigabe sinnvoll schneiden; freigegebenen Scope nicht nachträglich still ändern.
5. Den fertigen gesamten Plan unabhängig nach `CLAUDE.md` kalt prüfen: `reviewer` (Terra/high), für kritische Inhalte `reviewer_kritisch` (Astra/xhigh). Blockierende Findings gebündelt beheben und vollständig erneut prüfen. Keine gleichzeitige Änderung am Prüfgegenstand; parallele Agenten nur auf ausdrücklichen Nutzerwunsch.
6. Offene Fragen mit dem Nutzer klären und im Plan dokumentieren. Am menschlichen Freigabe-Gate anhalten.
7. Nach expliziter Freigabe nur die erlaubte Statusänderung durchführen. Keine Implementierung automatisch starten.
