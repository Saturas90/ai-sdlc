# IS-<NNN> — Kontext

> Arbeitsdatei, kein Freigabe-Artefakt: keine Statuszeile, kein Review-Gate. Einstieg für **jeden**
> Agenten dieses Issues — erst diese Datei, dann die genannten Anker plus gezielte Suchen; Reviewer begrenzt
> sie nicht. Budget ≤ 8 KB. Wer weitere relevante Stellen findet, ergänzt sie hier (eine Zeile, mit Anker),
> statt sie den nächsten Agenten erneut suchen zu lassen.

## Relevante Stellen
| Anker | Warum relevant |
|-------|----------------|
| `<pfad/datei.py>:<Klasse.methode>` (Z. <n>) | <ein Halbsatz> |
| `<docs/norm.md>#<abschnitt>` (Z. <von>–<bis>) | <ein Halbsatz> |

## Normen & Entscheidungen
- <Constraint/ADR/Regel, Quelle:Zeilen> — <tragender Satz wörtlich oder Kern in einem Satz; nur was dieses Issue berührt>

## Schrittkarten
<Optional, vom impl-planer: je Plan-Schritt, wenn die Angaben für den Plan zu lang sind.>
- S<n>: <Symbol — Datei:Zeile, Ist-Signatur> · Aufrufer/Fakes: <Datei:Zeile> · Tests: <Dateien>

## Tests & Prüfbefehle
- Gezielt: `<befehl für die betroffenen Tests>`
- Gate-Kette (einmal je Einheit vor dem Commit): `<befehl>`

## Bewusst nicht relevant
- <Bereich/Dokument> — <warum nicht lesen>

## Vertagt
<Hauptsession: je vertagtem Mittel/Niedrig-Finding eine Zeile — Phase, Finding (Datei:Zeile, ein Satz),
Ziel (Folge-Issue oder dauerhaft abgelehnt). Blocker stehen hier nur nach Entscheidung des Menschen. Der
Abschluss übernimmt die Liste in die Zusammenfassung. Wird bei vollem Budget nie gekürzt.>

## Stand
<Nur die Hauptsession, ≤ 1 KB, wird bei vollem Budget nie gekürzt. Vor jedem Commit überschreiben und
mitcommitten: nächster Schritt, offene Entscheidungen. Mitten im Gate am Ende jeder Runde und vor dem
Fixcheck: Gegenstand, Prüftiefe, Runde, Gate-Schritt (Review / Korrektur / Fixcheck), offene Findings
(Tabelle oder Verweis auf eine Datei in der Gate-Ablage, Standard `.gate-logs/<issue>/`), Unterordner der
jüngsten Sicherung, ggf. die Stufen-Abbildung. Hat das Projekt eine eigene Übergabe-Ablage, steht hier nur
der Verweis darauf.>
