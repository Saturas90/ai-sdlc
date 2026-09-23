# Review-Gate — Ablauf

Von jeder Phase verwendet. Kategorien-Definitionen: Severity-Schema der Projekt-CLAUDE.md, falls
vorhanden (hat Vorrang), sonst `konventionen.md`.

**Eingabe:** das zu prüfende Artefakt (oder der Diff eines Impl-Schritts) + Kontext
(Issue, ggf. Architektur/Impl-Plan).

1. **Review** — passenden Reviewer wählen und spawnen. Liefert Findings, je mit
   `Kategorie | Fundstelle | Problem | Vorschlag` + „Blockierend: ja/nein“.
   - **Standard** (Issue, Projektplan, Impl-Plan, normale Impl-Schritte) → `reviewer` (sonnet).
   - **Kritisch** (`[K]`-Schritt, sicherheits-/datenkritischer Code) → `reviewer-kritisch` (opus, effort high).
   - **Architekturplan** → `reviewer-architektur` (opus, effort xhigh = Effort des `architekt`).
   - Reviewer ist immer ≥ dem erzeugenden Agenten (Modell **und** Effort). Nie schwächer reviewen als produziert wurde.
2. **Bewerten:**
   - ≥1 **kritisch/hoch** offen → nur diese Findings an den erzeugenden Agenten
     (issue-autor / architekt / impl-planer / implementierer) zur **gezielten** Überarbeitung
     zurückgeben, dann zurück zu Schritt 1. Das Artefakt **nicht** komplett neu erzeugen.
   - Nur noch **mittel/niedrig** → Gate erfüllt.
3. **Menschliche Freigabe** (nur Planungsartefakte): offene mittel/niedrig-Findings kurz
   auflisten, dann um explizite Freigabe bitten. Erst nach „freigegeben“ weiter.
4. **Impl-Schritt-Reviews:** kein Human-Gate pro Schritt. Nach erfülltem Gate abhaken + committen
   (an `mechaniker` (haiku) delegieren).

**Kosten:** Der Reviewer ist ein eigenständiges „zweites Augenpaar“ — Standard Sonnet, riskante
Fälle Opus. Überarbeitungsrunden nur mit den offenen kritisch/hoch-Findings anstoßen, nicht das
ganze Artefakt neu erzeugen.

## Workflow-Muster (Review/Verify in Workflow-Skripten)

Gilt für jedes Workflow-Skript mit Review-, Verify- oder Widerlegen-Stufen. Spart Spawns, ohne das
Kaltreview-Prinzip (jede Runde verifiziert die Vorrunde **und** scannt vollständig neu) anzutasten.

1. **`agentType` ist Pflicht.** Kein `agent()` ohne `agentType` — sonst erbt der Spawn Hauptmodell,
   Effort (xhigh) und den vollen Tool-Satz (gemessen 09/2026: ~50K statt ~26K Tokens Start-Prompt).

   | Rolle | `agentType` |
   |---|---|
   | Breiter Review, Kaltreview-Linse, Verify/Widerlegen einzelner Findings (auch Niedrig-Bündel) | `reviewer-kritisch`; Nicht-[K]-Artefakte von Sonnet-Erzeugern auch `reviewer` |
   | **Gegenstand Architekturplan** — alle Linsen und Verify-Stimmen (Vorrang vor der Zeile darüber) | `reviewer-architektur` |
   | Mutation (Testwirksamkeit) — immer allein in eigener serieller Phase, nie parallel zu lesenden Linsen | `mutations-pruefer` |
   | Überarbeiten, Fixen | der erzeugende Agent (`issue-autor`, `architekt`, `impl-planer`, `implementierer`) |
   | Erheben, Recherche in Repo **oder Web** (WebFetch/WebSearch) | `Explore` mit explizitem `effort` (z. B. `'high'`); Fragen zu Claude Code: `claude-code-guide` |
   | Abhaken, Committen | `mechaniker` |

   Enthält der Gegenstand `architecture.md` oder ein ADR, laufen alle Linsen und Stimmen dazu über
   `reviewer-architektur`, auch bei gemischtem Gegenstand. `Explore` hat alle Tools außer Edit/Write/Agent (laut Agent-Liste), also auch WebFetch/WebSearch.
   Passt keine Rolle: `model` **und** `effort` explizit setzen und per `log()` begründen. Skripte leiten
   „Blockierend" aus den Severities ab. Neue oder geänderte Agenten wirken erst nach einem Session-Neustart;
   ist ein `agentType` unbekannt, bricht das Skript ab statt auf einen anderen Typ auszuweichen.

   **Mutationsphase:** Die Hauptsession gibt ein frisches, leeres Sicherungsverzeichnis und den Arbeitsbaum
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
2. **Nur Niedrig-Findings gebündelt prüfen.** Kritisch-, Hoch- und Mittel-Findings werden einzeln
   adversarial verifiziert. Niedrig-Findings gehen gebündelt an einen Verifizierer: höchstens 8 je Spawn,
   deterministisch im Skript (kein Agent) gruppiert nach Datei und 10-Zeilen-Fenster (Evidence ohne
   Zeilennummer: nach Datei bzw. Dokument). Schema je Finding: hält/widerlegt + eigene Severity. Die
   Finder-Severity dient nur dem Filtern im Skript und wird nicht mitgegeben. Stuft der Bündel-Verifizierer
   ein Finding auf ≥ Mittel hoch, läuft es danach einzeln durch die adversariale Verifikation (Muster 3).
   Nichts verwerfen; keine Vorrunden-Ergebnisse als Status mitgeben (Kaltreview).
3. **Stimmen nacheinander, Abbruch sobald das Ergebnis feststeht.** Mehrere Stimmen zu **einem** Finding
   laufen sequenziell (verschiedene Findings weiter parallel). Jede Stimme erhält nur Finding und
   Gegenstand, **keine** Urteile vorheriger Stimmen. Severity = Maximum der haltenden Stimmen. Abbrechen,
   sobald weitere Stimmen das Gate-Ergebnis nicht mehr ändern können — bei „hält, solange nicht alle
   Stimmen widerlegen" also, sobald eine Stimme das Finding **als kritisch/hoch** hält (Severity dann als
   „≥ hoch, Frühabbruch" ausweisen); hält eine Stimme nur mit Herabstufung, wird weiter abgefragt. Andere
   Aggregationen (Mehrheit, Median) brauchen eine eigene, ebenso fail-closed formulierte Abbruchbedingung.
   Eine ausgefallene oder ungültige Stimme (auch im Bündel, Muster 2) zählt **nie** als Widerlegung:
   einmal wiederholen, sonst hält das Finding mit der Severity des Finders.
4. **Linsen-Deckel erst ab Runde 5.** Ab der 5. Review-Runde derselben Prüfeinheit höchstens zwei Linsen:
   (A) Vorrunden-Findings verifizieren und Fixes auf Regressionen prüfen, (B) vollständiger Re-Scan aller
   Dateien und Nachbar-Bauteile mit den Leitfragen aller bisherigen Linsen als Checkliste, einschließlich
   Gegenprüfung zitierter Fakten gegen Code bzw. Quelle. Den vollen Linsensatz fährt die nächste Runde
   wieder, wenn eine Runde ≥ 1 kritisch oder ≥ 2 hoch bestätigt **oder** seit der Vorrunde neue
   Akzeptanzkriterien, Dateien oder normative Klauseln hinzukamen. Eine Mutationsphase läuft zusätzlich zu
   A/B und zählt nicht zum Deckel.
