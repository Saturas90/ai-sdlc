# Verbrauch nachmessen

`verbrauch_auswerten.py` wertet die Claude-Code-Transkripte unter `~/.claude/projects/<projekt>/` aus:
Kosten (API-Äquivalent zu Listenpreisen, nicht Abo-Verbrauch) je Hauptsession, Agententyp und Workflow,
Kostenkomponenten, Modelle und Effort, `reviewer-kritisch` je Workflow-Phase und die Hauptsession nach
Kontextgröße.

```bash
PYTHONUTF8=1 python ~/.claude/ai-sdlc/tools/verbrauch_auswerten.py --seit 2026-09-23 --bis 2026-09-30
```

`--seit` ist inklusive, `--bis` exklusive (ISO-Datum oder -Zeitstempel). Ohne `--projekt` wird der
Projektordner aus dem aktuellen Verzeichnis abgeleitet (jedes Zeichen außer A-Z/a-z/0-9 → `-`, wie
Claude Code ihn anlegt); sonst den Ordnernamen unter `~/.claude/projects/` angeben.

## Baseline

Vor einer Änderung an Agenten, Modellen oder Effort die Ausgabe für einen Referenzzeitraum als Textdatei
sichern — **außerhalb** von `~/.claude/ai-sdlc/`, da `install.ps1` dieses Verzeichnis ersetzt (bzw. bei
Symlink-Installation ins Repo schreibt).

## Was vergleichen

Erst Zeiträume ab einem Session-Neustart nach der Änderung messen — geänderte Agenten greifen erst dann.
Beim Vergleich auf gleiche Arbeitsart achten (Planungs- vs. Implementierungswochen) und Anteile statt
Absolutwerte vergleichen:

- Anteil und Kosten je Spawn von `reviewer-kritisch` (effort high; Architekturpläne gehen an
  `reviewer-architektur`).
- Anteil `workflow:workflow-subagent` (Workflow-Agenten ohne `agentType`; sollte durch die
  `agentType`-Pflicht aus `review-gate.md` gegen null gehen).
- Hauptsession: Anteil der Kosten in Requests über 300K bzw. 500K Kontext (Session-Schnitt).
- Output je Spawn beim Wechsel der Modellversion hinter einem Alias (z. B. `opus`) — neuere Modelle
  können je Effort-Stufe mehr denken.
