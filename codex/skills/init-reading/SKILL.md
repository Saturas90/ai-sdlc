---
name: init-reading
description: "Erfasst den aktuellen Projektstand eines Repositories token-sparsam anhand seiner CLAUDE.md und der dort benannten Statusquelle. Explizit mit $init-reading zu Beginn einer neuen Session verwenden; liefert aktives Issue, nächste Schritte und Blocker, ohne Dateien zu ändern."
---

# Projektstand erfassen

Mit Terra/medium direkt ausführen. Für diese kurze Bestandsaufnahme keine Unteragenten oder Reviews starten; bereits gelesene unveränderte Regeln nicht erneut laden.

1. Repository-Root bestimmen und `CLAUDE.md` als normative Navigations- und Prozessquelle verwenden. Fehlt sie, anhalten; keine Annahmen aus `~/.claude` übernehmen.
2. Aus `CLAUDE.md` die zentrale Statusquelle, die relevanten Abschnitte und die Regeln zur Token-Ökonomie bestimmen.
3. Die Statusquelle gezielt lesen: Fokus/aktueller Stand, Issue-Tabelle und die dort benannte Reihenfolge beziehungsweise GTM-Sequenz. Keine großen Archive, Glossare, Visionen oder Issue-Artefakte vollständig laden.
4. Nur bei einem konkreten Klärungsbedarf gezielt per Suche, Anker und kleinem Ausschnitt in die von `CLAUDE.md` verlinkten Detaildokumente schauen.
5. Knapp ausgeben:
   - aktueller Projektstand und aktives Issue,
   - nächste zulässige Schritte laut normativer Reihenfolge,
   - offene Punkte oder Blocker.
6. Keine Datei ändern, keinen Plan erstellen und keine Implementierung starten.
