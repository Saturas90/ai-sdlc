---
name: implementieren
description: Arbeitet den freigegebenen Implementierungsplan schrittweise ab. Bündelt einfache Schritte, führt [K]-Schritte einzeln aus, sichert jede Einheit per Review ab, hakt sie im Plan ab und committet mit Issue-Nummer.
---

# Skill: Implementierung

Voraussetzung: `impl-plan.md` freigegeben.

Schleife über die offenen `[ ]`-Schritte:

1. **Einheit wählen:** einfache Schritte dürfen gebündelt werden; `[K]`-Schritte einzeln.
2. **Umsetzen:** die eigentliche Code-Arbeit an den Sub-Agenten **`implementierer`** (Modell: sonnet) delegieren; triviale Einheiten direkt erledigen. Nur was im Impl-Plan/Issue steht — kein Scope-Creep.
3. **Review-Gate** auf den Diff der Einheit anwenden (`~/.claude/ai-sdlc/review-gate.md`): normale Einheit → `reviewer` (sonnet); `[K]`-Schritt oder sicherheits-/datenkritischer Code → `reviewer-kritisch` (opus). Kritisch/hoch → gezielt beheben → erneut prüfen. Kein Human-Gate pro Schritt.
4. **Abhaken + Commit** an `mechaniker` (haiku) delegieren: erledigte Schritte in `impl-plan.md` auf `[x]` setzen und `IS-<NNN>: <was getan wurde>` committen.

Wenn alle Schritte `[x]`: `/abschluss`.
