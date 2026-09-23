---
name: review
description: "Führt ein unabhängiges Kaltreview von Dokumenten, Plänen, Code oder Diffs nach dem Severity- und Evidence-Schema der Repository-CLAUDE.md durch. Explizit mit $review verwenden; bewertet und berichtet Findings, verändert den geprüften Gegenstand aber nicht."
---

# Review

1. Repository-Root bestimmen und `CLAUDE.md` als einzige normative Quelle für Scope, Severity, Evidence, Nachbarprüfungen und Ausgabeformat verwenden. Fehlt sie, anhalten; keine Review-Regeln aus `~/.claude` übernehmen.
2. Prüfgegenstand und zugehörigen Kontext bestimmen: Issue, gegebenenfalls Architektur und Plan sowie betroffene Nachbarbauteile und behauptete Fakten.
3. Risiko nach `CLAUDE.md` einstufen. Genau einen unabhängigen Reviewer einsetzen: Standardfälle einschließlich normaler Architekturänderungen `reviewer` (Terra/high); `[K]` und kritische Sicherheits-, Berechtigungs-, Daten-, Migrations-, Konkurrenz- oder Recovery-Entscheidungen `reviewer_kritisch` (Astra/xhigh). Redaktionelle Nachzüge ohne neue kritische Entscheidung bleiben Standardfälle. Keine parallelen Reviewer ohne ausdrücklichen Nutzerwunsch. Kritische Reviews bei fehlendem Astra nicht still mit Terra freigeben.
4. Erst gegen einen stabilen Prüfstand beginnen; keine gleichzeitigen Änderungen daran. Immer ein Kaltreview durchführen: Findings der Vorrunde verifizieren, danach den vollständigen relevanten Scope samt Nachbarn neu scannen und zitierte Tatsachen gegen Code oder Primärquelle prüfen. Nicht nur den Diff betrachten. Dem Reviewer Scope, Pfade und bisherige Findings knapp übergeben, keine Autorenbegründung oder volle Gesprächshistorie als Vorprägung. Findings einer Runde gebündelt zurückgeben.
5. Findings nach dem exakten Schema aus `CLAUDE.md`, absteigend nach Severity und mit konkreter Fundstelle/Evidence sowie Maßnahme ausgeben. Leere Severity-Stufen ausdrücklich als leer ausweisen, wenn `CLAUDE.md` dies verlangt.
6. Nur bewerten. Keine Dateien verändern, keine Findings selbst beheben und nicht committen.
