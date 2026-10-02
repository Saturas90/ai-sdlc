# ai-sdlc — Toolkit-Repo

Quell-Repo für einen dateibasierten SDLC-Workflow (Claude Code und Codex).
Wird nach `~/.claude/` und `~/.codex/` installiert und dann in **anderen** Projekten genutzt.

- Claude Code: `.claude/skills/` und `.claude/agents/`.
- Codex: `codex/AGENTS.md`, `codex/agents/`, `codex/skills/` und
  `codex/config.defaults.toml` (nur Modell-Standardwerte in einer vorhandenen Config).
- Geteilte Wissensbasis (Konventionen, Review-Gate, Vorlagen): `share/` → installiert nach `~/.claude/ai-sdlc/`.
- **DRY:** Fachliche Claude-Regeln in `share/konventionen.md`, Review-Ablauf in
  `share/review-gate.md`, Codex-Modellrouting und -Reviewschleife in `codex/AGENTS.md` und den
  benannten Rollen pflegen. Ausnahmen: Die Review-Prüfpunkte stehen bewusst im Body von `reviewer`,
  `reviewer-kritisch` und `reviewer-architektur` — Änderungen sinngemäß in allen drei nachziehen (siehe
  `share/review-checkliste.md`). `implementierer` trägt Kurzfassungen von „Kontext-Ökonomie“ und
  „Korrektur nach Review“, `rechercheur` die Leseregeln aus „Kontext-Ökonomie“ (spart je Spawn das Lesen
  der Konventionen); `architekt`, `impl-planer` und `issue-autor` lesen `konventionen.md` als Grundlage —
  bei Änderungen dort mitziehen. Auf der Codex-Seite tragen die Autor-Rollen die Kurzfassung von
  „Korrekturen minimal“ aus `codex/AGENTS.md`.
- Nach Änderungen: `install.ps1` erneut ausführen. Codex-Dateien mit abweichendem Inhalt
  werden vorher unter `~/.codex/ai-sdlc-backups/` gesichert, eigene Dateien in kopierten
  Claude-Verzeichnissen unter `~/.claude/ai-sdlc-backups/`.

Details & Modellwahl: `README.md`.
