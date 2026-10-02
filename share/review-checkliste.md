# Review-Checkliste

Die Checkliste steht direkt im Body der Reviewer-Agenten (spart je Spawn einen Lese-Schritt).
Wirst du als Reviewer auf diese Datei verwiesen, lies den Body deines Agenten ab dem Ende des Frontmatters
und wende dessen Prüfpunkte und Rückgabevertrag an (einschließlich Zitat-Pflicht und `Blockierend: ja/nein`):
`reviewer` → `~/.claude/agents/reviewer.md`, Architekturplan → `~/.claude/agents/reviewer-architektur.md`,
sonst → `~/.claude/agents/reviewer-kritisch.md`.

Pflege: Änderungen sinngemäß in allen drei Reviewer-Agenten nachziehen — Prüfpunkte, Einstufungsregeln,
Absatz „Lesen“ (Prüfpaket, Folgerunde, Fixcheck, Verify-Stimme) und Rückgabevertrag; `reviewer-architektur`
weicht bei Bezugsdokumenten und Code-Bezug bewusst ab. Den Blockierend-Wortlaut auch in
`mutations-pruefer.md` gleich halten. Ablauf, Prüftiefe und Workflow-Muster stehen in `review-gate.md`.
