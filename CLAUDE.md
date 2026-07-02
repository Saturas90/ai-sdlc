# ai-sdlc — Toolkit-Repo

Quell-Repo für einen dateibasierten SDLC-Workflow (Claude-Code-Skills + Sub-Agenten).
Wird nach `~/.claude/` installiert und dann in **anderen** Projekten genutzt.

- Skills: `.claude/skills/` · Sub-Agenten: `.claude/agents/`
- Geteilte Wissensbasis (Konventionen, Review-Gate, Vorlagen): `share/` → installiert nach `~/.claude/ai-sdlc/`.
- **DRY:** Regeln nur in `share/konventionen.md` ändern, nicht in Skills duplizieren.
- Nach Änderungen: `install.ps1` erneut ausführen (bei Symlink-Installation nur bei neuen/entfernten Dateien nötig).

Details & Modellwahl: `README.md`.
