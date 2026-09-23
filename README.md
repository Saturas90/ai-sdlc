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
`~/.codex/ai-sdlc-backups/` gesichert. Zum Prüfen ohne Änderungen am Benutzerprofil:

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
issues/IS-<NNN>-<slug>/{issue,architektur,impl-plan,zusammenfassung}.md
```

## Regeln (Kurzfassung)

- Jedes Planungsartefakt durchläuft ein **Review-Gate** und wird iteriert, bis keine
  **kritisch/hoch**-Findings offen sind — erst dann **menschliche Freigabe**.
- **Offene Fragen** stehen am Ende und werden vor der nächsten Phase beantwortet.
- **Out of Scope** referenziert ein zukünftiges Issue _oder_ wird dauerhaft abgelehnt.
- **Kein Scope-Creep**; der Abschluss gleicht Issue ↔ (Architektur) ↔ Plan ↔ Umsetzung ab.
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
| `mechaniker`          | Abhaken + Commits | **haiku** / low | Reine Mechanik, kein Denkmodell nötig |

**Reviewer-Modell — bewusst gewählt:** Der Reviewer ist nie schwächer als der erzeugende Agent,
weder im Modell noch im Effort. Standard-Reviews laufen auf Sonnet (gleich stark wie der
Implementierer, aber unabhängig). `[K]`-Schritte und sicherheits-/datenkritischer Code eskalieren
automatisch auf `reviewer-kritisch` (**opus**/high), Architekturpläne auf `reviewer-architektur`
(**opus**/xhigh) — so rutscht bei den riskanten Stellen nichts durch. Haiku wird **nie** für
Reviews genutzt, nur für Mechanik. Die Prüfpunkte stehen direkt im Body der drei Reviewer-Agenten
(spart je Spawn einen Lese-Schritt); `share/review-checkliste.md` verweist nur noch dorthin.

Modell und Effort pro Agent stehen im Frontmatter der Datei unter `.claude/agents/` und lassen
sich frei anpassen (`model: opus|sonnet|haiku`, `effort: low|medium|high|xhigh`). Die Aliase
zeigen auf die jeweils aktuelle Modellversion. Läuft die Session selbst auf **Sonnet**, ist die
Orchestrierung günstig; `architekt` zieht bei Bedarf Opus.

**Workflow-Skripte** (Review, Verify, Widerlegen, Mutation) folgen den Mustern in
[`share/review-gate.md`](share/review-gate.md): jeder `agent()`-Aufruf braucht einen `agentType`
(sonst erbt der Spawn Hauptmodell, Effort und alle Tools), Niedrig-Findings werden gebündelt
geprüft, Stimmen laufen nacheinander mit Frühabbruch, ab Runde 5 gilt ein Linsen-Deckel. Neue oder
geänderte Agenten greifen erst nach einem Session-Neustart. Den Verbrauch je Agent, Modell und
Effort misst [`share/tools/verbrauch_auswerten.py`](share/tools/README.md).

## Codex-Modellwahl

Die Codex-Quellen liegen unter [`codex/`](codex/) und werden nach `~/.codex/`
installiert. Der Standard ist **GPT-6 Sol/medium**. Normale Architektur nutzt Sol/high,
mechanische Aufträge GPT-6 Luna/low. Issue-Texte, Dokumentationsnachzüge,
Implementierungsplanung und normale Kaltreviews nutzen gezielt GPT-5.6 Terra.
GPT-6 Astra/xhigh ist kritischen Architekturentscheidungen, Implementierungen und
Reviews vorbehalten. Die Codex-Regeln halten Aufgaben sequenziell und begrenzen Kontext,
Delegation und wiederholte Prüfungen, ohne fachliche Gates zu verkürzen.

Änderungen an `codex/config.defaults.toml` werden beim nächsten `install.ps1` in eine
vorhandene Codex-Konfiguration übernommen. Änderungen an verlinkten Codex-Dateien wirken
direkt; bei Kopien den Installer erneut ausführen. Neue Modell- und Rollenwerte gelten
erst für neue Codex-Sitzungen und Agenten.

## Anpassen

- Claude-Regeln/Kategorien: `share/konventionen.md`.
- Reviewer-Prüfpunkte: im Body von `reviewer`, `reviewer-kritisch` und `reviewer-architektur`
  sinngemäß gleich halten (Pflegehinweis in `share/review-checkliste.md`).
- Review-Gate und Workflow-Muster: `share/review-gate.md`.
- Dokumentaufbau: `share/vorlagen/*.md`.
- Codex-Modellrouting: `codex/AGENTS.md`, `codex/agents/` und `codex/config.defaults.toml`.
- Nach dem Ändern von Dateinamen/Struktur `install.ps1` erneut ausführen.
