---
name: review
description: Führt ein eigenständiges Review eines Artefakts oder Diffs durch und liefert Findings kategorisiert nach kritisch/hoch/mittel/niedrig. Wird intern von allen Phasen genutzt, kann aber auch direkt aufgerufen werden.
---

# Skill: Review

1. Gegenstand bestimmen: Datei(en) oder aktueller Diff + zugehöriger Kontext (Issue / Architektur / Impl-Plan / `kontext.md`).
2. Prüftiefe nach `~/.claude/ai-sdlc/review-gate.md` Abschnitt 1 wählen (S: ein Reviewer-Spawn; M/L: Workflow nach den Workflow-Mustern). Reviewer nach Risiko: Standard → **`reviewer`** (sonnet); `[K]`, `Prüftiefe: L` oder sicherheits-/datenkritisch → **`reviewer-kritisch`** (opus); Architekturplan oder ADR → **`reviewer-architektur`** (opus, xhigh).
3. Prüfpaket übergeben (Abschnitt 2). Der Reviewer liefert Findings: je `Kategorie | Fundstelle | Zitat | Problem | Vorschlag`, plus `Blockierend: ja/nein`.
4. Findings kompakt und dedupliziert zurückgeben.

Regeln & Kategorien: Severity-Schema der Projekt-CLAUDE.md, falls vorhanden (Vorrang), sonst `~/.claude/ai-sdlc/konventionen.md` · Gate-Ablauf: `~/.claude/ai-sdlc/review-gate.md`.
Der Reviewer bewertet nur — nachgebessert wird durch den erzeugenden Agenten.
