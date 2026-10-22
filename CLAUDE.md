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
  „Korrektur nach Review“; `implementierer-kritisch` hat denselben Body plus die Absätze zu kritischen Kanten
  und zur max-Eskalation — Änderungen in beiden nachziehen. `rechercheur` trägt die Leseregeln aus „Kontext-Ökonomie“ (spart je Spawn das Lesen
  der Konventionen); `architekt`, `impl-planer` und `issue-autor` lesen `konventionen.md` als Grundlage —
  bei Änderungen dort mitziehen. Auf der Codex-Seite tragen die Autor-Rollen die Kurzfassung von
  „Korrekturen minimal“ aus `codex/AGENTS.md`.
- **Arbeitsbaum-Modus (opt-in):** Claude-Regeln in `share/arbeitsbaeume.md`, Codex-Regeln vollständig in
  `codex/arbeitsbaeume.md` (Codex liest `~/.claude` nicht), Mechanik in `share/tools/wt.ps1` für beide (Test:
  `tests/wt-smoke.ps1`). Exitcodes, Befehle und Projektwerte in allen drei gleich halten. Kurzfassungen der
  Modus-Regeln tragen `implementierer`, `implementierer-kritisch`, `mechaniker`, `mutations-pruefer`, die Skills `implementieren`,
  `naechster-schritt`, `abschluss`, `issue`, `projektplan`, `architektur` und `impl-plan`, `konventionen.md`
  (Tests & Gates, Sessions, Arbeitsbäume, Commit-Konvention), `review-gate.md` (Einleitung, 2.4, 2.5, 3.3, 5,
  6, Muster 6), die Vorlagen `kontext.md` (Zeile „Schnelle Gates“) und `impl-plan.md` (Zeile
  `**Integration:**`), in `codex/AGENTS.md` die Punkte „Sequenziell als Standard“, „CI-Prüfungen vor
  Git-Aktionen“ (Verweis, Befehlsquelle `schnelleGates`, Abgrenzungen „ohne Arbeitsbaum-Modus“), „Abschluss
  ohne Bestätigungsrunde“, „Kontext klein halten“ und „Arbeitsbäume (opt-in)“ sowie die Codex-Rollen und -Skills — bei Änderungen an den Modus-Regeln alle mitziehen.
- **Gate-Zeitpunkte:** Claude-Regeln in `share/konventionen.md` › Tests & Gates (schnelle Gates, eine Kette je
  Einheit, Planungs-/Doku-Commits, Wächter-Set, Drift-Prüfung), Codex-Regeln vollständig in `codex/AGENTS.md`
  „CI-Prüfungen vor Git-Aktionen“ (dazu „Lange Läufe abwarten statt pollen“). Kurzfassungen tragen
  `implementierer`, `implementierer-kritisch`, `mechaniker` (Drift-Vermerk, HEAD-Abgleich; Codex: Polling), `impl-planer`, die Skills `implementieren`, `issue`, `architektur`, `impl-plan`, `projektplan`,
  `abschluss` und `naechster-schritt`, `review-gate.md` (3.3, 5), `arbeitsbaeume.md` (4), die Vorlagen
  `kontext.md` und `impl-plan.md`, in `codex/AGENTS.md` „Abschluss ohne Bestätigungsrunde“,
  `codex/arbeitsbaeume.md` sowie die Codex-Rollen
  `implementierer`, `implementierer_kritisch`, `mechaniker`, `impl_planer`, die Codex-Skills und der
  Codex-Absatz im README — bei Änderungen alle mitziehen.
- **max-Eskalation:** Claude-Regel in `share/review-gate.md` Abschnitt 4 (Reviewer-Effort in Abschnitt 1),
  Codex-Regel vollständig in `codex/AGENTS.md` „Konvergenz“. Kurzfassungen tragen `implementierer-kritisch`,
  die Skills `implementieren` und `review`, `konventionen.md` › Agenten, `arbeitsbaeume.md` (Fall 10), die
  Vorlage `kontext.md` (Stand), `review-gate.md` 2.4, das README, auf der Codex-Seite „Modelle nach
  Verantwortung“, `codex/arbeitsbaeume.md` (Fall 10), `implementierer_kritisch` und der Codex-Skill
  `implementieren` — bei Änderungen alle mitziehen.
- Nach Änderungen: `install.ps1` erneut ausführen. Codex-Dateien mit abweichendem Inhalt
  werden vorher unter `~/.codex/ai-sdlc-backups/` gesichert, eigene Dateien in kopierten
  Claude-Verzeichnissen unter `~/.claude/ai-sdlc-backups/`.

Details & Modellwahl: `README.md`.
