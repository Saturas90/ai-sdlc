# Review-Checkliste

Von `reviewer` und `reviewer-kritisch` genutzt (DRY: hier ändern, nicht in den Agenten).

Prüfe den Gegenstand gegen: das **Issue (Scope!)**, ggf. Architektur/Impl-Plan,
`~/.claude/ai-sdlc/konventionen.md` und — bei Code — Korrektheit/Robustheit.

Achte besonders auf:
- **Scope-Treue**: wird geplant/umgesetzt, was nicht im Issue steht? (kritisch/hoch)
- Vollständigkeit gegenüber den Akzeptanzkriterien.
- Interpretationsspielraum / Mehrdeutigkeit in Plänen (hoch).
- Korrektheit, Sicherheit, Datenverlust, Fehlerbehandlung, Randfälle bei Code (kritisch/hoch).
- Struktur-Regeln: Offene Fragen am Ende? Out of Scope referenziert/abgelehnt?

Kategorien (Definitionen in `konventionen.md`): kritisch / hoch / mittel / niedrig.

**Rückgabe (kompakt):** Findings als Liste — je `Kategorie | Fundstelle | Problem | konkreter Vorschlag`.
Letzte Zeile: `Blockierend: ja/nein` (ja, sobald ≥1 kritisch/hoch). **Bessere nichts selbst aus** — du bewertest nur.
