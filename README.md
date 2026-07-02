# ai-sdlc

Ein dateibasiertes **SDLC-Toolkit für Claude Code**: Es bildet deinen Ablauf
*Projektplan → Issue → (Architektur) → Implementierungsplan → Implementierung → Abschluss*
mit Review-Gates, menschlichen Freigaben und Commits ab — als kleine, token­arme Skills
und spezialisierte Sub-Agenten. Alle Artefakte sind Markdown im jeweiligen Projekt-Repo.

## Installation (einmalig)

```powershell
cd <pfad-zu-diesem-repo>    # dorthin, wo du ai-sdlc abgelegt/geklont hast
./install.ps1              # Symlinks nach ~/.claude  (Fallback: kopieren; ./install.ps1 -Copy erzwingt Kopie)
```

Danach sind die Skills in **jedem** Projekt verfügbar. Symlinks brauchen Admin-Rechte
_oder_ den Windows-Entwicklermodus (Einstellungen → System → Für Entwickler).

## Nutzung im Zielprojekt

Wechsle in dein Tool-Projekt (Git-Repo) und lass dich vom Orchestrator führen:

```
/naechster-schritt        # erkennt den Stand und startet die passende Phase
```

Oder eine Phase direkt aufrufen:

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

## Architektur des Toolkits (Orchestrator + Sub-Agenten)

Der **Orchestrator** (`/naechster-schritt`, läuft in der Session) hält keinen schweren Kontext:
er erkennt nur den Stand und delegiert die Facharbeit an spezialisierte Sub-Agenten, die je
ihr eigenes Modell mitbringen. So bleibt das teure Modell dort, wo es zählt.

| Sub-Agent | Rolle | Empf. Modell | Warum |
|-----------|-------|--------------|-------|
| `issue-autor`      | Issues schreiben (Experte → Einsteiger) | **sonnet** | Strukturiertes Schreiben, günstig |
| `architekt`        | Architekturpläne, eindeutig | **opus** | Hoher Einsatz, keine Mehrdeutigkeit |
| `impl-planer`      | Implementierungsplan | **sonnet** | Präzise Planung, gutes P/L |
| `implementierer`   | Code umsetzen | **sonnet** | Masse der Arbeit → Opus-Kontingent schonen |
| `reviewer`         | Standard-Review | **sonnet** | Zweites Augenpaar, ≥ Implementierer |
| `reviewer-kritisch`| Review riskanter Fälle | **opus** | Architektur/`[K]`/Sicherheit — stärker als der Produzent |
| `mechaniker`       | Abhaken + Commits | **haiku** | Reine Mechanik, kein Denkmodell nötig |

**Reviewer-Modell — bewusst gewählt:** Der Reviewer ist nie schwächer als der erzeugende Agent.
Standard-Reviews laufen auf Sonnet (gleich stark wie der Implementierer, aber unabhängig). Für
Architekturpläne, `[K]`-Schritte und sicherheits-/datenkritischen Code eskaliert das Gate
automatisch auf `reviewer-kritisch` (**opus**) — so rutscht bei den riskanten Stellen nichts durch.
Haiku wird **nie** für Reviews genutzt, nur für Mechanik.

Modell pro Agent steht im Frontmatter der Datei unter `.claude/agents/` und lässt sich
frei anpassen (`model: opus|sonnet|haiku`). Läuft die Session selbst auf **Sonnet**, ist die
Orchestrierung günstig; `architekt` zieht bei Bedarf Opus.

## Anpassen

- Regeln/Kategorien: nur `share/konventionen.md`.
- Dokumentaufbau: `share/vorlagen/*.md`.
- Nach dem Ändern von Dateinamen/Struktur `install.ps1` erneut ausführen.
