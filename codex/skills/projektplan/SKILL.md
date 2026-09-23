---
name: projektplan
description: "Erstellt oder aktualisiert den Projektplan eines Repositories strikt nach dessen CLAUDE.md. Explizit mit $projektplan verwenden, wenn ein Projekt strukturiert, eine Roadmap gepflegt oder die Issue-Reihenfolge geplant werden soll; implementiert keinen Produktionscode."
---

# Projektplan

1. Repository-Root bestimmen und dessen `CLAUDE.md` als einzige normative Prozessquelle verwenden. Fehlt die Datei, anhalten und den Nutzer darauf hinweisen. Keine Regeln oder Vorlagen aus `~/.claude` übernehmen.
2. In `CLAUDE.md` nur die Abschnitte zu Workflow, Projektplan, Nummerierung, Dokumentation und verlinkten Vorlagen heranziehen. Verlinkte große Dokumente ausschließlich gezielt lesen.
3. Den in `CLAUDE.md` benannten Projektplan lokalisieren. Existiert er, gezielt aktualisieren und nicht überschreiben.
4. Ziel, Meilensteine, Issue-Liste, Abhängigkeiten und offene Entscheidungen nur im von `CLAUDE.md` verlangten Umfang klären. Fehlende wesentliche Angaben erfragen, nicht erfinden.
5. Den Entwurf mit Terra/medium im vorgegebenen Format erstellen; reine Nachzüge bei Bedarf an `dokumentierer` mit knappen Quellpfaden geben. Keine Issues ausarbeiten und keinen Code ändern. Keine doppelte Bearbeitung oder vollständige Gesprächsvererbung.
6. Das in `CLAUDE.md` vorgeschriebene Review-Gate gegen den fertigen Stand unabhängig ausführen: `reviewer` (Terra/high), bei kritischen Architektur-/Sicherheitsentscheidungen `reviewer_kritisch` (Astra/xhigh). Keine gleichzeitige Änderung am Prüfgegenstand; sequenziell, sofern der Nutzer nicht ausdrücklich parallele Arbeit verlangt.
7. An jedem in `CLAUDE.md` definierten Freigabe-Gate anhalten. Status- oder Git-Aktionen nur ausführen, wenn die Projektregeln und die Nutzerfreigabe sie erlauben.
