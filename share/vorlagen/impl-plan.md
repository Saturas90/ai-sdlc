# IS-<NNN> — Implementierungsplan

> Verfasst von einem Expert-Entwickler: präzise, knapp, ohne Interpretationsspielraum.

**Status:** Entwurf
<!-- Erst nach menschlicher Freigabe zu "**Status:** Freigegeben" ändern. -->

## Voraussetzungen
<Was muss vorliegen (Freigaben, Abhängigkeiten).>

## Schritte
Jeder Schritt ist einzeln überprüfbar. `[K]` = komplex ⇒ einzeln ausführen, Review mit Prüftiefe M.
`Prüftiefe: L (<Grund>)` nur bei Sicherheit, Datenverlust, Migration oder Recovery; schließt `[K]` ein.
`Kontext:` nennt, was der Implementierer lesen muss — Symbole mit Datei:Zeile und Ist-Signatur,
Aufrufer/Fakes mit Datei:Zeile; lange Karten stehen in `kontext.md` › Schrittkarten.

- [ ] S1: <Aktion · erwartetes Ergebnis>
  - Dateien: <ändern / neu / löschen>
  - Kontext: <Symbol — Datei:Zeile; Aufrufer — Datei:Zeile>
  - Tests: <Testdateien · gezielter Befehl>
- [ ] S2 [K]: <…>
- [ ] S3 [K] · Prüftiefe: L (<Grund>): <…>

## Test-/Verifikationsstrategie
<Wie wird jeder Schritt / das Ganze verifiziert. Schnell-Gate je Einheit als ein Aufruf mit begrenzter
Ausgabe, z. B. `<formatter> <dateien> && <linter> <dateien> && <typecheck> <dateien> && <tests> | tail -n 30`.>

## Offene Fragen
<Nur falls vorhanden; sonst diesen Abschnitt löschen. Jede Frage als Checkbox; vor der nächsten Phase beantwortet (`- [x]` + Antwort).>
- [ ] <Frage>
