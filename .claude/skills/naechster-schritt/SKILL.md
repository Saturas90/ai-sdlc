---
name: naechster-schritt
description: Orchestrator des SDLC-Workflows. Erkennt anhand vorhandener Dateien den Stand des aktuellen Issues/Projekts und startet die passende nächste Phase (Projektplan → Issue → optional Architektur → Impl-Plan → Implementierung → Abschluss). Nutzen, wenn unklar ist, was als Nächstes zu tun ist, oder um den Workflow zu treiben.
---

# Orchestrator: Nächster Schritt

Ziel: den korrekten nächsten Workflow-Schritt bestimmen und **nur diesen** anstoßen — token­sparsam, ohne Inhalte breit einzulesen.

## Stand erkennen

Prüfe **nur** Datei-Existenz, die Statuszeile `**Status:** Freigegeben`, Checkboxen und die
Projektplan-Status-Spalte (Marker: `konventionen.md` → „Status- & Freigabe-Marker“). Keine Inhalte breit einlesen.
„Freigegeben“ heißt: die Datei enthält die Zeile `**Status:** Freigegeben` — nicht das bloße Wort.

1. Kein `projektplan.md` → **Projektplan** → `/projektplan`.
2. **Alle** Projektplan-Issues haben Status `erledigt` → **Projekt fertig**, terminieren (nichts weiter tun, dem Nutzer melden).
3. Sonst **aktives Issue** = erste Projektplan-Zeile mit Status ≠ `erledigt`. Für dieses Issue der Reihe nach:
   1. kein `issues/IS-<NNN>-*/issue.md` → **Issue** → `/issue`.
   2. `issue.md` ohne `**Status:** Freigegeben` **oder** offene `- [ ]` im Abschnitt „Offene Fragen“ → im Issue-Schritt bleiben (Review/Fragen/Freigabe offen) → `/issue`.
   3. „Architekturplan nötig: ja“ und `architektur.md` fehlt bzw. ohne `**Status:** Freigegeben` bzw. mit offenen „Offene Fragen“ → **Architektur** → `/architektur`.
   4. `impl-plan.md` fehlt bzw. ohne `**Status:** Freigegeben` bzw. mit offenen „Offene Fragen“ → **Impl-Plan** → `/impl-plan`.
   5. `impl-plan.md` freigegeben mit offenen `[ ]`-**Schritten** → **Implementierung** → `/implementieren`.
   6. alle Impl-Schritte `[x]`, keine `zusammenfassung.md` → **Abschluss** → `/abschluss`.
   7. `zusammenfassung.md` vorhanden, aber Projektplan-Status noch ≠ `erledigt` → Status via `mechaniker` auf `erledigt` setzen, dann zurück zu 2.

Hinweis: „offene `- [ ]`“ ist je nach Abschnitt zu unterscheiden — Akzeptanzkriterien und Impl-Schritte sind eigene Checkbox-Listen; für das Fragen-Gate zählt nur der Abschnitt „Offene Fragen“.

## Regeln

- An jedem menschlichen Freigabe-Gate **anhalten** und nachfragen; nicht eigenmächtig über Gates hinweg arbeiten.
- Immer nur **einen** Schritt anstoßen, nicht mehrere Phasen auf einmal.
- Konventionen: `~/.claude/ai-sdlc/konventionen.md` (nur bei Bedarf lesen).

## Modell-Hinweis (Kosten)

Orchestrierung und Status-Erkennung sind leichtgewichtig → Session ruhig auf **Sonnet** laufen lassen. Teure Modelle nur dort, wo die Phase sie vorgibt (Architektur = Opus). Die Phasen delegieren die eigentliche Arbeit an spezialisierte Sub-Agenten mit passendem Modell.
