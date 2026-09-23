---
name: abschluss
description: "Schließt ein vollständig implementiertes Issue strikt nach der CLAUDE.md des Repositories ab. Explizit mit $abschluss verwenden, wenn alle Planschritte und Reviews erledigt sind; prüft Scope-Treue, erstellt die vorgeschriebene Zusammenfassung und aktualisiert nur den erlaubten Projektstatus."
---

# Abschluss

1. Repository-Root bestimmen und `CLAUDE.md` als einzige normative Quelle für Abschlussartefakt, Scope-Abgleich und Projektplanpflege verwenden. Fehlt sie, anhalten; keine Vorlagen aus `~/.claude` verwenden.
2. Prüfen, ob alle Implementierungsschritte, Tests und Reviews nach den Projektregeln abgeschlossen sind. Bei offenen Schritten anhalten und sie konkret nennen.
3. Issue, gegebenenfalls Architektur, Implementierungsplan, zugehörige Änderungen sowie die von `CLAUDE.md` verlinkte Zusammenfassungsvorlage gezielt lesen.
4. Jedes Akzeptanzkriterium, jede relevante Architekturentscheidung und jeden Planschritt gegen Implementierung und vorhandene gültige Prüfnachweise abgleichen. Bestandene Prüfungen ohne Änderungen oder neue Risiken nicht erneut ausführen. Ungeplanten Scope oder Abweichungen melden und vor dem Abschluss mit dem Nutzer klären. Neue kritische Befunde vor dem Abschluss an Astra geben; bestehende Qualitätsgates bleiben verbindlich.
5. Den Dokumentationsnachzug mit Terra/medium ausführen, lokal bei passendem aktivem Modell, sonst `dokumentierer` mit knappem Auftrag und Quellpfaden. Die kurze Zusammenfassung im vorgeschriebenen Pfad und Format erstellen. Entscheidungen, Scope-Cuts, Folge-Issues und offene Punkte nur dort dokumentieren, wo die Projektregeln sie vorsehen. Sequenziell arbeiten; keine zusätzlichen Autoren oder Reviewspuren ohne ausdrücklichen Nutzerwunsch.
6. Den Projektplan exakt nach `CLAUDE.md` aktualisieren; insbesondere nur die zulässigen Statusfelder ändern und keine Historie in Steuerungstabellen einfügen.
7. Git-Aktionen nur ausführen, wenn Projektregeln oder Nutzer sie ausdrücklich verlangen. Danach auf `$naechster-schritt` verweisen.
