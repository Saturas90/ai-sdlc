# Verbrauch nachmessen

`verbrauch_auswerten.py` wertet die Claude-Code-Transkripte unter `~/.claude/projects/<projekt>/` aus:
Kosten (API-Äquivalent zu Listenpreisen, nicht Abo-Verbrauch) je Hauptsession, Agententyp und Workflow,
Kostenkomponenten, Modelle und Effort, `reviewer-kritisch` je Workflow-Phase, die Hauptsession nach
Kontextgröße und die **Workflow-Serien**: je Prüfgegenstand (Workflow-Name ohne Rundensuffix wie `-r3`)
Läufe ≈ Runden, Agenten und Anteil der Verify-Agenten. Die Serienbildung ist eine Namensheuristik; sie
trifft nur Workflows, die nach `review-gate.md` als `<gegenstand>-r<N>` benannt sind, verlässlich.

```bash
PYTHONUTF8=1 python ~/.claude/ai-sdlc/tools/verbrauch_auswerten.py --seit 2026-09-23 --bis 2026-09-30
```

`--seit` ist inklusive, `--bis` exklusive (ISO-Datum oder -Zeitstempel). Ohne `--projekt` wird der
Projektordner aus dem aktuellen Verzeichnis abgeleitet (jedes Zeichen außer A-Z/a-z/0-9 → `-`, wie
Claude Code ihn anlegt); sonst den Ordnernamen unter `~/.claude/projects/` angeben.

## Baseline

Vor einer Änderung an Agenten, Modellen oder Effort die Ausgabe für einen Referenzzeitraum als Textdatei
sichern — **außerhalb** von `~/.claude/ai-sdlc/`, z. B. unter `~/.claude/ai-sdlc-baselines/`, da
`install.ps1` dieses Verzeichnis ersetzt (eigene Dateien sichert es nach `~/.claude/ai-sdlc-backups/`)
bzw. bei Symlink-Installation ins Repo schreibt.

Referenz vor der Umstellung auf Prüftiefe, Fixcheck und Verify nur für Blocker (BMS, 23.09.–02.10.2026,
Werte dieses Skripts): gesamt 5.086 $, Workflow-Reviewer 56 % (`reviewer-kritisch` 31 %,
`reviewer-architektur` 25 %), Hauptsession 18 %; Workflow-Serien: 78 Serien, 148 Läufe, 4.893 Agenten,
davon 85 % Verify. Aus einer gesonderten Agenten-Auswertung von 39 Mehrrunden-Serien (20.09.–02.10.):
im Mittel 4,6 Runden je Serie, 17 % der Review-Tokens nach dem ersten grünen Gate.

## Was vergleichen

Erst Zeiträume ab einem Session-Neustart nach der Änderung messen — geänderte Agenten greifen erst dann.
Beim Vergleich auf gleiche Arbeitsart achten (Planungs- vs. Implementierungswochen) und Anteile statt
Absolutwerte vergleichen:

- Anteil der Verify-Agenten an den Workflow-Agenten und Runden je Serie (Workflow-Serien).
- Anteil und Kosten je Spawn von `reviewer-kritisch` (effort high; Architekturpläne gehen an
  `reviewer-architektur`).
- Anteil `workflow:workflow-subagent` und `agent:general-purpose` (untypisierte Spawns; sollten durch die
  `agentType`-Pflicht und `rechercheur` gegen null gehen).
- Hauptsession: Anteil der Kosten in Requests über 300K bzw. 500K Kontext (Session-Schnitt).
- Turns je Spawn von `implementierer` und `impl-planer` (Kontext-Anker im Plan, frischer Autor je Einheit).
- Output je Spawn beim Wechsel der Modellversion hinter einem Alias (z. B. `opus`) — neuere Modelle
  können je Effort-Stufe mehr denken.
