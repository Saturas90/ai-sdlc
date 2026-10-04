# Arbeitsweise: Tokenverbrauch und Qualität

Diese persönlichen Vorgaben ergänzen die Repository-Regeln. Explizite Nutzeranweisungen und
fachliche Freigaben gelten weiterhin; Qualitätsgates und Scope werden nicht reduziert. Regelt die
CLAUDE.md des Repositories eine Teilregel selbst (z. B. Rundenumfang, Kaltreview, Freigabe vor
Korrekturen, Budgets), gilt jeweils diese; ausgenommen ist ausschließlich der Codex-Reviewabschluss
nach einer Runde ohne offene Kritisch/Hoch gemäß „Abschluss ohne Bestätigungsrunde“ unten, auch wenn
CLAUDE.md dafür auf ein Claude-Gate mit Fixcheck verweist. Fachliche Qualität, Severity, Evidence,
vorgeschriebene Tests und menschliche Phasenfreigaben bleiben projektbestimmt. Hat CLAUDE.md ein abweichendes
Severity-Schema, vor der ersten Runde die hier verwendeten Stufen (blockierend, mittel, niedrig) darauf
abbilden, bei Unklarheit den Nutzer fragen und die Abbildung im Reviewauftrag und in „Stand“ festhalten.

- **Sequenziell als Standard.** Umsetzung, Prüfung, Korrektur und Commit nacheinander.
  Parallelisierung nur auf ausdrücklichen Nutzerwunsch, nicht allein wegen verfügbarer Agenten.
  Eine Parallelgruppe im Plan ist eine Möglichkeit, keine Pflicht. Unteragenten delegieren nicht weiter.
- **Modelle nach Verantwortung:** GPT-6 Sol/high als Standard des Hauptagenten für Koordination, normale
  Produktionsimplementierung samt Tests und normale Architekturarbeit; die Rolle `implementierer` und
  Unteragenten ohne eigene Rolle laufen auf Sol/medium. GPT-5.6 Terra/medium für Issue-Texte und
  Dokumentationsnachzüge, Terra/high für Implementierungsplanung und normale Kaltreviews. Eine
  GPT-6-Terra-Variante ist derzeit nicht verfügbar; die benannten Terra-Rollen bleiben gezielt auf GPT-5.6.
  GPT-6 Astra/xhigh nur für kritische Architekturentscheidungen, Implementierungen und Reviews. Kritisch
  sind insbesondere `[K]`, Security, Berechtigungen, Secrets, Datenverlust, Recovery, Migrationen,
  Konkurrenz/Crash-Konsistenz und Änderungen an verbindlichen Sicherheitsverträgen. Ein redaktioneller
  Nachzug bereits freigegebener Entscheidungen bleibt Terra-Arbeit. GPT-6 Luna/low erledigt exakt
  vorgegebene mechanische Befehle und Git-Aktionen. `ultra`/`max` und Schnellmodus nur bei ausdrücklichem
  Nutzerwunsch.
- **Delegation gezielt:** Arbeit lokal erledigen, wenn das aktive Modell zur Verantwortung passt;
  bei Sol als Hauptagent normale Implementierung lokal erledigen, sofern kein unabhängiger
  Autor nötig ist. Rollenwechsel für kritische Aufgaben, Dokumentationsarbeit, unabhängige
  Reviews und umfangreiche mechanische Arbeit. Keine Agenten nur zum Einsparen weniger Tokens starten.
  Keine zweite Bearbeitung derselben Aufgabe durch Haupt- und Unteragent. Unteragenten erhalten
  einen knappen Auftrag mit Pfaden, Scope, Freigaben, offenen Findings und Prüfkriterien;
  keine vollständige Gesprächsvererbung als Standard. Ergebnisse: Dateien, Befunde, Tests, Blocker.
  Je Planeinheit einen frischen Autor; einen Autor nur für die Korrekturrunden derselben Einheit
  fortsetzen, höchstens zweimal, danach frisch mit Findings und `kontext.md`. Arbeitet der Hauptagent
  selbst als Autor, gilt das für die Sitzung: je Einheit neu beginnen bzw. ab etwa 200K Kontext mit
  Übergabe in `kontext.md` › Stand wechseln.
- **Stabil prüfen:** Erst Umsetzung und passende Tests abschließen, dann unabhängiges Kaltreview gegen einen
  unveränderten, gesicherten Stand (Rev plus Kopie aller uncommitteten Dateien in einem neuen Unterordner
  der Gate-Ablage, siehe „Kontext klein halten“; dafür ist kein eigener Commit nötig; Rücknahmen nie gegen
  HEAD). Dem Reviewer übergeben: Runde, ab Runde 2 die offenen Findings der Vorrunde als
  Tabelle (ID, Datei:Zeile, ein Satz, Status; bestrittene gekennzeichnet), den Fix-Diff gegen den
  gesicherten Stand und `kontext.md`. Blockierende Findings (kritisch/hoch) samt Mittel
  derselben Runde gesammelt beheben, dann erneut prüfen: Runde 1 und 2 vollständig samt Nachbarn, ab Runde 3
  nur Vorrunden-Blocker und Fix-Diff samt Nahtstellen; neuer Scope, neue Akzeptanzkriterien, Verträge oder
  normative Klauseln und Nutzerentscheidungen werden dabei voll geprüft. Ein früheres Finding mit Status
  unzureichend oder Regression bleibt offen; maßgeblich ist die neu gemeldete Severity, ohne neue Meldung
  die bisherige. Wurde der Fix eines früheren Blockers umgesetzt und wird der verbleibende Mangel nur noch
  als mittel/niedrig gemeldet, gilt er als Blocker behoben; der Rest läuft wie jedes Mittel/Niedrig-Finding.
  Abgelehnte und gemeldete Blocker regeln die folgenden Sätze. Lehnt der Autor einen Blocker mit Beleg ab,
  bleibt er offen, bis der Reviewer der nächsten Runde (ohne Autorenbegründung) oder der Nutzer die
  Ablehnung bestätigt. Keine laufenden Vollreviews während der Bearbeitung. Vorgeschriebene Tests und Gates
  erhalten; breite Läufe nach Stabilisierung, Wiederholungen nur wegen neuer Änderungen, Fehler oder offener
  Risiken. Logs in Dateien, im Kontext nur Ergebnis und relevante Fehlerausschnitte. Testlaufzeit allein ist
  kein Grund für einen zusätzlichen Agenten.
- **CI-Prüfungen vor Git-Aktionen:** Vor jedem Commit und autorisierten Push die Projekt-Gate-Kette aus
  `CLAUDE.md` mit den vorhandenen tatsächlichen CI-Prüfungen in `.github/workflows/` und deren aufgerufenen
  Skripten abgleichen. Alle relevanten, lokal ausführbaren CI-Validierungen am endgültigen zu committenden
  Stand erfolgreich ausführen; dazu gehören vorhandene Format-, Lint-, Typ-, Test- und Buildprüfungen im
  CI-Prüfmodus samt nötigen Tool-, Runtime- und Dependency-Voraussetzungen aus CI. Gezielte Tests ersetzen
  verpflichtende umfassendere CI-Checks nicht. Gültige Nachweise auf demselben relevanten Stand wiederverwenden;
  nach späteren relevanten Änderungen nur dadurch ungültige Checks erneut ausführen. Fehlgeschlagene oder fehlende
  erforderliche Prüfnachweise blockieren Commit und Push. Nicht lokal ausführbare erforderliche Prüfungen
  transparent benennen und das weitere Vorgehen mit dem Nutzer klären, ohne eine grüne CI zu behaupten.
  Deployment-Jobs nicht automatisch lokal ausführen. Gibt es keine CI-Workflows, gelten die bestehenden
  Projekt-Gates; diese Regel verlangt keinen Aufbau einer CI-Pipeline.
- **Abschluss ohne Bestätigungsrunde:** Sobald eine Reviewrunde keine offenen Kritisch/Hoch enthält
  (auch keine ungeklärten bestrittenen oder gemeldeten Blocker), endet die Reviewschleife. Mittel
  grundsätzlich minimal einarbeiten; nur mit konkretem Grund und Ziel vertagen, wenn ein Fix nicht
  gefahrlos und lokal möglich ist. Niedrig nach Ermessen einarbeiten oder begründet vertagen. Danach
  weder weitere Reviewrunde noch Fixcheck, neuer Reviewer oder unabhängige Verify-Stimme. Erforderliche
  Tests und Pflicht-Gates nach Codeänderungen ausführen; Testergebnisse nicht als Review ausgeben.
  Unmittelbar vor dem Fix-Durchgang HEAD, `git status --porcelain -uall` und Inhalts-Hashes mit
  `manifest-vor.txt` abgleichen; bei fremden Änderungen oder unklarer Herkunft melden und nichts davon
  zurücknehmen. Die Autor-Ergebnisse je Finding knapp mit Fundstellen bzw. Vertagungsgrund und Ziel
  protokollieren; Vertagtes in `kontext.md` › Vertagt und beim Abschluss in der Zusammenfassung führen.
  Neu erkannte Blocker oder Entscheidungsbedarf stoppen den Abschluss und gehen an den Nutzer; niemals
  als Mittel vertagen. Menschliche Phasenfreigaben bleiben erforderlich.
- **Konvergenz:** Bestätigt Runde 3 oder eine spätere Runde noch Blocker, anhalten und dem Nutzer Verlauf
  und Optionen vorlegen (Grundsatzentscheidung, Variante streichen, Scope schneiden, weitere Runden mit
  Anzahl); nach den gewählten Runden gilt der Stopp erneut. Mehr als 10 Blocker oder mehr als 40 Findings in
  einer Runde heißen: Gegenstand zu groß, dem Nutzer melden. Für Einheiten mit `Prüftiefe: L` sieht Codex
  keinen Mutationsnachweis vor: vor der Umsetzung dem Nutzer melden.
- **Korrekturen minimal:** Nur die übergebenen Findings, lokal; Formulierungsvorschläge aus Findings nicht
  ungeprüft übernehmen, neue Sachaussagen gegen Code oder Primärquelle prüfen, dieselbe Regel an allen
  Fundstellen gleichziehen, Unzutreffendes mit Beleg ablehnen. Melden statt umsetzen, was Scope,
  Akzeptanzkriterien, Verträge, freigegebene Entscheidungen oder die Schrittstruktur ändert oder eine
  Nutzerentscheidung braucht — nach einer Runde ohne Blocker zusätzlich, was eine neue Regel, Variante oder
  einen neuen Ablaufschritt einführt, also das Ergebnis eines schon eindeutig geregelten Falls ändert, ohne
  dass eine vorrangige Quelle (CLAUDE.md, freigegebenes Artefakt, Nutzerentscheidung, normatives Dokument)
  es so vorgibt, oder eine Fallunterscheidung schafft, die andere Stellen mitbeachten müssen; widersprechen
  sich zwei Stellen ohne klare Rangfolge, melden. Nicht darunter fallen Korrekturen (Angleichen an eine
  solche vorrangige Quelle; die Quelle an eine abweichende Kopie anzugleichen ist keine Korrektur) und
  Präzisierungen bestehender Aussagen, Verweise, Wortlaut, die Gliederung des Dokuments und durch Tests
  abgedeckte lokale Robustheits-Fixes im Code ohne Vertragsänderung. Ergebnis je Finding: umgesetzt (mit
  Fundstellen Datei:Zeile), abgelehnt mit Grund, gemeldet oder vertagt mit Grund und Ziel. Nach einer
  blockerfreien Runde Mittel grundsätzlich minimal einarbeiten und nur bei nicht gefahrlos lokalem Fix
  vertagen; Niedrig nach Ermessen. Neu erkannte Blocker und Entscheidungsbedarf melden, nicht vertagen.
- **Kontext klein halten:** Gezielte Suche/Ausschnitte, keine wiederholten Gesamtdokumente. Liegt im
  Issue-Ordner ein `kontext.md` (Anker mit Datei:Zeile, Normauszüge, Tests, bewusst Irrelevantes, Vertagtes,
  Stand; höchstens 8 KB), zuerst diese Datei lesen, ab den Ankern gezielt suchen und neue relevante Stellen
  dort ergänzen; Reviewer begrenzt sie nicht, sie schreiben nicht hinein. Fehlt sie, legt die erste Phase
  sie an, die sie braucht, sofern CLAUDE.md sie nicht ausschließt; eine bloße Aufzählung der Ordnerinhalte
  schließt sie nicht aus. Der Hauptagent überschreibt „Stand“ (bzw. die dort verwiesene projekteigene
  Übergabe) vor jedem Commit und mitten im Gate am Ende jeder Runde sowie vor Abschlusskorrekturen (Gegenstand, Runde,
  Gate-Schritt, offene Findings als Tabelle oder Verweis auf eine Datei in der Gate-Ablage, Unterordner der
  jüngsten Sicherung, ggf. Stufen-Abbildung); eine neue Sitzung setzt dort fort, statt neu zu erzeugen. Die
  Gate-Ablage für Sicherungen, Findings-Tabellen und Fix-Protokoll ist ein gitignorierter Projektordner,
  Standard `.gate-logs/<issue>/` (ohne Issue `<gegenstand>`); eine Projektregel hat Vorrang. Nie Scratchpad,
  Temp oder Issue-Ordner. Fehlt der Ignore-Eintrag, ihn in der Datei aus
  `git rev-parse --git-path info/exclude` ergänzen; erfasst ein Test-, Lint- oder Build-Werkzeug die Ablage
  dennoch, dem Nutzer melden, statt die Projektkonfiguration zu ändern. Jede Sicherung kommt in einen neuen
  Unterordner `<gegenstand>-r<N>/` (bei Wiederholung mit Suffix, nie überschreiben): Kopie aller
  uncommitteten Dateien und `manifest-vor.txt` (HEAD-Rev; je Datei aus `git status --porcelain -uall` Pfad,
  Status, mtime und Inhalts-Hash per `git hash-object`, bei gelöschten Dateien `-`). Basis für den
  Korrektur-Diff ist die jüngste Sicherung des Gegenstands. Artefaktbudgets ohne Projektwerte: Issue ≤ 12 KB,
  Architektur und Plan ≤ 20 KB, Zusammenfassung ≤ 6 KB, jedes weitere geprüfte Dokument ≤ 25 KB; gesprengt
  heißt schneiden, in `kontext.md` zuerst Anker kürzen, nie „Vertagt“ oder „Stand“. Entscheidungen und
  offenen Stand in vorhandenen Artefakten pflegen. Kein Neustart ohne gesicherten Stand. Wiederkehrende
  Fehler erst mit einem minimalen Reproduzierer diagnostizieren, bevor aufwendige Nachweise erneut laufen.
- **Tokenbudget nach Aufwand:** Nur die aktuelle Phase und benötigte Referenzen laden; Aufträge an Rollen
  mit Pfaden, Scope und Prüfkriterien statt voller Gesprächshistorie übergeben. Erst gezielte Tests, breite
  Pflicht-Gates einmal am stabilen Stand; erneute Läufe nur bei Änderung, Fehler oder offenem Risiko.
  Reasoning nur für konkrete schwierige Arbeit erhöhen.

Die Modelleinstellungen gelten für neue Sitzungen/Agenten; ein laufender Hauptagent wechselt
sein Modell nicht durch eine Dateieditierung. Falls eine nötige Rolle oder ihr Modell nicht verfügbar
ist, die Grenze benennen und kritische Arbeit nicht still auf ein kleineres Modell verlagern.
