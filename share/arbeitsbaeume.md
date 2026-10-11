# Arbeitsbäume — parallele Sessions (opt-in)

Gilt nur, wenn die Projekt-CLAUDE.md einen Abschnitt `## Arbeitsbäume (ai-sdlc)` enthält
(Arbeitsbaum-Modus); sonst arbeiten alle Sessions wie bisher im Hauptcheckout (`konventionen.md`). Der
Abschnitt sagt mindestens: „Implementierung läuft im Issue-Worktree. Für Arbeiten an einem Issue mit Worktree
(Umsetzung, Neufreigabe des Plans, Konfliktauflösung, Gate-Fixes) `EnterWorktree(path)`; vor Integration,
Übergabe und Arbeiten im Hauptcheckout `ExitWorktree(action: keep)`. Fragt Claude Code beim Beenden der
Session im Worktree ‚keep or remove‘, immer keep wählen (entfernen nur per `wt finish`). Regeln:
`~/.claude/ai-sdlc/arbeitsbaeume.md`; im Hauptcheckout nur per `wt commit` committen.“ Damit sind beide
Tools durch eine Projektanweisung gedeckt. Projektwerte stehen in `.ai-sdlc/arbeitsbaeume.json` im
Hauptcheckout (Abschnitt 7). Die Mechanik erledigt `wt` =
`pwsh -NoProfile -File "$HOME/.claude/ai-sdlc/tools/wt.ps1" <befehl> …` (Abschnitt 6), nie das Programm `wt`
(Windows Terminal); ein Ergebnis zählt nur mit der Schlusszeile `WT: …`. Codex: eigene Regel in
`codex/arbeitsbaeume.md` (installiert nach `~/.codex/ai-sdlc/`), gleiches Skript.

## 1. Wer arbeitet wo

| Tätigkeit | Ort | Commit |
|---|---|---|
| Projektplan, Issue, Architektur, Impl-Plan, Abschluss, Registrierungen | Hauptcheckout (Hauptbranch, Standard `main`); Ausnahme Issue-Ordner: Abschnitt 5 | `wt commit` |
| Bugfix der Prüftiefe S (`review-gate.md` Abschnitt 1: kein `[K]`, nichts Sicherheits- oder Datenkritisches, keine Migration) | Hauptcheckout, wenn dort keine andere Session Code ändert | `wt commit -Gate` |
| Implementierung, Bugfix M/L | Issue-Worktree `<worktreeRoot>/<key>` (Standard `.claude/worktrees/issue-0256`), Branch `<key>-<slug>` | je Einheit auf dem Branch, dann `wt integrate` |

- Ein Worktree je Issue, eine Session je Worktree. Code ändert sich nur in Issue-Worktrees, außer beim
  S-Bugfix; vor dessen Start zeigt `git status --porcelain` im Hauptcheckout keine fremden Code-Pfade.
- Im Hauptcheckout nie den Branch wechseln (`checkout`/`switch`), kein `stash`, `reset`, kein `restore`
  fremder Pfade, kein `git add -A`/`commit -a`. Commits dort nur über `wt commit` (Sperre, explizite
  Dateiliste).
- Commits und Abhaken über `mechaniker`; selbst führt die Hauptsession nur `git rebase <hauptbranch>`,
  `rebase --continue`, `rebase --abort` und `git commit --amend` (Abschnitt 3, samt dem nötigen `git add`),
  `wt integrate` und `wt commit -Gate` aus.
- Überall verboten: `rebase --skip`, `--force`, `branch -D`, `branch -f`, `worktree add -B`, `update-ref`
  auf den Hauptbranch, `push --force`, `git merge` in Issue-Branches (`wt integrate` verweigert Branches mit
  Merge-Commits). Git schlägt in Fehlermeldungen genau solche Varianten vor — stattdessen melden.

## 2. Ablauf einer Implementierungseinheit

Claude Code (neuer Tab im Projektfenster, per „Claude Code: Rename Session Tab“ nach Issue und Schritt
benennen):
1. `wt start -Key <KEY> -Slug <slug>` (Slug nur beim Anlegen): legt den Worktree vom lokalen Hauptbranch an,
   verwendet den vorhandenen wieder oder hängt einen vorhandenen Branch an und bringt ihn auf den aktuellen
   Stand (wie `sync`); kopiert fehlende gitignorierte Pflichtdateien laut `.worktreeinclude` (überschreibt
   nichts) und fährt beim Anlegen den Setup-Befehl. Es verweigert (12), solange der Issue-Ordner im
   Hauptcheckout uncommittete Änderungen hat (Abschnitt 5). Exitcode ≠ 0 → Abschnitt 3.
2. `EnterWorktree(path: <Pfad aus der Zeile WORKTREE= von wt start>)`. Ab hier laufen Session und
   Sub-Agenten im Worktree; Sub-Agenten bekommen relative Pfade, nie Pfade des Hauptcheckouts.
3. Umsetzung und Review-Gate wie in `implementieren`; vorher nur gezielte Tests und die schnellen Gates
   (Abschnitt 4), nicht die volle Kette.
4. Stand in `kontext.md`, Abhaken und Commit auf dem Branch über `mechaniker` (`wt commit`).
5. `ExitWorktree(action: "keep")`; dann startet die Hauptsession selbst `wt integrate -Key <KEY>` im
   Hintergrund (`run_in_background`; nicht über `mechaniker` oder Monitor, deren Laufzeitgrenzen sind zu
   kurz). Integrationen laufen nacheinander; das Skript wartet auf die Sperre.
6. Ergebnis nach Exitcode (Abschnitte 3 und 6); danach endet die Session.

**Fortsetzung einer unterbrochenen Einheit:** Hat der Worktree uncommittete Einheitsarbeit und bestätigt der
Mensch, dass dort keine Session läuft (Abschnitt 8), ohne `wt start`/`wt sync` direkt
`EnterWorktree(path: <Pfad aus wt status>)` und laut „Stand“ fortsetzen; `start`/`sync` nur bei sauberem
Worktree. Vor einer geplanten Übergabe mitten im Gate „Stand“ schreiben (`review-gate.md` 2.4), dann
`ExitWorktree(keep)`.

Eigenes Fenster: `wt start` aus dem Hauptcheckout bzw. dessen Projektfenster, danach ein Fenster mit dem
Worktree-Ordner als Projekt; dort dieselben Schritte ohne Enter-/ExitWorktree, `wt integrate` direkt aus dem
Worktree. Registrierungen und `nurAufMain`-Dateien (Abschnitt 5): Datei im Hauptcheckout bearbeiten,
`wt commit -Repo <Hauptcheckout> …`.

Nach der letzten Einheit: `/abschluss` im Hauptcheckout, danach `wt finish -Key <KEY>` (Abschnitt 8).

**Integration am Ende (je Issue wählbar):** Trägt der freigegebene Impl-Plan `**Integration:** am Ende (<Grund>)`
statt des Standards `je Einheit` — nur, wenn Zwischenstände nicht auf main dürfen oder die Einheiten sehr
klein sind; Preis: höheres Konfliktrisiko, Fehler der vollen Kette zeigen sich erst am Ende —, entfallen
Schritt 5 und jede Vorab-Integration, solange Schritte offen sind. Jede Einheit wird reviewt und auf dem
Branch committet, jede weitere beginnt mit `wt start` bzw. `wt sync`; das rebased die bisherigen Commits auf
den aktuellen Hauptbranch, Konflikte zeigen sich so früh und klein: Auflösung und Review wie Fall 10, danach
ohne `wt integrate` mit der Einheit weiter (Pfad aus `WORKTREE=` bzw. `wt status`). Nach der letzten Einheit
einmal `wt integrate` (eine volle Gate-Kette für alle Einheiten), dann `/abschluss`. Trägt der Branch mehrere
Commits, kommen Korrekturen aus einem Konflikt-Review als eigener Commit `<KEY>: Konfliktkorrektur` und ein
Fix nach rotem Gate als eigener Commit `<KEY>: Gate-Fix` über `mechaniker` (`wt commit`) dazu; weitere rote
Läufe amendet die Hauptsession in genau diesen Gate-Fix-Commit (sonst wie Fall 10 bzw. 11). Reviewer-Typ für
Konflikt-Review und Fixcheck ist dann der stärkste der betroffenen Einheiten.

## 3. Konflikt, rotes Gate, Blockade

- **10 Konflikt** (aus `wt integrate`, `wt start` oder `wt sync`): Das Skript hat den Rebase abgebrochen; der
  Branch ist unverändert, ausgegeben werden die Konfliktdateien sowie `ALTE_BASIS` und `ALTER_TIP`. Im
  Worktree (`EnterWorktree(path)`, Pfad aus `WORKTREE=` bzw. `wt status`) `git rebase <hauptbranch>`;
  Code-Konflikte löst ein frischer `implementierer` mit Konfliktliste und `kontext.md`, reine
  Text-Konflikte die Session; `git add` und `rebase --continue` führt die Session aus. Danach Review der
  Auflösung (`review-gate.md` Abschnitt 6); Korrekturen daraus committet die Hauptsession per
  `git commit --amend --no-edit -- <Dateien>` (mehrere Commits auf dem Branch: eigener Commit, Abschnitt 2).
  Dann `ExitWorktree(keep)` und erneut `wt integrate` – bei einem Konflikt aus `start`/`sync` stattdessen mit
  der Einheit weiter. Hält ein Rebase ohne offene Konfliktdatei an (rerere hat eine frühere Auflösung
  eingespielt), gilt das ebenfalls als Konflikt. Einen Rebase nie offen lassen; findet eine Session einen
  offenen vor (`wt status`), liest sie zuerst den Stand und fragt vor `rebase --abort` den Menschen.
- **11 Gate rot:** Der Branch kann schon rebased sein (Ausgabe „Branch wurde rebased“ mit `ALTE_BASIS` und
  `ALTER_TIP`). Ist das Gate auch auf dem Hauptbranch rot (fremde Ursache): nicht im Einheits-Commit
  reparieren, sondern dem Menschen melden. Sonst `EnterWorktree(path)`, neue Sicherung vom aktuellen HEAD
  (`review-gate.md` 2.5), die Gate-Fehler als Findings `G1`, `G2`, … ins Fix-Protokoll; Fix durch einen
  frischen Autor, gezielte Tests und schnelle Gates, Fixcheck nach `review-gate.md` Abschnitt 3 mit dem
  Reviewer-Typ der Einheit (führt er zur Rücknahme eines Fixes, bleibt das Gate rot: Mensch). Dann
  `git commit --amend --no-edit -- <Fix-Dateien, ggf. kontext.md>` durch die Hauptsession (neue Dateien
  vorher `git add -N`; die Einheit bleibt ein Commit; mehrere Commits auf dem Branch: Gate-Fix-Commit und
  Reviewer-Typ nach Abschnitt 2), `ExitWorktree(keep)` und erneut `wt integrate`.
- **12 blockiert:** Die Meldung nennt den Grund, z. B. Datei aus `nurAufMain` im Branch, doppelte Nummer (im
  Branch umnummerieren), Merge-Commit im Branch, Worktree während der Wartezeit verändert, „would be
  overwritten“ durch uncommittete Arbeit im Hauptcheckout, Konfiguration uncommittet geändert, noch laufender
  Gate-Prozess eines abgebrochenen Laufs, Sperre zu lange belegt, nach `git mv` nur der neue Pfad genannt,
  Hook hat Dateien verändert (Abschnitt 4). Ursache beheben oder dem Menschen melden; keine
  Wiederholschleife. Hat das Gate Dateien verändert (Formatter, Abschnitt 4): im Worktree den
  Formatierungsdiff prüfen, wie bei 11 übernehmen und erneut integrieren.
- **13 Teilzustand:** Der ff-Merge ist gescheitert, nachdem sich HEAD oder vom ff betroffene Pfade des
  Hauptcheckouts verändert hatten (die Meldung nennt die Pfade), oder `finish` konnte den Worktree-Ordner
  nach der Belegungsprobe nicht zurückbenennen (die Meldung nennt den Ordner `<dir>.wt-probe-<pid>`), oder
  `wt commit -Gate` hat committet, die Indexeinträge der genannten Pfade aber nicht angeglichen (die Meldung
  nennt den `git reset`-Befehl). Sofort stoppen, im Hauptcheckout nichts committen, Mensch (den Probe-Ordner
  zurückbenennen, nie `git worktree prune`).
- **14 nichts zu tun:** per `wt status` prüfen, ob das erwartet ist (z. B. schon integriert), sonst melden.
  **1 Fehler:** melden; bei Bindungsfehlern von PowerShell kann die `WT:`-Zeile fehlen.
- Sachkonflikte (zwei unvereinbare Absichten) gehen immer an den Menschen, mit beiden Seiten und einem
  Vorschlag.

## 4. Gate-Regel

- Die volle Gate-Kette läuft genau einmal je Integration, im Worktree auf dem rebasten Stand, gestartet von
  `wt integrate`; der Nachweis gilt für den Tree-Hash. Sie läuft im lebenden Worktree: Während des Gates
  arbeitet dort niemand — Dateien, die nur während des Laufs existieren, erkennt `wt` nicht (es prüft die
  Sauberkeit vor und nach dem Gate). Vorher (Implementierer, Fixes nach Review) laufen nur gezielte Tests und
  die schnellen Gates: Projektwert `schnelleGates`, sonst die schnellen Gates des Impl-Plans (`kontext.md` ›
  Tests & Prüfbefehle);
  `implementieren` gibt den Befehl dem `implementierer` mit.
- Den Formatter wenden die schnellen Gates vor dem Commit an; die Integrations-Kette `gate` prüft nur, und
  Git-Hooks dürfen keine Dateien umschreiben. Verändert die Kette dennoch Dateien, endet `wt integrate` mit
  12 (Abschnitt 3); verändert ein Hook genannte Dateien, endet `wt commit` mit 12 „Commit <hash> angelegt,
  Hook hat Dateien verändert: …“ — der Commit steht schon (Indexeinträge dieser Pfade auf HEAD): nicht
  wiederholen, Mensch.
- Ein Neulauf entfällt nur, wenn sich seit dem gegateten Tree ausschließlich Pfade aus `gateIrrelevant`
  geändert haben (Standard leer, also immer Neulauf). Die Liste führt das Projekt, belegt per Grep über
  Tests und Gate-Skripte.
- Integriert wird genau der gegatete Commit, per `merge --ff-only --no-overwrite-ignore` unter der
  Hauptcheckout-Sperre. Vorher prüft das Skript: Hauptcheckout auf dem Hauptbranch, Worktree sauber und kein
  offener Rebase (nach Erhalt der Integrationssperre und vor dem Gate erneut), keine Merge-Commits im Branch,
  keine Datei aus `nurAufMain` im Branch, keine neue doppelte Nummer laut `nummernPruefung`.
- `wt commit -Gate` (S-Bugfix) fährt die Kette in einem temporären Worktree auf HEAD plus den genannten
  Dateien, damit uncommittete Arbeit anderer Sessions das Ergebnis nicht verfälscht, und committet genau die
  gegateten Inhalte, ohne Git-Hooks; weicht eine genannte Datei im Hauptcheckout inzwischen ab, meldet es das,
  die spätere Änderung bleibt uncommittet. Wie `wt integrate` startet ihn die Hauptsession selbst im
  Hintergrund, nicht `mechaniker`.
- Planungs-, Doku- und Abschluss-Commits fahren vor dem Commit statt der Kette die Tests und Gate-Schritte, die
  die Dateien lesen (`konventionen.md` › Tests & Gates).

## 5. Konfliktvermeidung

- **Nur auf main:** Dateien aus `nurAufMain` (Standard `projektplan.md`; z. B. Teilpläne, Statusarchiv; die
  Konfigurationsdatei immer, Abschnitt 7) nie im Branch. Vor jeder Änderung `git diff --quiet -- <datei>`
  im Hauptcheckout; zeigt es fremde Änderungen, anhalten und den Menschen fragen. Dann bearbeiten und sofort
  per `wt commit` festschreiben. Der Projektplan entsteht deshalb als `projektplan.entwurf.md` im
  Hauptcheckout (Entwurf und Review; erste Zeile `Basis: <rev>` = HEAD beim Anlegen; ein vorhandener Entwurf
  ist uncommittet, also Aktivität: vor dem Fortsetzen fragen wie in Abschnitt 8). Nach der Freigabe
  die seit der Basis committeten Änderungen (`git diff <rev> HEAD -- projektplan.md`) in den Entwurf
  einspielen, ihn ohne die Basis-Zeile in einem Zug nach `projektplan.md` übernehmen, sofort festschreiben und
  die Entwurfsdatei löschen. Kein Schrittfortschritt im Projektplan; den tragen die Plan-Häkchen.
- **Neue Nummern:** Issue-Nummern vor der ersten Verwendung per Reservierungs-Commit auf main
  (`<KEY>-<NNN>: registriert`, nur die neue Projektplan-Zeile), auch mitten in einer Einheit:
  `ExitWorktree(keep)`, im Hauptcheckout eintragen, `wt commit`, `EnterWorktree(path)` (eigenes Fenster:
  Abschnitt 2). ADR- und Migrationsnummern ohne Reservierung im Branch vergeben (Planung: im Hauptcheckout);
  Dubletten mit einem neuen Namen (im Branch hinzugefügt oder umbenannt bzw. noch nicht in HEAD) erkennt
  `nummernPruefung` bei `wt integrate` und bei `wt commit` im Hauptcheckout (12) → umnummerieren, im Branch
  bzw. vor dem Commit; schon auf dem Hauptbranch vorhandene Dubletten meldet es nur als WARNUNG.
- **Issue-Ordner:** Solange ein Issue einen Worktree mit nicht integrierten Commits hat oder dort gearbeitet
  wird, schreibt nur dessen Branch den Issue-Ordner — auch eine Neufreigabe des Plans entsteht im Worktree.
  Nach der letzten Integration schreibt der Abschluss im Hauptcheckout (`zusammenfassung.md`,
  Projektplan-Status). Bedarf anderer Sessions geht über den Menschen. `wt start` und `wt sync` verweigern
  bei uncommittetem Issue-Ordner im Hauptcheckout (12).
- **Frischer Stand:** Jede Einheit beginnt mit `wt start` bzw. `wt sync`, außer bei der Fortsetzung
  (Abschnitt 2).
- **Git, einmalig im Repo:** `git config rerere.enabled true` und `git config merge.conflictStyle zdiff3`.
  Kein `merge=union` (erzeugt bei Tabellen stille Doppelzeilen).

## 6. `wt.ps1`

| Befehl | Wirkung |
|---|---|
| `start -Key K [-Slug s]` | Worktree anlegen, wiederverwenden oder an vorhandenen Branch hängen, `WORKTREE=` und `BRANCH=` ausgeben, dann `sync` (Konflikt → Rebase abgebrochen, 10); fehlende Pflichtdateien nachkopieren, Setup beim Anlegen, Gate-Ablage anlegen; verweigert bei uncommittetem Issue-Ordner im Hauptcheckout (12) |
| `sync [-Key K]` | Branch ohne eigene Commits per ff, sonst per Rebase auf den Hauptbranch (Konflikt → 10); verweigert wie `start` bei uncommittetem Issue-Ordner im Hauptcheckout (12) |
| `integrate [-Key K]` | Sperre → Konfiguration neu aus HEAD → Sauberkeit erneut → Rebase → Prüfungen → Gate (einmal je Tree) → ff → Sperre frei; bei 10 und nach einem Rebase auch bei 11 `ALTE_BASIS=`/`ALTER_TIP=` |
| `commit -Nachricht m [-Gate] <dateien…>` | Pfadlisten-Commit (neue Dateien per `add -N`; bekannt ist ein Pfad aus Index oder HEAD, also auch nach `git rm`/`git mv` — dann alten und neuen Pfad nennen, sonst 12; Ergebnis geprüft); im Worktree keine `nurAufMain`-Dateien (12); im Hauptcheckout unter Sperre und mit `nummernPruefung`; `-Gate` nur im Hauptcheckout (Abschnitt 4) |
| `finish -Key K` | nur aus dem Hauptcheckout und wenn integriert (Abschnitt 8): Gate-Ablage nach `<gateAblage>/_worktrees/<key>/` im Hauptcheckout (ohne Überschreiben), abweichende `.claude/settings.local.json` dorthin sichern, Junctions/Symlinks als Links entfernen, Worktree entfernen, Branch löschen |
| `status` | Worktrees mit vollem Pfad, Branches, Vorsprung/Rückstand, `integriert` (Branch vollständig im Hauptbranch), offene Rebases, letzte Änderung, Sperren, Branches ohne Worktree (nicht integriert bzw. „integriert, ohne Worktree“), nicht registrierte Ordner unter `worktreeRoot` als „Rest (nicht registriert)“ |

Ohne `-Key` gilt der Key des aktuellen Worktrees; `-Repo <pfad>` setzt das Startverzeichnis (Standard: das
aktuelle). Exitcodes: 0 ok · 1 Aufruf- oder unerwarteter Fehler · 10 Konflikt · 11 Gate rot · 12 blockiert ·
13 Teilzustand · 14 nichts zu tun. Die letzte Ausgabezeile lautet `WT: <STATUS> …`; fehlt sie (Bindungsfehler
von PowerShell, Exit 1), ist das Ergebnis nicht zu werten.

## 7. Projektwerte (`.ai-sdlc/arbeitsbaeume.json`)

```json
{
  "hauptbranch": "main",
  "worktreeRoot": ".claude/worktrees",
  "issueOrdner": ["issues"],
  "setup": "",
  "gate": "pwsh -NoProfile -File scripts/gates.ps1",
  "schnelleGates": "",
  "gateAblage": ".gate-logs",
  "nurAufMain": ["projektplan.md"],
  "nurAufMainAusnahmen": [],
  "gateIrrelevant": [],
  "nummernPruefung": [{ "ordner": "docs/adr", "muster": "^ADR-(\\d{4})-" }],
  "integrationsVersuche": 3,
  "sperreWartenMinuten": 240
}
```

`wt` liest die Datei aus HEAD des Hauptcheckouts; sie gehört committet und zählt immer zu `nurAufMain`
(`integrate` und `wt commit` im Worktree verweigern Änderungen daran, 12). Weicht die Arbeitskopie ab, enden
die ändernden Befehle mit 12 („Konfiguration uncommittet geändert“), `status` warnt nur. `wt commit` der
Datei selbst im Hauptcheckout bleibt erlaubt: Es prüft die Arbeitskopie vollständig; ein geänderter
`hauptbranch` muss der aktuelle Branch des Hauptcheckouts sein (sonst 12). Ist die Datei in HEAD ungültig,
enden alle Befehle mit 1 außer `status` (Standardwerte, WARNUNG) und `wt commit` der Datei im Hauptcheckout
(Reparatur). Fehlt sie in HEAD, gilt die Arbeitskopie mit Warnung. Eine wartende Integration liest sie nach
Erhalt der Sperre neu. Pfade relativ zur Repo-Wurzel; ein Eintrag mit `/` am Ende meint den Ordner samt
Inhalt; Platzhalter (`*`, `?`, `[`) sind in `nurAufMain`, `nurAufMainAusnahmen` und `gateIrrelevant` nicht
erlaubt, und jedes `muster` braucht mindestens eine Fanggruppe (sonst 1). Fehlt `gate`, verweigert
`integrate` (12); `""` heißt bewusst „keine Gate-Kette“. `gate` ist eine PowerShell-Befehlszeile, Ketten mit `&&` oder `;`; jeder
scheiternde Schritt macht das Gate rot. Sie startet keinen Hintergrundprozess, der sie überdauert: `wt`
wartet auf das Prozessende, und ein noch laufender Gate-Prozess blockiert den nächsten Lauf (12).
`schnelleGates` nutzt nur die Session (Abschnitt 4). `gateAblage` ist der Ordner der Gate-Ablage
(`review-gate.md` 2.5) und der Gate-Logs, ohne in HEAD versionierte Dateien (sonst 1); `wt start` legt ihn im
Worktree an und ergänzt ihn in `info/exclude`, wenn er im Hauptcheckout oder im Worktree nicht ignoriert ist;
die Sauberkeitsprüfungen von `sync`, `integrate` und `finish` nehmen ihn aus. Gitignorierte Pflichtdateien für
neue Worktrees stehen in `.worktreeinclude` (eine Datei je Zeile, `#` leitet Kommentare ein); `wt start`
kopiert nur ignorierte Dateien und überschreibt nichts. `worktreeRoot` muss im Hauptcheckout ignoriert sein,
möglichst in der versionierten `.gitignore` (Build-Werkzeuge lesen `info/exclude` nicht); fehlt der Eintrag,
ergänzt ihn `wt start` in `info/exclude` und warnt. Er darf weder selbst noch in einer Pfadkomponente
unterhalb der Repo-Wurzel eine Junction oder ein Symlink sein (sonst 1).

## 8. Zustand, Orchestrator, Abschluss

- `wt status` ist die Zustandsquelle für Worktrees; der dort genannte Pfad dient `EnterWorktree`, wenn kein
  `wt start` vorausgeht. Hat ein Issue einen Worktree, liegen Stand, Häkchen und Gate-Ablage dort (aus dem
  Hauptcheckout lesbar).
- Aktivität: uncommittete Dateien im Worktree oder Änderungen der letzten 30 Minuten, bei einem Issue in
  Planung dasselbe im Issue-Ordner des Hauptcheckouts. Dann vor dem Einstieg den Menschen fragen, ob dort
  eine Session läuft (Fortsetzung: Abschnitt 2).
- Ein Branch mit nicht integrierten Commits wird zuerst integriert — bei `**Integration:** am Ende` nicht,
  solange Schritte offen sind, sondern nach dem letzten `[x]` (Schlussintegration, dann `/abschluss`);
  `wt integrate` gatet selbst, wenn kein Nachweis vorliegt.
- Der Abschluss läuft im Hauptcheckout, wenn `wt status` den Branch als integriert zeigt (Worktree-Zeile mit
  `integriert` bzw. „Branch integriert, ohne Worktree“); danach `wt finish -Key <KEY>` nur aus dem
  Hauptcheckout, nachdem Fenster, Prozesse und aus dem Worktree gestartete Programme beendet sind. `finish`
  verweigert (12), bevor etwas gelöscht ist, wenn der Hauptcheckout nicht auf dem Hauptbranch steht, es im
  Worktree aufgerufen wird, der Ordner belegt ist oder ein Programm aus dem Worktree läuft (Meldung mit PID
  und Pfad); einen Worktree mit Submodulen entfernt es nur, wenn diese sauber sind. Junctions und Symlinks im
  Worktree entfernen `finish` und der Abbau temporärer Gate-Worktrees als Links, nie ihre Ziele, und nennen
  sie mit Ziel (scheitert das: 12 mit Liste, nichts weiter gelöscht). Meldet git beim Entfernen geänderte oder
  ungetrackte Dateien: 12 mit deren Liste. `finish` nennt die übrigen ignorierten Einträge, die mit dem
  Worktree gelöscht werden. Einen leeren, nicht registrierten Ordner eines früheren Versuchs räumt ein
  erneuter Aufruf ab, wenn der Branch integriert ist; zu `<dir>.wt-probe-<pid>` (Fall 13) raten `finish`,
  `start` und `status` zum Zurückbenennen. Verwaiste `_gate-*`-Ordner entfernt der nächste `wt commit -Gate`,
  soweit möglich; andere Reste (`wt status`: „Rest entfernen, Mensch“) → Mensch.
