# Arbeitsweise: Tokenverbrauch und Qualität

Diese persönlichen Vorgaben ergänzen die Repository-Regeln. Explizite Nutzeranweisungen und
fachliche Freigaben gelten weiterhin; Qualitätsgates, Scope und Reviewtiefe werden nicht reduziert.

- **Sequenziell als Standard.** Umsetzung, Prüfung, Korrektur und Commit nacheinander.
  Parallelisierung nur auf ausdrücklichen Nutzerwunsch, nicht allein wegen verfügbarer Agenten.
  Eine Parallelgruppe im Plan ist eine Möglichkeit, keine Pflicht. Unteragenten delegieren nicht weiter.
- **Modelle nach Verantwortung:** GPT-6 Sol/medium als Standard für Koordination und
  normale Produktionsimplementierung samt Tests; Sol/high für normale Architekturarbeit.
  GPT-5.6 Terra/medium für Issue-Texte und Dokumentationsnachzüge, Terra/high für
  Implementierungsplanung und normale Kaltreviews. Eine GPT-6-Terra-Variante ist derzeit
  nicht verfügbar; die benannten Terra-Rollen bleiben gezielt auf GPT-5.6.
  GPT-6 Astra/xhigh nur für kritische Architekturentscheidungen, Implementierungen und Reviews.
  Kritisch sind insbesondere `[K]`, Security, Berechtigungen, Secrets, Datenverlust, Recovery,
  Migrationen, Konkurrenz/Crash-Konsistenz und Änderungen an verbindlichen Sicherheitsverträgen.
  Ein redaktioneller Nachzug bereits freigegebener Entscheidungen bleibt Terra-Arbeit.
  GPT-6 Luna/low erledigt exakt vorgegebene mechanische Befehle und Git-Aktionen.
  `ultra`/`max` und Schnellmodus nur bei ausdrücklichem Nutzerwunsch.
- **Delegation gezielt:** Arbeit lokal erledigen, wenn das aktive Modell zur Verantwortung passt;
  bei Sol als Hauptagent normale Implementierung lokal erledigen, sofern kein unabhängiger
  Autor nötig ist. Rollenwechsel für kritische Aufgaben, Dokumentationsarbeit, unabhängige
  Reviews und umfangreiche mechanische Arbeit. Keine Agenten nur zum Einsparen weniger Tokens starten.
  Keine zweite Bearbeitung derselben Aufgabe durch Haupt- und Unteragent. Unteragenten erhalten
  einen knappen Auftrag mit Pfaden, Scope, Freigaben, offenen Findings und Prüfkriterien;
  keine vollständige Gesprächsvererbung als Standard. Ergebnisse: Dateien, Befunde, Tests, Blocker.
- **Stabil prüfen:** Erst Umsetzung und passende Tests abschließen, dann unabhängiges Kaltreview
  gegen einen unveränderten Stand. Zusammengehörige Findings beheben, dann den vollständigen
  relevanten Scope samt Nachbarn erneut prüfen. Keine laufenden Vollreviews während der Bearbeitung.
  Vorgeschriebene Tests und Gates erhalten; breite Läufe nach Stabilisierung, Wiederholungen nur
  wegen neuer Änderungen, Fehler oder offener Risiken. Logs in Dateien, im Kontext nur Ergebnis
  und relevante Fehlerausschnitte. Testlaufzeit allein ist kein Grund für einen zusätzlichen Agenten.
- **Kontext klein halten:** Gezielte Suche/Ausschnitte, keine wiederholten Gesamtdokumente.
  Entscheidungen und offenen Stand in vorhandenen Artefakten pflegen. Bei langer Arbeit kompakte
  Übergabe je Einheit; kein Neustart ohne gesicherten Stand. Wiederkehrende Fehler erst mit einem
  minimalen Reproduzierer diagnostizieren, bevor aufwendige Nachweise erneut laufen.
- **Tokenbudget nach Aufwand:** Nur die aktuelle Phase und benötigte Referenzen laden; Aufträge an
  Rollen mit Pfaden, Scope und Prüfkriterien statt voller Gesprächshistorie übergeben. Erst gezielte
  Tests, breite Pflicht-Gates einmal am stabilen Stand; erneute Läufe nur bei Änderung, Fehler oder
  offenem Risiko. Reasoning nur für konkrete schwierige Arbeit erhöhen.

Die Modelleinstellungen gelten für neue Sitzungen/Agenten; ein laufender Hauptagent wechselt
sein Modell nicht durch eine Dateieditierung. Falls eine nötige Rolle oder ihr Modell nicht verfügbar
ist, die Grenze benennen und kritische Arbeit nicht still auf ein kleineres Modell verlagern.
