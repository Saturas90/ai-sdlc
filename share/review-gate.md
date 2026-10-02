# Review-Gate — Ablauf

Von jeder Phase verwendet. Kategorien-Definitionen: Severity-Schema der Projekt-CLAUDE.md, falls
vorhanden, sonst `konventionen.md`; weicht das Projektschema ab, bildet die Hauptsession vor Runde 1 alle hier
verwendeten Stufen darauf ab (Blocker = „blockierend“ des Projekts, mittel, niedrig) und fragt bei unklarer
Abbildung den Menschen; die Abbildung gehört ins Prüfpaket und in den „Stand“, Reviewer melden in den
Stufen des Projekts. Regelt die Projekt-CLAUDE.md
Teile des Ablaufs selbst (z. B. Rundenumfang, Kaltreview, Freigabe vor Korrekturen), gilt jeweils diese
Teilregel; alles Übrige hier gilt weiter. Abschnitte 1–5 gelten immer; die Workflow-Muster nur bei
Prüftiefe M/L lesen — bei einem bestrittenen Blocker in Stufe S auch Muster 1 und 3.

## 1. Prüftiefe (vor Runde 1 festlegen)

| Stufe | Gegenstand | Form |
|-------|------------|------|
| **S** | Projektplan, Issue, Impl-Plan ohne `[K]`, normale Impl-Einheit, Zusammenfassung | **ein** Reviewer-Spawn je Runde, kein Workflow, kein Verify (Ausnahme: bestrittener Blocker, Abschnitt 2) |
| **M** | Architekturplan, Impl-Plan mit `[K]`, `[K]`-Einheit | Workflow: höchstens 2 Linsen + Verify der Blocker (Muster 2–5) |
| **L** | Einheit mit `Prüftiefe: L` im freigegebenen Impl-Plan (Sicherheit, Datenverlust, Migration, Recovery; schließt `[K]` ein) oder auf ausdrücklichen Wunsch des Menschen | Workflow: höchstens 4 Linsen + Verify + Mutationsphase (Muster 6); ohne Code und Tests entfällt sie mit Begründung per `log()` |

Reviewer nach Gegenstand, nie schwächer als der erzeugende Sub-Agent (Modell **und** Effort):
Architekturplan oder ADR im Gegenstand → `reviewer-architektur` (opus, xhigh), auch in Stufe S; `[K]`,
`Prüftiefe: L` oder sicherheits-/datenkritischer Inhalt → `reviewer-kritisch` (opus, high); sonst
`reviewer` (sonnet, high). Erzeugnisse der Hauptsession (Projektplan, Zusammenfassung) prüft `reviewer`.
Haiku reviewt nie. Eine höhere Stufe als die Tabelle nur mit Begründung im Chat bzw. per `log()` —
allgemeine Gründlichkeitsvorgaben heben die Stufe nicht an.

## 2. Runde

1. **Prüfpaket** übergeben statt Gesprächsverlauf: Gegenstand (Pfade bzw. Diff-Bereich mit Rev), Runde,
   Bezug (Issue mit AK-IDs, ggf. Architektur/Plan-Schritte), `kontext.md`, Nachbarn, gegen die der
   Gegenstand Annahmen trifft, freigegebene Entscheidungen (nicht neu verhandeln); ab Runde 2 die offenen
   Findings der Vorrunde als Tabelle (ID, Datei:Zeile, ein Satz, Status) und den Fix-Diff gegen den
   gesicherten Stand der Vorrunde. Für den Fixcheck statt Vorrunden-Tabelle und Vorrunden-Fix-Diff: die eingearbeiteten
   Findings der Runde mit ID, das Fix-Protokoll mit Fundstellen je ID und den Fix-Diff gegen den gesicherten
   Stand; Bezug, `kontext.md`, Nachbarn und freigegebene Entscheidungen bleiben im Paket. Keine Rohberichte.
2. **Bewerten** (bestätigte Findings, ohne Verify die gemeldeten; Dubletten erst nach dem Urteil
   zusammengefasst):
   - ≥ 1 kritisch/hoch → geprüften Stand sichern (Rev plus Kopie aller uncommitteten Dateien; Basis für Fix-Diff und
     Rücknahmen, nie HEAD), dann
     Korrektur durch den Erzeuger: Blocker und Mittel der Runde, Niedrig nach Ermessen, als deduplizierte
     Liste (Kategorie, Datei:Zeile, Maßnahme); Regeln: „Korrektur nach Review“ in `konventionen.md`. Dann
     nächste Runde (Abschnitt 4). Das Artefakt **nicht** komplett neu erzeugen.
   - nur mittel/niedrig → **Gate erfüllt** → Abschnitt 3.
   - Ein Vorrunden-Blocker mit Status unzureichend oder Regression bleibt offen und zählt für das Gate mit;
     maßgeblich ist die neu gemeldete Severity des verbleibenden Mangels (in M/L nach Verify), ohne neue Meldung
     die bisherige. Wurde sein Fix umgesetzt (Fix-Protokoll) und ist der Rest nur noch mittel/niedrig oder
     widerlegt Verify die Neumeldung, gilt er als Blocker behoben; der Rest läuft wie jedes
     Mittel/Niedrig-Finding. Bestrittene und gemeldete Blocker regelt der nächste Punkt.
   - **Bestrittener Blocker:** Bestreitet der Erzeuger einen Blocker mit Beleg, prüfen ihn Stimmen nach
     Muster 3 — auch in Stufe S, ohne Beleg und Urteil des Erzeugers; das Ergebnis bestimmt Muster 3
     (widerlegt erst, wenn zwei Stimmen widerlegen). Einen schon per Verify bestätigten Blocker kippt nur der
     Mensch. Ein gemeldeter Blocker-Fix (Scope, Vertrag, Entscheidung) bleibt offener Blocker, bis der Mensch
     entschieden hat; von sich aus vertagt die Session Blocker nie.
3. **Vollständigkeit:** Ist ein Reviewer, eine Linse oder der Fixcheck ausgefallen oder ohne gültiges
   Ergebnis zurückgekommen, gibt es dafür kein Urteil — einmal wiederholen, sonst abbrechen und dem Menschen
   melden. Ein fehlendes Review ist nie „keine Findings“. Ausgefallene Verify-Stimmen regelt Muster 3 (das
   Finding hält).
4. **Session-Wechsel mitten im Gate:** Am Ende jeder Runde und vor dem Fixcheck schreibt die Hauptsession
   „Stand“ in `kontext.md` (bzw. die dort verwiesene projekteigene Übergabe-Ablage): Gegenstand, Prüftiefe,
   Runde, Gate-Schritt (Review / Korrektur / Fixcheck), offene Findings (als Tabelle oder Verweis auf
   eine Datei im Issue-Ordner bzw. an einem anderen sitzungsübergreifenden Ort, nie Scratchpad/Temp), Ablage
   des gesicherten Stands, ggf. die Stufen-Abbildung. Eine
   neue Session setzt dort fort, statt den Entwurf neu zu erzeugen.

## 3. Abschluss nach einer Mittel/Niedrig-Runde — keine Bestätigungsrunde

Die Review-Schleife endet mit der Runde, die nur noch mittel/niedrig liefert:
1. Geprüften Stand sichern (wie in Abschnitt 2) und Parallel-Check (mtimes der Dateien aus `git status`,
   jüngster Commit); arbeitet eine andere Session im selben Arbeitsbaum, vor dem Fix-Durchgang dem Menschen
   melden. Der Erzeuger arbeitet Mittel ein, Niedrig nach Ermessen („Korrektur nach
   Review“ in `konventionen.md`; dort steht auch, welche Fixes nicht hierher gehören — sie werden gemeldet,
   standardmäßig vertagt und nur mit regulärer Runde umgesetzt).
2. **Fixcheck statt Runde:** **ein** Spawn des Reviewer-Typs der Runde prüft nur den Fix-Diff — alle Änderungen
   dieses Fix-Durchgangs gegen den gesicherten Stand, auch außerhalb des Gegenstands (Nahtstellen); nicht dazu
   gehören Ablage-Dateien des Workflows (`kontext.md`, Fix-Protokoll, Übergaben) und Änderungen anderer
   Sessions. Änderungen unklarer Herkunft werden nie zurückgenommen, sondern dem Menschen gemeldet. Er sucht neue Fehler, falsche Sachaussagen und Widersprüche zu
   freigegebenen Entscheidungen oder Nachbarstellen. Kein Re-Scan, keine Linsen, kein Verify. Er gibt
   Befunde und eine Zuordnungsliste zurück:
   - **Zuordnung:** jede Änderung im Fix-Diff (zusammenhängende geänderte Zeilen) → Finding-ID(s) oder „ohne
     Auftrag“. Stellen, die das Fix-Protokoll nicht nennt (z. B. eine vergessene Nahtstelle), zählen zum Fix
     dieser Finding-ID, sofern das Protokoll das Finding als umgesetzt führt; eine Änderung zu einem
     abgelehnten oder gemeldeten Finding gilt als „ohne Auftrag“. Die Hauptsession gleicht Liste und Diff ab:
     Fehlt eine Änderung in der Liste, gilt sie als „ohne Auftrag“; zugeordnete Stellen trägt sie ins
     Protokoll nach.
   - **Befunde:** je Befund die Finding-ID des verursachenden Fixes (auch an einer Nachbarstelle, die der Fix
     verursacht hat), „ohne Auftrag“ (Befund in einer Änderung ohne Auftrag) oder „außerhalb der Fixes“ — das
     sind nur Befunde an Stellen, die keine Änderung im Fix-Diff verursacht hat.

   Folgen:
   - Änderung ohne Auftrag → der Erzeuger nimmt sie auch ohne Befund auf den gesicherten Stand zurück, nur
     diese Zeilen; lässt sie sich von einem Fix nicht trennen, geht dieser mit zurück und wird vertagt.
     Befunde darin sind damit erledigt. Protokoll: „zurückgenommen, ohne Auftrag“.
   - Befund ab mittel an einem Fix → der Erzeuger nimmt alle Änderungen dieses Fixes (laut Fix-Protokoll
     samt Zuordnung) gemeinsam zurück, sodass der Bereich wieder dem gesicherten Stand entspricht; gehört
     eine Änderung zu mehreren Fixes, gehen diese mit zurück. Die betroffenen Findings werden vertagt; keine
     weitere Runde. Niedrig → nur ins Fix-Protokoll.
   - Befund außerhalb der Fixes: ab hoch → Gate nicht erfüllt, der Mensch entscheidet (reguläre Runde,
     vertagen oder bewusst akzeptieren); darunter → nach `kontext.md` › Vertagt.
3. Bei Code laufen nach Fixes und Rücknahmen die betroffenen Tests und die Gate-Kette erneut grün.
4. Das Fix-Protokoll (umgesetzt / abgelehnt mit Grund / gemeldet / zurückgenommen, auch „ohne Auftrag“) geht
   in die Freigabe-Anfrage. Vertagtes steht in `kontext.md` › Vertagt (eine Zeile je Finding mit Ziel) und geht
   beim Abschluss in die Zusammenfassung.

Jeder Blocker-Fix wird damit weiter von einer regulären Runde geprüft; nur Mittel/Niedrig-Fixes laufen über
den Fixcheck.

## 4. Folgerunden und Konvergenz

- **Umfang:** Runde 1 und 2 sind volle Kaltreviews: Vorrunden-Findings verifizieren (erledigt /
  unzureichend / Regression), dann vollständiger Re-Scan des Gegenstands samt Nachbarn, zitierte Fakten
  gegen Code bzw. Quelle. Ab Runde 3 **Delta:** Vorrunden-Blocker und der Fix-Diff samt Nahtstellen (gleiche
  Regel an anderen Stellen, Aufrufer, Verweise). Kamen seit der Vorrunde neuer Scope, neue
  Akzeptanzkriterien, Verträge oder normative Klauseln oder Entscheidungen des Menschen hinzu, prüft die
  Runde diese Teile voll wie in Runde 1, samt Nahtstellen zum Rest.
- **Konvergenz-Stopp:** Bestätigt Runde 3 oder eine spätere Runde noch Blocker, nicht weiter feilen. Dem
  Menschen einen Konvergenzbericht vorlegen (je Runde erhoben / bestätigt / widerlegt, Anteil Regressionen
  eigener Fixes, wiederkehrende Themen) mit Optionen: Grundsatzentscheidung statt Wortlaut-Feilen, Variante
  streichen, Scope schneiden bzw. Issue teilen, bewusst weitere Runden (mit Anzahl). Weiter erst nach seiner
  Entscheidung; nach den gewählten Runden gilt der Stopp erneut.
- **Findings-Flut:** Mehr als 10 Blocker oder mehr als 40 Findings in einer Runde (Dubletten grob
  zusammengefasst) heißen: Gegenstand zu groß oder unreif. Nicht einzeln verifizieren und abarbeiten,
  sondern dem Menschen melden und schneiden bzw. grundsätzlich überarbeiten.

## 5. Freigabe

- **Planungsartefakte:** Prüftiefe, Runden, Ergebnis der letzten Runde, Fixcheck und Fix-Protokoll kurz
  nennen (offene Mittel/Niedrig und Vertagtes auflisten), dann um explizite Freigabe bitten — bei stehender
  Freigabe (`konventionen.md`) direkt freigeben. Erst danach weiter.
- **Impl-Einheiten:** kein Human-Gate pro Einheit. Nach erfülltem Gate und abgeschlossenem Abschnitt 3
  (Fixcheck, Rücknahmen, Tests grün) abhaken + committen (an `mechaniker` (haiku) delegieren).

## Workflow-Muster (Prüftiefe M/L)

Gilt für jedes Workflow-Skript mit Review-, Verify-, Fixcheck- oder Widerlegen-Stufen. Workflow-Namen:
`<gegenstand>-r<N>` (N = Runde), ein eigener Fixcheck-Workflow `<gegenstand>-r<N>-fixcheck` — die
Verbrauchsauswertung gruppiert danach.

1. **`agentType` ist Pflicht** — im Workflow `agentType`, im Agent-Tool `subagent_type`. Ohne erbt der
   Spawn Hauptmodell, Effort (xhigh) und den vollen Tool-Satz (gemessen 09/2026: ~50K statt ~26K Tokens
   Start-Prompt); `general-purpose` nie für SDLC-Arbeit.

   | Rolle | `agentType` |
   |---|---|
   | Linse, Fixcheck, Verify-Stimme (auch Bündel) | `reviewer-kritisch`; Nicht-[K]-Artefakte von Sonnet-Erzeugern auch `reviewer` |
   | **Gegenstand Architekturplan** — alle Linsen, Stimmen und der Fixcheck (Vorrang vor der Zeile darüber) | `reviewer-architektur` |
   | Mutation (Testwirksamkeit) — immer allein in eigener serieller Phase, nie parallel zu lesenden Linsen | `mutations-pruefer` |
   | Überarbeiten, Fixen | der erzeugende Agent (`issue-autor`, `architekt`, `impl-planer`, `implementierer`) |
   | Erheben, Recherche in Repo **oder Web** | `rechercheur`; reine Dateisuche auch `Explore` mit explizitem `effort`; Fragen zu Claude Code: `claude-code-guide` |
   | Abhaken, Committen | `mechaniker` |

   Enthält der Gegenstand `architecture.md` oder ein ADR, laufen alle Linsen und Stimmen dazu über
   `reviewer-architektur`, auch bei gemischtem Gegenstand. Passt keine Rolle: `model` **und** `effort`
   explizit setzen und per `log()` begründen. Skripte leiten „Blockierend“ aus den Severities ab. Neue oder
   geänderte Agenten wirken erst nach einem Session-Neustart; ist ein `agentType` unbekannt, bricht das
   Skript ab statt auf einen anderen Typ auszuweichen.
2. **Linsen schlank.** Jede Linse mit eigener Leitfrage; ab Runde 2 ist eine davon die Vorrunden-Linse.
   Vorrunden-Infos als kompakte Tabelle (ID, Datei:Zeile, ein Satz, Status), keine Berichtsdateien. Große
   Gegenstände nach Dateien auf die Linsen verteilen, statt jede Linse alles lesen zu lassen; Normdokumente
   nur abschnittsweise. Fokussiert arbeiten (Richtwert ≤ 30 Turns je Linse). Vor dem Verify nichts
   zusammenführen: Findings derselben Datei und Nachbarschaft (±100 Zeilen bzw. gleicher Abschnitt) landen
   im selben Bündel, die Stimme urteilt je Finding und kennzeichnet Dubletten. Erst nach dem Urteil fasst der
   Koordinator Dubletten (gleiche Stelle, gleiche Maßnahme) für die Übergabe an den Erzeuger zusammen.
3. **Verify nur für Blocker der Linse.** Nur Findings, die eine Linse als kritisch/hoch einstuft, werden
   adversarial verifiziert. Mittel/Niedrig gehen ohne Verify an den Erzeuger; er prüft beim Einarbeiten jede
   Stelle und lehnt Unzutreffendes mit Beleg ab.
   - **Erste Stimme gebündelt:** höchstens 5 Findings je Spawn, deterministisch nach Datei bzw. Abschnitt
     (±100 Zeilen) gruppiert; mehr als 5 in einer Nachbarschaft nach Zeilennummer in Fünferblöcke teilen,
     Dubletten über Bündelgrenzen prüft der Koordinator nach dem Urteil. Eine **zweite Stimme** (einzeln) nur, wenn die erste widerlegt oder unter hoch
     herabstuft. Jede Stimme erhält nur Finding und Gegenstand, **keine** Urteile vorheriger Stimmen und
     nicht die Linsen-Severity.
   - **Keine Hochstufung:** Verifizierer bestätigen, stufen herab oder widerlegen. Liegt die Severity einer
     Stimme über der Linsen-Severity, übernimmt das Skript sie nicht, sondern meldet sie samt Begründung als
     Hinweis an den Koordinator (gemessen 09/2026: von 331 nachgeprüften Hochstufungen hielt eine).
   - **Ergebnis je Finding:** hält, solange nicht alle Stimmen widerlegen; Severity = Maximum der haltenden
     Stimmen, höchstens die Linsen-Severity. Eine ausgefallene oder ungültige Stimme zählt **nie** als
     Widerlegung: einmal wiederholen, sonst hält das Finding mit der Linsen-Severity. Fehlende, doppelte oder
     widersprüchliche IDs im Bündel gelten als ausgefallene Stimme für genau diese Findings.
4. **Verify-Prompt kompakt.** Eigener Kontextblock (Richtwert ≤ 1,5 KB) statt des Linsen-Kontexts: Repo/Rev,
   zitierte Dateien und Zeilen, nur die für das Finding relevanten Entscheidungen als Einzeiler, das Schema.
   Keine Liste aller Prüfgegenstände, keine Anweisungen zur Volllektüre, keine weitergereichte
   Nutzeranfrage. Lese-Budget: zuerst die Fundstelle ±30 Zeilen, dann höchstens 5 weitere gezielte Aufrufe;
   Volllektüre nur mit Begründung. Schema je Finding: `{id, haelt, severity, beleg (Datei:Zeile),
   begruendung (≤ 3 Sätze), dublette_von?}`, im Bündel als Liste `urteile`.
5. **Rückgabe kompakt.** Das Skript gibt nur bestätigte Findings (ID, Severity, Datei:Zeile, Titel
   ≤ 120 Zeichen, Maßnahme ≤ 2 Sätze) und Zähler je Severity (erhoben / bestätigt / widerlegt) zurück —
   keine Rohstimmen, keine Linsentexte. Beim Fixcheck je Befund zusätzlich die Kennzeichnung (Finding-ID, „ohne Auftrag“ oder „außerhalb
   der Fixes“) und die Zuordnungsliste (Änderung → Finding-ID(s) oder „ohne Auftrag“, ohne Severity).
6. **Mutationsphase** (nur Stufe L bzw. auf Wunsch; läuft zusätzlich zu den Linsen): Die Hauptsession gibt
   ein frisches, leeres Sicherungsverzeichnis und den Arbeitsbaum
   vor — committeter Gegenstand in eigenem Worktree außerhalb des Repos an kurzem Pfad; sonst vorher
   Parallel-Check auf **jede** aktive Session im selben Arbeitsbaum (mtimes aller Dateien aus `git status`,
   jüngster Commit), bei Aktivität oder im Zweifel erst nach ausdrücklicher Bestätigung des Menschen — und
   das Skript protokolliert beides per `log()`. Vor dem Start legt sie eine **Offen-Markierung** an (existiert
   schon eine: keine Phase starten, Menschen fragen): Memory `mutation-offen.md` (Session-ID, Startzeit,
   Sicherungsverzeichnis, Arbeitsbaum) mit Index-Zeile `mutation-offen (Session <id>): nicht anfassen,
   Menschen fragen`. Die Markierung sehen nur Sessions, die danach starten; laufende schützt allein der
   Parallel-Check. Den Abgleich fährt nur die anlegende Hauptsession, Subagenten nie. Findet eine andere
   Session die Markierung, fasst sie nichts im genannten Arbeitsbaum und Sicherungsverzeichnis an und fragt
   den Menschen, ob die Besitzer-Session beendet ist; erst nach seiner Bestätigung fährt sie den Abgleich.
   Markierung ohne Sicherungsverzeichnis: nur melden. Nach Ende des Workflows, auch nach Abbruch oder Fehler, prüft die **Hauptsession selbst** je
   Datei die jüngste Zeile aus `manifest.tsv` (Format siehe `mutations-pruefer`):
   - `restored`, `orig` oder `mut` mit Platte = `orig`-Hash: in Ordnung. `restored`/`orig` mit anderer
     Platte: nur melden.
   - `mut`: nur wenn Platte = `mut`-Hash, Sicherung = `orig`-Hash **und** der mit denselben Labels neu
     erzeugte Diff Sicherung → Platte per `cmp` byte-gleich zur Diff-Datei der Zeile ist, in einem
     Bash-Aufruf per `cp -p` zurückschreiben und Hash + Bytes gegen `orig` prüfen; sonst nur melden.
   - Sicherungsdateien ohne `orig`-Zeile (außer `baseline/`, `manifest.tsv`, `mut-*.diff`): melden.
   - Mutation in HEAD/Index: alle Befehle mit `git -C <arbeitsbaum>`; je mutiertem Pfad (repo-relativ per
     `git ls-files --full-name -- <abs>`; leer = untrackt, dann entfällt diese Prüfung) den Index-Blob
     (`git ls-files -s`) und für jeden Commit aus `git log --format=%H <baseline-HEAD>..HEAD -- <relpfad>`
     den Blob `<commit>:<relpfad>` gegen die `git-blob`-Werte der `mut`-Zeilen prüfen; ein Treffer oder ein
     Fehler-Returncode ist zu melden.
   Danach die Baseline-Befehle selbst wiederholen und mit `baseline/` vergleichen. Gemeldete Abweichungen
   entscheidet der Mensch; nie überschreiben. Abräumen erst, wenn alles in Ordnung bzw. zurückgeschrieben und
   die Baseline identisch ist oder jede Abweichung entschieden wurde: den eigens angelegten Worktree per
   `git worktree remove <pfad>` ohne `--force` (im Haupt-Tree-Modus entfällt das), das Sicherungsverzeichnis
   nur über den protokollierten, nicht leeren Pfad außerhalb des Repos; zuletzt die Offen-Markierung entfernen.
