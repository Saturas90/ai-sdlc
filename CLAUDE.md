# ai-sdlc — Toolkit-Repo

Quell-Repo für einen dateibasierten SDLC-Workflow (Claude Code und Codex).
Wird nach `~/.claude/` und `~/.codex/` installiert und dann in **anderen** Projekten genutzt.

- Claude Code: `.claude/skills/` und `.claude/agents/`.
- Codex: `codex/AGENTS.md`, `codex/agents/`, `codex/skills/` und
  `codex/config.defaults.toml` (nur Modell-Standardwerte in einer vorhandenen Config).
- Geteilte Wissensbasis (Konventionen, Review-Gate, Vorlagen): `share/` → installiert nach `~/.claude/ai-sdlc/`.
- **DRY:** Fachliche Claude-Regeln in `share/konventionen.md`, Codex-Modellrouting in
  `codex/AGENTS.md` und den benannten Rollen pflegen.
- Nach Änderungen: `install.ps1` erneut ausführen. Codex-Dateien mit abweichendem Inhalt
  werden vorher unter `~/.codex/ai-sdlc-backups/` gesichert.

Details & Modellwahl: `README.md`.
