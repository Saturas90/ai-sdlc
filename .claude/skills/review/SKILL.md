---
name: review
description: Führt ein eigenständiges Review eines Artefakts oder Diffs durch und liefert Findings kategorisiert nach kritisch/hoch/mittel/niedrig. Wird intern von allen Phasen genutzt, kann aber auch direkt aufgerufen werden.
---

# Skill: Review

1. Gegenstand bestimmen: Datei(en) oder aktueller Diff + zugehöriger Kontext (Issue / Architektur / Impl-Plan).
2. Reviewer nach Risiko wählen: Standard → **`reviewer`** (sonnet); Architektur/`[K]`/sicherheits-/datenkritisch → **`reviewer-kritisch`** (opus). Er liefert Findings: je `Kategorie | Fundstelle | Problem | Vorschlag`, plus `Blockierend: ja/nein`.
3. Findings kompakt zurückgeben.

Regeln & Kategorien: `~/.claude/ai-sdlc/konventionen.md` · Gate-Ablauf: `~/.claude/ai-sdlc/review-gate.md`.
Der Reviewer bewertet nur — nachgebessert wird durch den erzeugenden Agenten.
