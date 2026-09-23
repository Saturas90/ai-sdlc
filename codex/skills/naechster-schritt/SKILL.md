---
name: naechster-schritt
description: "Bestimmt token-sparsam die nächste zulässige SDLC-Phase aus CLAUDE.md, Projektplan, Artefakten, Freigaben und Checkboxen. Explizit mit $naechster-schritt verwenden, wenn der Workflow-Stand unklar ist; stößt genau eine Phase an und überschreitet kein menschliches Gate."
---

# Nächster Schritt

Mit Terra/medium direkt routen, ohne parallele Rechercheagenten. Nur die gewählte Phase lädt ihre Detailregeln; ein kritischer Folgeschritt wird dort an Astra übergeben.

1. Repository-Root bestimmen und `CLAUDE.md` als einzige normative Quelle für Phasen, Pfade, Statusmarker und Freigaben verwenden. Fehlt sie, anhalten; keine Marker oder Namensschemata aus `~/.claude` annehmen.
2. Nur die Workflow- und Navigationsabschnitte aus `CLAUDE.md` sowie die minimale Steuerinformation des dort benannten Projektplans lesen. Große Dokumente nicht vollständig laden.
3. Das aktive Issue und seinen Stand ausschließlich anhand der normativen Statusquelle, der erwarteten Artefakte, exakten Freigabemarker, offenen Fragen, Plan-Checkboxen und des Abschlussartefakts bestimmen.
4. Genau eine nächste Aktion wählen:
   - fehlender oder zu aktualisierender Projektplan → `$projektplan`
   - fehlendes oder ungeklärtes Issue → `$issue`
   - erforderliche, noch nicht freigegebene Architektur → `$architektur`
   - fehlender oder noch nicht freigegebener Implementierungsplan → `$impl-plan`
   - offene freigegebene Planschritte → `$implementieren`
   - vollständig implementiertes, noch nicht abgeschlossenes Issue → `$abschluss`
5. Die gewählte Skill-Phase anstoßen oder dem Nutzer eindeutig nennen. Niemals mehrere Phasen in einem Lauf überspringen.
6. An jedem menschlichen Gate anhalten. Sind laut Projektplan alle Issues abgeschlossen, nichts verändern und den Projektabschluss melden.
