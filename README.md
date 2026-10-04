# ai-sdlc

Ein dateibasiertes **SDLC-Toolkit für Claude Code und Codex**: Es bildet deinen Ablauf
*Projektplan → Issue → (Architektur) → Implementierungsplan → Implementierung → Abschluss*
mit Review-Gates, menschlichen Freigaben und Commits ab — als kleine, token­arme Skills
und spezialisierte Sub-Agenten. Alle Artefakte sind Markdown im jeweiligen Projekt-Repo.

## Installation (einmalig)

```powershell
cd <pfad-zu-diesem-repo>    # dorthin, wo du ai-sdlc abgelegt/geklont hast
./install.ps1              # Claude nach ~/.claude, Codex nach ~/.codex; -Copy erzwingt Kopien
```

Danach sind die Skills in **jedem** Projekt verfügbar. Symlinks brauchen Admin-Rechte
_oder_ den Windows-Entwicklermodus (Einstellungen → System → Für Entwickler).
Bei fehlenden Rechten kopiert der Installer. Eine bestehende Codex-`config.toml` behält alle
anderen Einstellungen; der Installer aktualisiert nur `model`, `model_reasoning_effort` und
die zwei Agent-Standardwerte. Abweichende Codex-Dateien werden vor dem Ersetzen unter
`~/.codex/ai-sdlc-backups/` gesichert, versehentlich in kopierte Claude-Verzeichnisse gelegte eigene
Dateien unter `~/.claude/ai-sdlc-backups/`. Lokale Änderungen an installierten Repo-Dateien werden ohne
Sicherung überschrieben — Änderungen gehören ins Repo; Messbaselines nach `~/.claude/ai-sdlc-baselines/`.
Der Installer braucht PowerShell 7 (`pwsh`). Zum Prüfen ohne Änderungen am Benutzerprofil:

```powershell
pwsh -File tests/install-smoke.ps1
```

## Nutzung im Zielprojekt

Wechsle in dein Tool-Projekt (Git-Repo) und lass dich vom Orchestrator führen:

```
/naechster-schritt        # erkennt den Stand und startet die passende Phase
```

Oder eine Phase direkt aufrufen:

In Claude Code mit `/naechster-schritt`, in Codex mit `$naechster-schritt`.
Codex bietet zusätzlich `$init-reading` für eine kurze Bestandsaufnahme.

| Skill | Zweck |
|-------|-------|
| `/projektplan`     | Projektplan mit Ziel, Ablauf, Issue-Liste (IS-Keys) |
| `/issue`           | Ein Issue erstellen, reviewen, freigeben lassen |
| `/architektur`     | Architekturplan (nur wenn im Issue als nötig markiert) |
| `/impl-plan`       | Implementierungsplan mit abhakbaren Schritten |
| `/implementieren`  | Plan schrittweise umsetzen, je Einheit Review + Commit |
| `/review`          | Eigenständiges Review (kritisch/hoch/mittel/niedrig) |
| `/abschluss`       | Zusammenfassung + Scope-Abgleich |

### Ablage im Zielprojekt

```
projektplan.md
issues/IS-<NNN>-<slug>/{issue,kontext,architektur,impl-plan,zusammenfassung}.md
```

`kontext.md` ist das **Kontextpaket** des Issues (≤ 8 KB, kein Freigabe-Artefakt): relevante Stellen
als Anker mit Datei:Zeile, tragende Normauszüge, Tests, bewusst Irrelevantes und der Stand für die
nächste Session. Jeder Agent steigt dort ein, statt das Projekt erneut zu durchsuchen.

## Regeln (Kurzfassung)

- Jedes Planungsartefakt durchläuft ein **Review-Gate** und wird iteriert, bis keine
  **kritisch/hoch**-Findings offen sind — erst dann **menschliche Freigabe**.
- **Prüftiefe** je Gegenstand: **S** = ein Reviewer (Projektplan, Issue, Plan ohne `[K]`, normale
  Einheit, Zusammenfassung), **M** = Workflow mit ≤ 2 Linsen (Architektur, `[K]`), **L** = ≤ 4 Linsen +
  Mutation (im Plan markiert). Verifiziert werden nur Blocker, Verifizierer stufen nie hoch.
- **Keine Bestätigungsrunde (Claude Code):** Liefert eine Runde nur mittel/niedrig, werden diese eingearbeitet und
  nur ihr Diff per **Fixcheck** (ein Agent) geprüft; ein fehlerhafter Fix wird zurückgenommen.
  Folgerunden: Runde 1–2 voller Kaltreview, ab Runde 3 Delta; Runde 3 mit Blockern ⇒ Entscheidung des
  Menschen (Konvergenz-Stopp).
- **Offene Fragen** stehen am Ende und werden — soweit schon im Entwurf — **vor** dem ersten Review beantwortet.
- **Out of Scope** referenziert ein zukünftiges Issue _oder_ wird dauerhaft abgelehnt.
- **Kein Scope-Creep**; der Abschluss gleicht Issue ↔ (Architektur) ↔ Plan ↔ Umsetzung ab.
- **Kontext-Ökonomie:** Kontextpaket, Lese-Disziplin, Größenbudgets, frischer Implementierer je
  Einheit, eine Session je Einheit (Details in den Konventionen).
- Commits: `IS-<NNN>: <kurz>` je Planungsartefakt und je review-gesicherter Impl-Einheit.

Vollständige Regeln: [`share/konventionen.md`](share/konventionen.md) · Gate: [`share/review-gate.md`](share/review-gate.md).

**Gate-Absicherung:** Freigabe, offene Fragen und Projektfortschritt hängen an maschinell
prüfbaren Markern (`**Status:** Freigegeben`, `- [ ]`-Checkboxen, Projektplan-Status `erledigt`) —
siehe „Status- & Freigabe-Marker“ in den Konventionen. So kann der Orchestrator ein Gate nicht
aus Versehen überspringen. Da Claude-Code-Skills einander nur *empfehlen* (kein erzwungener Aufruf),
bleibt die letzte Sicherung deine Freigabe; wer die Gates härter erzwingen will, kann optional einen
`PreToolUse`-Hook ergänzen, der Commits ohne freigegebenes Artefakt blockt.

## Claude-Code-Agenten (Orchestrator + Sub-Agenten)

Der **Orchestrator** (`/naechster-schritt`, läuft in der Session) hält keinen schweren Kontext:
er erkennt nur den Stand und delegiert die Facharbeit an spezialisierte Sub-Agenten, die je
ihr eigenes Modell mitbringen. So bleibt das teure Modell dort, wo es zählt.

| Sub-Agent | Rolle | Modell / Effort | Warum |
|-----------|-------|-----------------|-------|
| `issue-autor`         | Issues schreiben (Experte → Einsteiger) | **sonnet** / medium | Strukturiertes Schreiben, günstig |
| `architekt`           | Architekturpläne, eindeutig | **opus** / xhigh | Hoher Einsatz, keine Mehrdeutigkeit |
| `impl-planer`         | Implementierungsplan | **sonnet** / high | Präzise Planung, gutes P/L |
| `implementierer`      | Code umsetzen | **sonnet** / medium | Masse der Arbeit → Opus-Kontingent schonen |
| `reviewer`            | Standard-Review | **sonnet** / high | Zweites Augenpaar, ≥ Implementierer |
| `reviewer-kritisch`   | Review riskanter Fälle | **opus** / high | `[K]`/Sicherheit/Daten, Kaltreview-Linsen, Verify — stärker als der Produzent |
| `reviewer-architektur`| Review von Architekturplänen | **opus** / xhigh | Gleicher Effort wie `architekt`, nie schwächer als der Erzeuger |
| `mutations-pruefer`   | Testwirksamkeit per temporärer Mutation | **opus** / xhigh | Läuft allein in eigener serieller Phase, stellt jede Datei byte-genau wieder her |
| `rechercheur`         | Fakten erheben (Repo/Web), Kontextpaket füllen | **sonnet** / high | Typisiert und günstig statt `general-purpose` mit Hauptmodell |
| `mechaniker`          | Abhaken + Commits | **haiku** / low | Reine Mechanik, kein Denkmodell nötig |

**Reviewer-Modell — bewusst gewählt:** Der Reviewer ist nie schwächer als der erzeugende Agent,
weder im Modell noch im Effort. Standard-Reviews laufen auf Sonnet (gleich stark wie der
Implementierer, aber unabhängig). `[K]`-Schritte und sicherheits-/datenkritischer Code eskalieren
automatisch auf `reviewer-kritisch` (**opus**/high), Architekturpläne auf `reviewer-architektur`
(**opus**/xhigh) — so rutscht bei den riskanten Stellen nichts durch. Haiku wird **nie** für
Reviews genutzt, nur für Mechanik. Die Prüfpunkte stehen direkt im Body der drei Reviewer-Agenten
(spart je Spawn einen Lese-Schritt); `share/review-checkliste.md` verweist nur noch dorthin. Jedes
Finding trägt ein wörtliches Zitat aus dem aktuellen Stand; Einstufungsregeln (freigegebene
Entscheidungen nicht neu verhandeln, fail-closed-Lücke höchstens mittel) bremsen Severity-Inflation.

Modell und Effort pro Agent stehen im Frontmatter der Datei unter `.claude/agents/` und lassen
sich frei anpassen (`model: opus|sonnet|haiku`, `effort: low|medium|high|xhigh`). Die Aliase
zeigen auf die jeweils aktuelle Modellversion. Läuft die Session selbst auf **Sonnet**, ist die
Orchestrierung günstig; `architekt` zieht bei Bedarf Opus.

**Workflow-Skripte** (Prüftiefe M/L) folgen den Mustern in
[`share/review-gate.md`](share/review-gate.md): jeder `agent()`-Aufruf braucht einen `agentType`
(sonst erbt der Spawn Hauptmodell, Effort und alle Tools), Findings werden vor dem Verify nur gebündelt
und erst nach dem Urteil dedupliziert, nur Blocker der Linse werden verifiziert (gebündelt nach Datei, zweite Stimme nur bei Widerlegung oder
Herabstufung unter hoch),
Verify-Prompts sind kompakt mit Lese-Budget, Rückgaben enthalten nur bestätigte Findings und Zähler.
Gemessen 09/2026 waren 85 % aller Workflow-Agenten Verify-Stimmen bei 3–10 % Widerlegungsquote.
Neue oder geänderte Agenten greifen erst nach einem Session-Neustart. Den Verbrauch je Agent, Modell,
Effort und Review-Serie misst [`share/tools/verbrauch_auswerten.py`](share/tools/README.md).

## Codex-Modellwahl

Die Codex-Quellen liegen unter [`codex/`](codex/) und werden nach `~/.codex/` installiert.
Der Standard der Hauptsitzung ist **GPT-6 Sol/high**, auch für normale Architektur; die
Rolle `implementierer` und Unteragenten ohne eigene Rolle nutzen Sol/medium, mechanische
Aufträge GPT-6 Luna/low. Issue-Texte, Dokumentationsnachzüge, Implementierungsplanung und
normale Kaltreviews nutzen gezielt GPT-5.6 Terra. GPT-6 Astra/xhigh ist kritischen
Architekturentscheidungen, Implementierungen und Reviews vorbehalten. Die Codex-Regeln
halten Aufgaben sequenziell und begrenzen Kontext, Delegation und wiederholte Prüfungen,
ohne fachliche Gates zu verkürzen. Für Codex gilt beim Reviewabschluss die eng begrenzte
Ausnahme in [`codex/AGENTS.md`](codex/AGENTS.md): Sobald eine Reviewrunde keine offenen
Kritisch/Hoch enthält, werden Mittel grundsätzlich minimal eingearbeitet (sonst mit Grund
und Ziel vertagt), Niedrig nach Ermessen. Danach gibt es kein weiteres Review und keinen
Fixcheck, auch wenn eine Projekt-`CLAUDE.md` wie in BreakMySystem.ai auf den Claude-Fixcheck
verweist. Nötige Tests und Pflicht-Gates nach Codefixes sowie menschliche Phasenfreigaben
gelten weiter. Reviewer- und Autor-Anweisungen stehen in [`codex/agents/`](codex/agents/),
die Skill-Einstiege in [`codex/skills/`](codex/skills/).

Änderungen an `codex/config.defaults.toml` werden beim nächsten `install.ps1` in eine
vorhandene Codex-Konfiguration übernommen. Änderungen an verlinkten Codex-Dateien wirken
direkt; bei Kopien den Installer erneut ausführen. Neue Modell- und Rollenwerte gelten
erst für neue Codex-Sitzungen und Agenten.

## Anpassen

- Claude-Regeln/Kategorien, Korrektur nach Review, Kontext-Ökonomie und Budgets: `share/konventionen.md`.
- Reviewer-Prüfpunkte: im Body von `reviewer`, `reviewer-kritisch` und `reviewer-architektur`
  sinngemäß gleich halten (Pflegehinweis in `share/review-checkliste.md`).
- Review-Gate (Prüftiefe, Abschluss ohne Bestätigungsrunde, Konvergenz-Stopp) und Workflow-Muster:
  `share/review-gate.md`.
- Dokumentaufbau: `share/vorlagen/*.md`.
- Codex-Modellrouting: `codex/AGENTS.md`, `codex/agents/` und `codex/config.defaults.toml`.
- Codex-Reviewabschluss: `codex/AGENTS.md`, `codex/agents/reviewer*.toml`, Autor-Rollen
  und `codex/skills/`; Claude- und geteilte Gate-Regeln bleiben davon unberührt.
- Nach dem Ändern von Dateinamen/Struktur `install.ps1` erneut ausführen.
