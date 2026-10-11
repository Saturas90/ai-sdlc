# Arbeitsbäume — Codex-Regel (opt-in)

Ergänzt `~/.codex/AGENTS.md`; Quelle im Toolkit: `codex/arbeitsbaeume.md`, gleiche Mechanik wie die
Claude-Regel (`share/arbeitsbaeume.md`).

Nur wenn die Projekt-CLAUDE.md einen Abschnitt `## Arbeitsbäume (ai-sdlc)` enthält
(Arbeitsbaum-Modus); sonst gilt `AGENTS.md` allein. Dort genannte `EnterWorktree`/`ExitWorktree` betreffen nur
Claude Code. Werkzeug `wt` = `pwsh -NoProfile -File "$HOME/.codex/ai-sdlc/tools/wt.ps1" <befehl> …`, nie das
Programm `wt` (Windows Terminal). Exitcodes: 0 ok · 1 Aufruf- oder unerwarteter Fehler · 10 Konflikt ·
11 Gate rot · 12 blockiert · 13 Teilzustand · 14 nichts zu tun. Ein Ergebnis zählt nur mit der letzten
Ausgabezeile `WT: <STATUS> …`; fehlt sie, melden.

Projektwerte stehen in `.ai-sdlc/arbeitsbaeume.json`; `wt` liest sie aus HEAD des Hauptcheckouts, Änderungen
daran also im Hauptcheckout per `wt commit` festschreiben (es prüft die Arbeitskopie vollständig, ungültig: 1;
ein geänderter `hauptbranch` muss dem aktuellen Branch des Hauptcheckouts entsprechen, sonst 12). Abweichende
Arbeitskopie: ändernde Befehle 12 „Konfiguration uncommittet geändert“, `status` nur WARNUNG; noch nicht
versioniert: Arbeitskopie mit WARNUNG. Ist die Fassung in HEAD ungültig, laufen nur `status` (Standardwerte,
WARNUNG) und als Reparatur `wt commit` genau dieser Datei im Hauptcheckout; alles andere endet mit 1. Wartende
Integrationen lesen die Werte nach Erhalt der Sperre neu. U. a. `hauptbranch` (Standard `main`), `worktreeRoot`
(Standard `.claude/worktrees`, im Hauptcheckout ignoriert, möglichst per versionierter `.gitignore`; unterhalb
der Repo-Wurzel ohne Junction oder Symlink im Pfad, sonst 1), `gate` (volle Kette; fehlt es, verweigert
`integrate`; `""` = bewusst keine), `schnelleGates` (für Umsetzung und Fixes), `nurAufMain` (Standard
`projektplan.md`; die Konfigurationsdatei gehört immer dazu), `gateIrrelevant` (Standard leer),
`nummernPruefung` (jedes `muster` mit mindestens einer Fanggruppe), `gateAblage` (Ordner der Gate-Ablage,
Standard `.gate-logs`, ohne in HEAD versionierte Dateien, sonst 1; `wt start` legt ihn an und ergänzt
`/<gateAblage>/` in `info/exclude`, wenn er im Hauptcheckout oder Worktree nicht ignoriert ist; alle
Sauberkeitsprüfungen nehmen ihn aus) und `sperreWartenMinuten` (Standard 240). Einträge in `nurAufMain`,
`nurAufMainAusnahmen` und `gateIrrelevant` enthalten kein `*`, `?` oder `[` (sonst 1). `gate` ist eine
PowerShell-Befehlszeile (Ketten mit `&&` oder `;`): Jeder scheiternde Schritt macht sie rot, und sie
hinterlässt keinen Hintergrundprozess ohne Ende. Gitignorierte Pflichtdateien neuer Worktrees stehen in
`.worktreeinclude`.

Befehle: `start -Key K [-Slug s]` legt Worktree `<worktreeRoot>/<key>` mit Branch `<key>-<slug>` vom lokalen
Hauptbranch an, hängt einen vorhandenen Branch an oder verwendet den vorhandenen Worktree wieder, jeweils mit
`sync` (Konflikt → 10); es kopiert fehlende Pflichtdateien nach (überschreibt nichts), fährt Setup nur beim
Anlegen und gibt `WORKTREE=<pfad>` vor dem `sync` aus, also auch bei 10. `sync [-Key K]`: ff bzw. Rebase auf
den Hauptbranch. Beide verweigern (12) bei uncommitteten Änderungen im Issue-Ordner des Hauptcheckouts.
`integrate [-Key K]`: siehe „Gate“. `commit -Nachricht m [-Gate] <dateien…>`: Pfadlisten-Commit im aktuellen
bzw. per `-Repo <pfad>` gewählten Checkout; ein Pfad ist bekannt, wenn er im Index oder in HEAD steht (auch
nach `git rm`/`git mv`; nach `git mv` alten und neuen Pfad nennen, sonst 12); im Hauptcheckout unter Sperre
und mit `nummernPruefung`, nur dort `-Gate`. `finish -Key K`, `status`: siehe „Zustand und Abschluss“. Ohne
`-Key` gilt der aktuelle Worktree.

- **Zugriff:** Git-Schreibschritte (`wt` außer `status`, Rebase, Amend) brauchen vollen Zugriff
  (`danger-full-access`): `workspace-write` schützt `.git`, mit `approval_policy = "never"` scheitern sie
  still. Fehlt er, vor dem ersten Git-Schreibschritt anhalten und melden. Alle Git-Schreibschritte
  einschließlich `wt commit` führt der Hauptagent selbst aus; `mechaniker` übernimmt hier nur Prüfkommandos,
  Checkboxen und Statuswörter. `wt integrate` und `wt commit -Gate` laufen lange (die Sperre wartet bis
  `sperreWartenMinuten`): Ausgabe per Umleitung in eine Log-Datei der Gate-Ablage, Shell-Timeout mindestens
  `sperreWartenMinuten` plus Gate-Laufzeit oder eine Hintergrundsitzung bis zur Zeile `WT: …` abwarten
  (Wartezyklen nach `AGENTS.md` „Lange Läufe abwarten statt pollen“); der Status gilt aus dieser Zeile. Nie
  abbrechen.
- **Wer wo:** Planung (Projektplan, Issue, Architektur, Impl-Plan), Abschluss und Registrierungen im
  Hauptcheckout auf dem Hauptbranch per `wt commit` (Grenze bei Issue-Ordnern: „Konflikte vermeiden“); dort
  auch ein Bugfix der Prüftiefe S (kein `[K]`, nichts Sicherheits- oder Datenkritisches, keine Migration) per
  `wt commit -Gate`, wenn `git status --porcelain` keine fremden Code-Pfade zeigt. Sonst ändert sich Code nur
  im Issue-Worktree: ein Worktree je Issue, eine Sitzung je Worktree, im Worktree-Ordner als eigenes Projekt
  (App: Local-Modus; CLI: `codex -C <worktree>`); Unteragenten erhalten relative Pfade, nie solche des
  Hauptcheckouts.
- **Verboten:** im Hauptcheckout Branchwechsel (`checkout`/`switch`), `stash`, `reset`, `restore` fremder
  Pfade, `git add -A`/`commit -a` und Commits außer per `wt commit`; in Issue-Branches `merge` (`wt integrate`
  verweigert Merge-Commits mit 12); überall `rebase --skip`, `--force`, `branch -D`/`-f`, `worktree add -B`,
  `update-ref` auf den Hauptbranch, `push --force` — Git schlägt genau solche Varianten vor; stattdessen
  melden. In der Codex-App weder den Worktree-Modus (übernimmt uncommittete Änderungen des Hauptcheckouts)
  noch „Hand off chat to worktree“ (`git stash push --include-untracked` im Hauptcheckout) oder „Bring
  changes back to local checkout“ (checkt den Branch im Hauptcheckout aus), weder die Tools
  `handoff_thread`/`create_worktree` noch Branch-Umschalter, Commit-/PR-Knöpfe oder „Apply“ verwenden oder
  vorschlagen.
- **Einheit:** beginnt mit `wt start -Key <KEY>` (`-Slug` nur beim Anlegen) bzw. `wt sync`, beides nur bei
  sauberem Worktree; aus dem Hauptcheckout nur `wt start` und auf eine Sitzung im Worktree-Ordner verweisen
  (Pfad aus `WORKTREE=` bzw. `wt status`). Liegt dort uncommittete Arbeit einer unterbrochenen Einheit und
  bestätigt der Nutzer, dass keine Sitzung mehr daran arbeitet, ohne `start`/`sync` in einer Sitzung im
  Worktree laut „Stand“ fortsetzen; vor einer geplanten Übergabe mitten im Gate „Stand“ schreiben. Umsetzung
  und Reviewschleife wie ohne Modus, vorher nur gezielte Tests und schnelle Gates (Befehl: Projektwert
  `schnelleGates`, sonst Plan-Feld; in `kontext.md` als „Schnelle Gates“, der Hauptagent
  gibt ihn dem Autor mit). Stand in `kontext.md`, Abhaken und Commit auf dem Branch per `wt commit`, dann
  `wt integrate` selbst aus dem Worktree (siehe „Zugriff“). Nach dem Folgeschritt je Exitcode endet die
  Sitzung; nach einer Vorab-Integration (der Branch hatte beim Einstieg nicht integrierte Commits) geht es
  mit dem nächsten offenen Schritt weiter. Nach der letzten Einheit `$abschluss` im Hauptcheckout, danach
  `wt finish -Key <KEY>`.
- **Integration am Ende (je Issue wählbar):** Der Plan trägt im Modus die Zeile `**Integration:** je Einheit`
  (Standard) oder `**Integration:** am Ende (<Grund>)` — Letzteres nur, wenn Zwischenstände nicht auf main
  dürfen oder die Einheiten sehr klein sind. Bei „am Ende“ wird jede Einheit reviewt und auf dem Branch
  committet, aber nicht integriert; eine Vorab-Integration beim Einstieg entfällt, solange Schritte offen sind.
  Jede Einheit beginnt weiter mit `wt start` bzw. `wt sync`, auch die nächste in derselben Sitzung (`wt sync`);
  das rebased die bisherigen Commits, Konflikte zeigen sich früh und klein. Ein Konflikt dabei wird wie bei 10
  aufgelöst und reviewt, danach geht es ohne `wt integrate` mit der Einheit weiter (Pfad aus `WORKTREE=` bzw.
  `wt status`). Nach der letzten Einheit einmal `wt integrate` (eine volle Kette für alle Einheiten), dann
  `$abschluss`. Korrekturen aus einem Konflikt-Review und Fixes nach rotem Gate kommen bei mehreren Commits auf
  dem Branch als eigene Commits dazu (10, 11). Preis: höheres Konfliktrisiko, Fehler der vollen Kette zeigen
  sich erst am Ende.
- **Gate:** Die volle Kette läuft genau einmal je Integration, gestartet von `wt integrate` im Worktree am
  rebasten Stand; der Nachweis gilt je Tree-Hash, ein Neulauf entfällt nur, wenn sich seither ausschließlich
  Pfade aus `gateIrrelevant` geändert haben (vom Projekt geführt, belegt per Grep über Tests und
  Gate-Skripte). Die Kette läuft im lebenden Worktree: Während des Laufs dort nicht arbeiten; Dateien, die nur
  währenddessen existieren, erkennt `wt` nicht. Vorher prüft das Skript Hauptbranch im Hauptcheckout,
  sauberen Worktree (erneut nach Erhalt der Sperre und unmittelbar vor dem Gate), keinen offenen Rebase,
  keinen Merge-Commit und keine `nurAufMain`-Datei im Branch sowie keine neue doppelte Nummer
  (`nummernPruefung`); integriert wird genau der gegatete Commit per ff unter der Hauptcheckout-Sperre.
  Formatter wenden die schnellen Gates vor dem Commit an, `gate` prüft nur; Git-Hooks dürfen keine Dateien
  umschreiben. `wt commit -Gate` startet der Hauptagent selbst wie `wt integrate`, nie `mechaniker`; es fährt
  die Kette in einem temporären Worktree auf HEAD plus den genannten Dateien, unbeeinflusst von fremder
  uncommitteter Arbeit, und committet genau die gegateten Inhalte, ohne Git-Hooks (eine seither geänderte
  Arbeitskopie bleibt uncommittet, mit Hinweis). Planungs-, Doku- und Abschluss-Commits fahren vorher
  statt der Kette die Tests und Gate-Schritte, die die Dateien lesen (`AGENTS.md`). CI-Prüfungen nach `AGENTS.md`: Auslöser sind die Integration nach main
  und autorisierte Pushes; Commits direkt auf main zählen als Integration (Code dort nur per
  `wt commit -Gate`). Den CI-Abgleich gegen `gate` führen: Fehlen relevante Prüfungen darin, blockiert das
  `wt integrate` und `wt commit -Gate`, bis `gate` sie enthält oder der Nutzer entscheidet. Commits auf dem
  Issue-Branch folgen nach gezielten Tests, schnellen Gates und Review.
- **10 Konflikt** (aus `wt start`, `wt sync` oder `wt integrate`): Rebase abgebrochen, Branch unverändert;
  ausgegeben werden Konfliktdateien, `ALTE_BASIS` und `ALTER_TIP`. Im Worktree `git rebase <hauptbranch>`;
  Code-Konflikte löst ein Autor nach Modellrouting (kritisch `implementierer_kritisch`) mit Konfliktliste und
  `kontext.md` nur in den Konfliktdateien, reine Textkonflikte der Hauptagent, der auch `git add` und
  `git -c core.editor=true rebase --continue` ausführt. Ein Halt ohne offene Konfliktdatei (rerere spielte
  eine frühere Auflösung ein) gilt ebenfalls als Konflikt. Danach prüft der Reviewer-Typ der Einheit
  (`reviewer` bzw. `reviewer_kritisch`; bei mehreren betroffenen Einheiten der stärkste) die Auflösung über
  `git range-diff --creation-factor=100 <ALTE_BASIS>..<ALTER_TIP> <neue Basis>..HEAD` samt Konfliktdateien:
  Ging eine Änderung des Hauptbranchs verloren oder wurde sie verfälscht, widerspricht die Auflösung Issue,
  Plan oder der erkennbaren Absicht der fremden Änderung? Schleife nach „Stabil prüfen“ und „Abschluss ohne
  Bestätigungsrunde“; Korrekturen committet der Hauptagent per `git commit --amend --no-edit -- <Dateien>`,
  trägt der Branch mehrere Commits, als eigenen Commit `<KEY>: Konfliktkorrektur` per `wt commit`. Dann
  erneut `wt integrate` — bei einem Konflikt aus `wt start`/`wt sync` stattdessen mit der Einheit weiter. Ein
  Rebase ohne Konflikt braucht kein Review. Einen Rebase nie offen lassen; einen vorgefundenen (`wt status`)
  erst lesen und vor `rebase --abort` den Nutzer fragen.
- **11 Gate rot:** Der Branch kann schon rebased sein (Meldung „Branch wurde rebased“ mit `ALTE_BASIS` und
  `ALTER_TIP`). Ist das Gate auch auf dem Hauptbranch rot (fremde Ursache), nicht im Einheits-Commit
  reparieren, sondern an den Nutzer. Sonst in der Sitzung im Worktree eine neue Sicherung vom aktuellen HEAD
  anlegen und die Gate-Fehler als Findings G1… ins Fix-Protokoll übernehmen; ein frischer Autor nach
  Modellrouting behebt sie uncommittet und fährt gezielte Tests und schnelle Gates; dann prüft der
  Reviewer-Typ der Einheit (bei mehreren betroffenen Einheiten der stärkste) den Fix-Diff als neuen
  Prüfgegenstand kalt (statt Claude-Fixcheck; Schleife wie bei 10). Danach committet der Hauptagent per
  `git commit --amend --no-edit -- <Fix-Dateien, kontext.md>` (neue Dateien vorher `git add -N`; die Einheit
  bleibt ein Commit), trägt der Branch mehrere Commits, als eigenen Commit `<KEY>: Gate-Fix` per `wt commit`
  (weitere rote Läufe per Amend auf genau diesen Commit), und startet erneut `wt integrate`.
- **12 blockiert:** Grund laut Meldung beheben oder melden; keine Wiederholschleife. Gründe u. a.:
  `nurAufMain`-Datei oder Merge-Commit im Branch, doppelte Nummer (siehe „Konflikte vermeiden“), „would be
  overwritten“ durch uncommittete Arbeit im Hauptcheckout, Sperre zu lange belegt, Worktree während der
  Wartezeit verändert, Konfiguration uncommittet geändert, verwaister Gate-Prozess läuft noch, nach `git mv`
  nur der neue Pfad genannt. „Commit <hash> angelegt, Hook hat Dateien verändert“: Der Commit steht schon;
  nicht wiederholen, sondern melden. Hat das Gate Dateien verändert (z. B. ein Formatter; Meldung „Gate hat
  HEAD oder den Arbeitsbaum verändert“): Formatierungsdiff prüfen, wie bei 11 committen, erneut integrieren.
  **13 Teilzustand:** ff gescheitert, nachdem sich HEAD oder vom ff betroffene Pfade des Hauptcheckouts
  verändert hatten (die Meldung nennt die Pfade): sofort stoppen, im Hauptcheckout nichts committen, Nutzer.
  Aus `finish`: Die Belegungsprobe konnte den Worktree-Ordner nicht zurückbenennen (die Meldung nennt ihn) →
  zurückbenennen (Nutzer), nie `git worktree prune`. Aus `wt commit -Gate`: Der Commit steht, die
  Indexeinträge der genannten Pfade sind nicht angeglichen (die Meldung nennt den `git reset`-Befehl) →
  nichts weiter committen, Nutzer. **14 nichts zu tun:** per `wt status` prüfen, ob
  erwartet (z. B. schon integriert), sonst melden. **1:** melden (bei Bindungsfehlern kann die `WT:`-Zeile
  fehlen). Sachkonflikte (zwei unvereinbare Absichten) immer an den Nutzer, mit beiden Seiten und einem
  Vorschlag.
- **Konflikte vermeiden:** Dateien aus `nurAufMain` nie im Branch: im Hauptcheckout vor jeder Änderung
  `git diff --quiet -- <datei>` (fremde Änderungen → anhalten, Nutzer fragen), dann bearbeiten und sofort
  per `wt commit` festschreiben; kein Schrittfortschritt im Projektplan (den tragen die Plan-Häkchen). Neue
  Issue-Nummern vor der ersten Verwendung per Reservierungs-Commit auf main (Projektplan ohne fremde
  Änderungen, nur die neue Zeile; `<KEY>-<NNN>: registriert`), auch mitten in einer Einheit. Beides aus einer
  Worktree-Sitzung: Datei im Hauptcheckout bearbeiten, `wt commit -Repo <Hauptcheckout>`. ADR- und
  Migrationsnummern ohne Reservierung im Branch vergeben (Planung: im Hauptcheckout); Dubletten meldet
  `nummernPruefung` bei `wt integrate` und bei `wt commit` im Hauptcheckout (12, wenn ein vom Branch bzw.
  Commit neu vergebener Name beteiligt ist; ältere nur als WARNUNG) → umnummerieren, im Branch bzw. vor dem
  Commit. Solange ein Issue einen Worktree mit nicht integrierten Commits hat oder dort gearbeitet wird,
  schreibt nur dessen Branch den Issue-Ordner, auch eine Neufreigabe des Plans entsteht im Worktree; nach der
  letzten Integration schreibt der Abschluss im Hauptcheckout (Zusammenfassung, Projektplan-Status). Bedarf
  anderer Sitzungen geht über den Nutzer. Einmalig im Repo `git config rerere.enabled true` und
  `git config merge.conflictStyle zdiff3`; kein `merge=union` (stille Doppelzeilen).
- **Zustand und Abschluss:** `wt status` ist die Zustandsquelle für Worktrees (voller Pfad, Vorsprung und
  Rückstand, offene Rebases, letzte Änderung, Sperren nur lesend geprüft, nicht integrierte und integrierte
  Branches ohne Worktree, nicht registrierte Reste unter `worktreeRoot`). Integriert heißt: `wt status` markiert
  die Worktree-Zeile mit `integriert` (Branch vollständig im Hauptbranch enthalten) bzw. zeigt „Branch
  integriert, ohne Worktree“. Hat ein Issue einen Worktree, liegen Stand, Häkchen und Gate-Ablage dort; in
  einem Issue-Worktree ist dessen Issue das aktive, sonst bei parallelen Sitzungen das genannte, ohne Angabe
  das erste nicht erledigte, an dem keine andere Sitzung arbeitet. Uncommittete Dateien oder Änderungen der
  letzten 30 Minuten im Worktree (bei Issues in Planung im Issue-Ordner des Hauptcheckouts): vor dem Einstieg
  fragen, ob dort eine Sitzung läuft. Nicht integrierte Commits zuerst integrieren (`wt integrate` gatet
  selbst, wenn kein Nachweis vorliegt), bei „am Ende“ erst, wenn alle Schritte erledigt sind. Abschluss im
  Hauptcheckout, wenn `wt status` den Branch als integriert zeigt; danach `wt finish -Key <KEY>` nur aus dem
  Hauptcheckout, vorher App-Projekt, Terminals und Prozesse im Worktree schließen. `finish` (nur wenn
  integriert) übernimmt die Gate-Ablage ohne Überschreiben nach `<gateAblage>/_worktrees/<key>/`, sichert eine
  abweichende `.claude/settings.local.json` dorthin, nennt die übrigen ignorierten Einträge, die mit dem
  Worktree gelöscht werden, und entfernt Worktree und Branch. Wird es im Worktree aufgerufen, ist der Ordner
  belegt oder läuft ein Programm aus dem Worktree (Meldung mit PID und Pfad), verweigert es (12), bevor etwas
  gelöscht ist: schließen und erneut aufrufen; meldet git beim Entfernen veränderte oder ungetrackte Dateien,
  endet es mit 12 und nennt sie. Einen Worktree mit initialisierten Submodulen entfernt es nur, wenn diese
  sauber sind (sonst 12). Junctions und Symlinks im Worktree entfernen `finish` und der Abbau temporärer
  Gate-Worktrees nur als Links, nie ihre Ziele, und nennen sie mit Ziel (scheitert das: 12 mit Liste, nichts
  weiter gelöscht). Einen leeren, nicht registrierten Ordner eines früheren Versuchs räumt ein erneutes
  `finish` ab, wenn der Branch integriert ist; einen Probe-Ordner `<dir>.wt-probe-*` zurückbenennen (siehe 13).
  Verwaiste `_gate-*`-Ordner entfernt der nächste `wt commit -Gate`, soweit möglich; andere Reste
  (`wt status`: „Rest entfernen, Mensch“) → Nutzer.
