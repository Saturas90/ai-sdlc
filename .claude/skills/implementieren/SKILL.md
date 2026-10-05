---
name: implementieren
description: Arbeitet den freigegebenen Implementierungsplan schrittweise ab. Bündelt einfache Schritte, führt [K]-Schritte einzeln aus, sichert jede Einheit per Review (Prüftiefe je Schritt) ab, hakt sie im Plan ab und committet mit Issue-Nummer.
---

# Skill: Implementierung

Voraussetzung: `impl-plan.md` freigegeben. Eine Session je Einheit ist günstiger als eine lange Session
(„Kontext-Ökonomie“ in `~/.claude/ai-sdlc/konventionen.md`).

**Arbeitsbaum-Modus** (die Projekt-CLAUDE.md hat `## Arbeitsbäume (ai-sdlc)`; Regeln und Exitcodes:
`~/.claude/ai-sdlc/arbeitsbaeume.md`; `wt` = `pwsh -NoProfile -File "$HOME/.claude/ai-sdlc/tools/wt.ps1"`, nie
das Programm `wt`, Ergebnis nur mit Schlusszeile `WT: …` werten): Zuerst `wt status`. Zeigt der Worktree des
Issues uncommittete Dateien oder Änderungen der letzten 30 Minuten, den Menschen fragen, ob dort eine Session
läuft; bestätigt er, dass keine läuft, und liegt uncommittete Einheitsarbeit vor: ohne `wt start` direkt
`EnterWorktree(path: <Pfad aus wt status>)` und laut „Stand“ fortsetzen. Sonst: Hat der Branch nicht
integrierte Commits, zuerst Schritt 6 (Vorab-Integration) — bei `**Integration:** am Ende` im Plan nicht,
solange Schritte offen sind. Dann `wt start -Key <KEY>` (beim Anlegen mit `-Slug`) und
`EnterWorktree(path: <Pfad aus der Zeile WORKTREE=>)`; bei „am Ende“ beginnt jede weitere Einheit der Session
mit `wt sync` im Worktree. Exitcode von `wt start`/`wt sync`: 10 → `arbeitsbaeume.md` Fall 10, danach ohne
`wt integrate` mit der Einheit weiter; 12 und 1 → Abschnitt 3. Schritt 2 gibt den Befehl der
schnellen Gates mit (Projektwert `schnelleGates`, sonst Schnell-Gate des Plans); in Schritt 3 statt der vollen
Gate-Kette nur gezielte Tests und schnelle Gates; Schritt 5 committet auf dem Issue-Branch; danach Schritt 6.

Schleife über die offenen `[ ]`-Schritte:

1. **Einheit wählen:** einfache Schritte dürfen gebündelt werden; `[K]`-Schritte einzeln.
2. **Umsetzen:** je Einheit einen **frischen** Sub-Agenten **`implementierer`** (Modell: sonnet) spawnen; Übergabe: Schritt-IDs, Pfade von `impl-plan.md` und `kontext.md`. Triviale Einheiten (eine Datei, keine Logikänderung) direkt erledigen. Nur was im Impl-Plan/Issue steht — kein Scope-Creep.
3. **Review-Gate** auf den Diff der Einheit anwenden (`~/.claude/ai-sdlc/review-gate.md`): normale Einheit → Prüftiefe S mit `reviewer`, sicherheits-/datenkritischer Code auch ohne Marker mit `reviewer-kritisch`; `[K]` → M, `Prüftiefe: L` → L (`reviewer-kritisch`). Kritisch/hoch → derselbe Implementierer behebt mit den deduplizierten Findings (höchstens zwei Fortsetzungen, dann frisch) → nächste Runde. Runde mit nur mittel/niedrig → einarbeiten, Fixcheck, ggf. Rücknahmen, danach Tests und Gate-Kette grün — keine weitere Runde; ist eine Meldung „unklare Herkunft“ offen, weder abhaken noch committen, bis der Mensch entschieden hat. Kein Human-Gate pro Schritt; Konvergenz-Stopp ab Runde 3.
4. **Stand** in `kontext.md` (bzw. die dort verwiesene projekteigene Übergabe) überschreiben (nächster Schritt, offene Entscheidungen) und Vertagtes eintragen; ist die Session groß, neue Session für die nächste Einheit vorschlagen.
5. **Abhaken + Commit** an `mechaniker` (haiku) delegieren: erledigte Schritte in `impl-plan.md` auf `[x]` setzen und `IS-<NNN>: <was getan wurde>` committen (mit `kontext.md` bzw. der projekteigenen Übergabe, sofern versioniert).
6. **Integration** (nur Arbeitsbaum-Modus; bei `**Integration:** am Ende` im Plan erst nach dem letzten Schritt, `arbeitsbaeume.md` Abschnitt 2): `ExitWorktree(action: "keep")`, dann `wt integrate -Key <KEY>` selbst im Hintergrund starten (nicht über `mechaniker`). Exitcode 0 → die Session endet (nach einer Vorab-Integration weiter mit `wt start` und dem nächsten offenen Schritt). 10 Konflikt, 11 Gate rot, 12 blockiert, 13 Teilzustand, 14 nichts zu tun, 1 Fehler → `arbeitsbaeume.md` Abschnitt 3 (Konfliktauflösung mit Review nach `review-gate.md` Abschnitt 6; rotes Gate: Gate-Fehler als Findings, frischer Autor, Fixcheck; Korrekturen per `git commit --amend` durch die Hauptsession, bei mehreren Commits auf dem Branch als eigener Commit `<KEY>: Konfliktkorrektur` bzw. `<KEY>: Gate-Fix` über `mechaniker`, weitere rote Läufe per Amend in diesen Gate-Fix-Commit).

Wenn alle Schritte `[x]` (im Arbeitsbaum-Modus: und laut `wt status` integriert): `/abschluss`.
