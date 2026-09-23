---
name: implementieren
description: "Arbeitet einen freigegebenen Implementierungsplan kontrolliert und schrittweise nach der CLAUDE.md des Repositories ab. Explizit mit $implementieren verwenden, wenn die Implementierungsphase freigegeben ist; setzt nur geplanten Scope um, testet und reviewt jede Einheit."
---

# Implementieren

1. Repository-Root bestimmen und `CLAUDE.md` als einzige normative Quelle für Scope, Reihenfolge, Tests, Reviews und erlaubte Statusänderungen verwenden. Fehlt sie, anhalten; keine Workflow-Regeln aus `~/.claude` übernehmen.
2. Prüfen, ob der maßgebliche Implementierungsplan nach den Projektregeln freigegeben ist. Issue, Architektur und Plan nur im für die nächste offene Einheit nötigen Umfang lesen.
3. Die nächste zulässige Implementierungseinheit exakt aus dem Plan wählen und sequenziell bearbeiten. Parallelisierung nur auf ausdrücklichen Nutzerwunsch; eine Parallelgruppe im Plan allein löst keine parallelen Agenten aus.
4. `[K]` und sicherheits-, datenverlust-, migrations-, konkurrenz- oder recoverykritische Implementierung an `implementierer_kritisch` (Astra/xhigh) geben. Normale Produktionsimplementierung samt Tests mit Sol/medium bearbeiten: bei passendem aktivem Hauptmodell lokal, sonst mit `implementierer`. Redaktionelle Nachzüge freigegebener Entscheidungen mit Terra, bei Bedarf `dokumentierer`. Fehlende kritische Rolle nicht durch einen normalen Implementierer ersetzen: einen verfügbaren Agenten explizit mit Astra/xhigh und demselben Auftrag verwenden oder die Verfügbarkeitsgrenze melden. Nur nötige Pfade, Freigaben, Scope und Prüfaufträge übergeben; keine vollständige Gesprächsvererbung, doppelte Bearbeitung oder weitere Delegation.
5. Produktionscode und zugehörige Tests in derselben Einheit umsetzen. Erst passende Tests, breite vorgeschriebene Gates gegen den stabilen Stand. Wiederholungen brauchen neue Änderungen, Fehler oder offene Risiken als Anlass. Feststehende Prüfkommandos bei umfangreicher Ausführung an `mechaniker` geben; Auswahl und Fehlerdiagnose bleiben fachliche Arbeit. Logs in Dateien, Ergebnisse und relevante Fehlerausschnitte knapp berichten.
6. Nach Umsetzung und Tests das unabhängige Kaltreview gegen einen unveränderten Stand ausführen: `reviewer` (Terra/high) für normale, `reviewer_kritisch` (Astra/xhigh) für kritische Einheiten. Alle Findings der Runde gesammelt bearbeiten; danach die gesamte Einheit einschließlich Nachbarn und früherer Findings erneut prüfen. Keine parallele Änderung am Prüfgegenstand und keine zweite Reviewspur. Reviewtiefe, Testpflichten und blockierende Severity-Stufen bleiben nach `CLAUDE.md` unverändert.
7. Planschritte erst nach erfolgreicher Verifikation und Review abhaken. Mechanische Änderungen nur an `mechaniker` delegieren, wenn die Projektregeln dies verlangen. Nicht eigenmächtig committen.
8. Bei jeder Abweichung vom freigegebenen Plan sofort anhalten und neue Nutzerfreigabe einholen. Nach der letzten geprüften Einheit auf `$abschluss` verweisen.
