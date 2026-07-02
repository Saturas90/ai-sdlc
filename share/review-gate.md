# Review-Gate — Ablauf

Von jeder Phase verwendet. Kategorien-Definitionen: siehe `konventionen.md`.

**Eingabe:** das zu prüfende Artefakt (oder der Diff eines Impl-Schritts) + Kontext
(Issue, ggf. Architektur/Impl-Plan).

1. **Review** — passenden Reviewer wählen und spawnen. Liefert Findings, je mit
   `Kategorie | Fundstelle | Problem | Vorschlag` + „Blockierend: ja/nein“.
   - **Standard** (Issue, Projektplan, Impl-Plan, normale Impl-Schritte) → `reviewer` (sonnet).
   - **Kritisch** (Architekturplan, `[K]`-Schritt, sicherheits-/datenkritischer Code) → `reviewer-kritisch` (opus).
   - Reviewer ist immer ≥ dem erzeugenden Agenten. Nie schwächer reviewen als produziert wurde.
2. **Bewerten:**
   - ≥1 **kritisch/hoch** offen → nur diese Findings an den erzeugenden Agenten
     (issue-autor / architekt / impl-planer / implementierer) zur **gezielten** Überarbeitung
     zurückgeben, dann zurück zu Schritt 1. Das Artefakt **nicht** komplett neu erzeugen.
   - Nur noch **mittel/niedrig** → Gate erfüllt.
3. **Menschliche Freigabe** (nur Planungsartefakte): offene mittel/niedrig-Findings kurz
   auflisten, dann um explizite Freigabe bitten. Erst nach „freigegeben“ weiter.
4. **Impl-Schritt-Reviews:** kein Human-Gate pro Schritt. Nach erfülltem Gate abhaken + committen
   (an `mechaniker` (haiku) delegieren).

**Kosten:** Der Reviewer ist ein eigenständiges „zweites Augenpaar“ — Standard Sonnet, riskante
Fälle Opus. Überarbeitungsrunden nur mit den offenen kritisch/hoch-Findings anstoßen, nicht das
ganze Artefakt neu erzeugen.
