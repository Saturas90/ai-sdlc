---
name: implementieren
description: Arbeitet den freigegebenen Implementierungsplan schrittweise ab. Bündelt einfache Schritte, führt [K]-Schritte einzeln aus, sichert jede Einheit per Review (Prüftiefe je Schritt) ab, hakt sie im Plan ab und committet mit Issue-Nummer.
---

# Skill: Implementierung

Voraussetzung: `impl-plan.md` freigegeben. Eine Session je Einheit ist günstiger als eine lange Session
(„Kontext-Ökonomie“ in `~/.claude/ai-sdlc/konventionen.md`).

Schleife über die offenen `[ ]`-Schritte:

1. **Einheit wählen:** einfache Schritte dürfen gebündelt werden; `[K]`-Schritte einzeln.
2. **Umsetzen:** je Einheit einen **frischen** Sub-Agenten **`implementierer`** (Modell: sonnet) spawnen; Übergabe: Schritt-IDs, Pfade von `impl-plan.md` und `kontext.md`. Triviale Einheiten (eine Datei, keine Logikänderung) direkt erledigen. Nur was im Impl-Plan/Issue steht — kein Scope-Creep.
3. **Review-Gate** auf den Diff der Einheit anwenden (`~/.claude/ai-sdlc/review-gate.md`): normale Einheit → Prüftiefe S mit `reviewer`, sicherheits-/datenkritischer Code auch ohne Marker mit `reviewer-kritisch`; `[K]` → M, `Prüftiefe: L` → L (`reviewer-kritisch`). Kritisch/hoch → derselbe Implementierer behebt mit den deduplizierten Findings (höchstens zwei Fortsetzungen, dann frisch) → nächste Runde. Runde mit nur mittel/niedrig → einarbeiten, Fixcheck, ggf. Rücknahmen, danach Tests und Gate-Kette grün — keine weitere Runde. Kein Human-Gate pro Schritt; Konvergenz-Stopp ab Runde 3.
4. **Stand** in `kontext.md` (bzw. die dort verwiesene projekteigene Übergabe) überschreiben (nächster Schritt, offene Entscheidungen) und Vertagtes eintragen; ist die Session groß, neue Session für die nächste Einheit vorschlagen.
5. **Abhaken + Commit** an `mechaniker` (haiku) delegieren: erledigte Schritte in `impl-plan.md` auf `[x]` setzen und `IS-<NNN>: <was getan wurde>` committen (mit `kontext.md` bzw. der projekteigenen Übergabe, sofern versioniert).

Wenn alle Schritte `[x]`: `/abschluss`.
