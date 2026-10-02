# Arbeitsweise: Tokenverbrauch und Qualität

Diese persönlichen Vorgaben ergänzen die Repository-Regeln. Explizite Nutzeranweisungen und
fachliche Freigaben gelten weiterhin; Qualitätsgates und Scope werden nicht reduziert. Regelt die
CLAUDE.md des Repositories eine Teilregel selbst (z. B. Rundenumfang, Kaltreview, Freigabe vor
Korrekturen, Budgets), gilt jeweils diese; alles Übrige unten bleibt bestehen. Hat sie ein abweichendes
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
  HEAD). Dem Reviewer übergeben: Runde bzw. Fixcheck, ab Runde 2 die offenen Findings der Vorrunde als
  Tabelle (ID, Datei:Zeile, ein Satz, Status; bestrittene gekennzeichnet), den Fix-Diff gegen den
  gesicherten Stand und `kontext.md`; für den Fixcheck die eingearbeiteten Findings der Runde mit ID, das
  Fix-Protokoll mit Fundstellen je ID und den Fix-Diff. Blockierende Findings (kritisch/hoch) samt Mittel
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
- **Abschluss ohne Bestätigungsrunde:** Liefert eine Runde nur mittel/niedrig, ist das Gate erfüllt: Mittel
  einarbeiten, Niedrig nach Ermessen, dann **ein** Fixcheck nur des Fix-Diffs (alle Änderungen dieses
  Fix-Durchgangs gegen den gesicherten Stand, auch außerhalb des Gegenstands; nicht dazu gehören
  Ablage-Dateien (`kontext.md`, Gate-Ablage, Übergaben) und Änderungen anderer Sitzungen; Änderungen
  unklarer Herkunft nie zurücknehmen, sondern dem Nutzer melden; weicht unmittelbar vor dem Fix-Durchgang
  der Stand (`git status --porcelain -uall` samt Hashes) außerhalb der Ablage-Dateien von `manifest-vor.txt`
  ab oder gibt es einen neuen Commit, arbeitet eine andere Sitzung im selben Arbeitsbaum: vor dem
  Fix-Durchgang melden) durch den Reviewer der Runde — keine weitere Runde. Der Reviewer liefert Befunde
  (gekennzeichnet mit Finding-ID, „ohne Auftrag“ oder „außerhalb der Fixes“) und eine Zuordnung jeder
  Änderung im Fix-Diff zu Finding-ID(s) oder „ohne Auftrag“; Stellen, die das Fix-Protokoll nicht nennt,
  zählen zum Fix dieser Finding-ID, sofern das Protokoll das Finding als umgesetzt führt; Änderungen zu
  abgelehnten oder gemeldeten Findings und Änderungen, die in der Zuordnung fehlen, gelten als ohne Auftrag.
  Der Hauptagent gleicht Zuordnung und Diff ab und ergänzt das Protokoll. Änderungen ohne Auftrag nimmt der
  Autor auch ohne Befund zurück, nur diese Zeilen (untrennbar von einem Fix: der Fix geht mit zurück und
  wird vertagt); Befunde darin sind damit erledigt, Protokoll „zurückgenommen, ohne Auftrag“. Befund ab
  mittel an einem Fix (auch an einer Nachbarstelle, die der Fix verursacht): alle Änderungen dieses Fixes
  zurücknehmen, sodass der Bereich wieder dem gesicherten Stand entspricht, und das Finding vertagen.
  Zurückgenommen wird nur bei klarer Herkunft: Beim Sichern und am Ende des Fix-Durchgangs hält der
  Hauptagent `manifest-vor.txt` bzw. `manifest-nach.txt` in derselben Sicherung fest; vor der ersten
  Rücknahme ist HEAD unverändert, die Manifeste unterscheiden sich nur bei vom Autor als bearbeitet
  gemeldeten Dateien und bei Ablage-Dateien, und außer den Ablage-Dateien entspricht alles noch dem zweiten
  Manifest. Sonst oder im Zweifel nichts zurücknehmen: jede fällige Rücknahme samt Befunden an den Nutzer,
  ein Befund ab hoch darin hält das Gate bis zu seiner Entscheidung, Protokoll „gemeldet, unklare Herkunft“.
  Fremde Änderungen in Dateien, die auch der Autor geändert hat, erkennt kein Manifest; deshalb vor der
  ersten Rücknahme jede betroffene Datei in ihrem aktuellen Stand unter ihrem repo-relativen Pfad nach
  `vor-ruecknahme/` in derselben Sicherung kopieren, damit jede Rücknahme umkehrbar bleibt. Befund außerhalb
  der Fixes (nur an Stellen, die keine Änderung im Fix-Diff verursacht hat): ab hoch ist das Gate nicht
  erfüllt und der Nutzer entscheidet; darunter nach Vertagt. Nicht hierher gehören Fixes, die unter
  „Korrekturen minimal“ zu melden sind: Mittel/Niedrig standardmäßig vertagen; Blocker-Fixes und alles mit
  Entscheidungsbedarf dem Nutzer vorlegen, nie selbst vertagen. Fix-Protokoll (samt Zuordnung und
  Rücknahmen) und Vertagtes gehen in die Freigabe-Anfrage; Vertagtes steht laufend in `kontext.md` › Vertagt
  und geht beim Abschluss in die Zusammenfassung.
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
  Fundstellen Datei:Zeile), abgelehnt mit Grund oder gemeldet.
- **Kontext klein halten:** Gezielte Suche/Ausschnitte, keine wiederholten Gesamtdokumente. Liegt im
  Issue-Ordner ein `kontext.md` (Anker mit Datei:Zeile, Normauszüge, Tests, bewusst Irrelevantes, Vertagtes,
  Stand; höchstens 8 KB), zuerst diese Datei lesen, ab den Ankern gezielt suchen und neue relevante Stellen
  dort ergänzen; Reviewer begrenzt sie nicht, sie schreiben nicht hinein. Fehlt sie, legt die erste Phase
  sie an, die sie braucht, sofern CLAUDE.md sie nicht ausschließt; eine bloße Aufzählung der Ordnerinhalte
  schließt sie nicht aus. Der Hauptagent überschreibt „Stand“ (bzw. die dort verwiesene projekteigene
  Übergabe) vor jedem Commit und mitten im Gate am Ende jeder Runde und vor dem Fixcheck (Gegenstand, Runde,
  Gate-Schritt, offene Findings als Tabelle oder Verweis auf eine Datei in der Gate-Ablage, Unterordner der
  jüngsten Sicherung, ggf. Stufen-Abbildung); eine neue Sitzung setzt dort fort, statt neu zu erzeugen. Die
  Gate-Ablage für Sicherungen, Findings-Tabellen und Fix-Protokoll ist ein gitignorierter Projektordner,
  Standard `.gate-logs/<issue>/` (ohne Issue `<gegenstand>`); eine Projektregel hat Vorrang. Nie Scratchpad,
  Temp oder Issue-Ordner. Fehlt der Ignore-Eintrag, ihn in der Datei aus
  `git rev-parse --git-path info/exclude` ergänzen; erfasst ein Test-, Lint- oder Build-Werkzeug die Ablage
  dennoch, dem Nutzer melden, statt die Projektkonfiguration zu ändern. Jede Sicherung kommt in einen neuen
  Unterordner `<gegenstand>-r<N>/` (bei Wiederholung mit Suffix, nie überschreiben): Kopie aller
  uncommitteten Dateien und `manifest-vor.txt` (HEAD-Rev; je Datei aus `git status --porcelain -uall` Pfad,
  Status, mtime und Inhalts-Hash per `git hash-object`, bei gelöschten Dateien `-`). Basis für Fix-Diff und
  Rücknahmen ist die jüngste Sicherung des Gegenstands. Artefaktbudgets ohne Projektwerte: Issue ≤ 12 KB,
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
