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
- **Arbeitsbaum-Modus (opt-in):** Claude-Regeln in `share/arbeitsbaeume.md`, Codex-Regeln vollständig in
  `codex/arbeitsbaeume.md` (Codex liest `~/.claude` nicht), Mechanik in `share/tools/wt.ps1` für beide (Test:
  `tests/wt-smoke.ps1`). Exitcodes, Befehle und Projektwerte in allen drei gleich halten. Kurzfassungen der
  Modus-Regeln tragen `implementierer`, `mechaniker`, `mutations-pruefer`, die Skills `implementieren`,
  `naechster-schritt`, `abschluss`, `issue`, `projektplan`, `architektur` und `impl-plan`, `konventionen.md`
  (Tests & Gates, Sessions, Arbeitsbäume, Commit-Konvention), `review-gate.md` (Einleitung, 2.4, 2.5, 3.3, 5,
  6, Muster 6), die Vorlagen `kontext.md` (Zeile „Schnelle Gates“) und `impl-plan.md` (Zeile
  `**Integration:**`), in `codex/AGENTS.md` die Punkte „Sequenziell als Standard“, „CI-Prüfungen vor
  Git-Aktionen“ (nur der Verweis), „Abschluss ohne Bestätigungsrunde“, „Kontext klein halten“ und „Arbeitsbäume
  (opt-in)“ sowie die Codex-Rollen und -Skills — bei Änderungen an den Modus-Regeln alle mitziehen.
- Nach Änderungen: `install.ps1` erneut ausführen. Codex-Dateien mit abweichendem Inhalt
  werden vorher unter `~/.codex/ai-sdlc-backups/` gesichert, eigene Dateien in kopierten
  Claude-Verzeichnissen unter `~/.claude/ai-sdlc-backups/`.

Details & Modellwahl: `README.md`.
