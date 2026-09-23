"""Wertet den Token-Verbrauch aus Claude-Code-Transkripten aus (Hauptsession, Subagenten, Workflows).

Aufruf (Git-Bash, im Projektverzeichnis oder mit --projekt):
    PYTHONUTF8=1 python ~/.claude/ai-sdlc/tools/verbrauch_auswerten.py [--seit 2026-09-23] [--bis 2026-09-30]
        [--projekt <ordnername unter ~/.claude/projects>]

Kosten sind API-Äquivalent (Listenpreise), kein Abo-Verbrauch; sie dienen nur als Vergleichsmaß.
"""

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

# $/MTok: input, output, cache_read; cache write 5m = 1,25x input, 1h = 2x input
PREISE = {
    "claude-fable-5-1": (10.0, 50.0, 0.25),
    "claude-fable-5": (10.0, 50.0, 1.0),
    "claude-opus-5-5": (4.0, 20.0, 0.20),
    "claude-opus-5": (5.0, 25.0, 0.50),
    "claude-opus-4-8": (5.0, 25.0, 0.50),
    "claude-sonnet-5": (2.0, 10.0, 0.20),
    "claude-sonnet-4-6": (3.0, 15.0, 0.30),
    "claude-haiku-4-5": (1.0, 5.0, 0.10),
}


def preis_schluessel(modell):
    m = (modell or "").split("[")[0]
    for k in sorted(PREISE, key=len, reverse=True):
        if m.startswith(k):
            return k
    return None


def kosten(modell, u):
    k = preis_schluessel(modell)
    if k is None:
        return {"input": 0.0, "cwrite": 0.0, "cread": 0.0, "output": 0.0}
    pin, pout, pread = PREISE[k]
    cc = u.get("cache_creation") or {}
    c5 = cc.get("ephemeral_5m_input_tokens")
    c1 = cc.get("ephemeral_1h_input_tokens")
    if c5 is None and c1 is None:
        c5, c1 = u.get("cache_creation_input_tokens", 0) or 0, 0
    return {
        "input": (u.get("input_tokens", 0) or 0) * pin / 1e6,
        "cwrite": ((c5 or 0) * pin * 1.25 + (c1 or 0) * pin * 2.0) / 1e6,
        "cread": (u.get("cache_read_input_tokens", 0) or 0) * pread / 1e6,
        "output": (u.get("output_tokens", 0) or 0) * pout / 1e6,
    }


def requests_lesen(pfad, seit, bis):
    """Je API-Request (dedupliziert per requestId): model, effort, usage, ts."""
    reqs = {}
    with open(pfad, encoding="utf-8", errors="replace") as fh:
        for zeile in fh:
            if '"type":"assistant"' not in zeile:
                continue
            try:
                d = json.loads(zeile)
            except ValueError:
                continue
            msg = d.get("message") or {}
            u = msg.get("usage")
            ts = d.get("timestamp") or ""
            if not u or d.get("type") != "assistant":
                continue
            if (seit and ts < seit) or (bis and ts >= bis):
                continue
            reqs[d.get("requestId") or d.get("uuid")] = {
                "model": msg.get("model"), "effort": d.get("effort"), "usage": u, "ts": ts,
            }
    return list(reqs.values())


def einordnen(pfad, wurzel):
    teile = pfad.relative_to(wurzel).parts
    if len(teile) == 1:
        return "MAIN", {}
    meta = Path(str(pfad)[: -len(".jsonl")] + ".meta.json")
    info = {}
    if meta.exists():
        try:
            info = json.loads(meta.read_text(encoding="utf-8"))
        except ValueError:
            info = {}
    im_wf = "workflows" in teile
    typ = info.get("agentType") or ("workflow-default" if im_wf else "unbekannt")
    return ("workflow:" if im_wf else "agent:") + typ, info


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    # Claude Code benennt Projektordner nach dem Pfad, jedes Zeichen außer A-Z/a-z/0-9 wird zu "-"
    ap.add_argument("--projekt", default=re.sub(r"[^A-Za-z0-9]", "-", str(Path.cwd())),
                    help="Ordner unter ~/.claude/projects (Standard: aus dem aktuellen Verzeichnis)")
    ap.add_argument("--seit", default="", help="ISO-Datum inklusive, z. B. 2026-09-23")
    ap.add_argument("--bis", default="", help="ISO-Datum exklusive")
    a = ap.parse_args()
    wurzel = Path.home() / ".claude" / "projects" / a.projekt
    if not wurzel.is_dir():
        sys.exit(f"Projektordner nicht gefunden: {wurzel} (mit --projekt angeben)")

    agg = defaultdict(lambda: defaultdict(float))
    komp = defaultdict(lambda: defaultdict(float))
    modelle = defaultdict(Counter)
    efforts = defaultdict(Counter)
    erster_prompt = defaultdict(list)
    turns = defaultdict(list)
    rk_phasen = Counter()
    haupt_kontext = []
    ts_min, ts_max = None, None
    dateien = list(wurzel.glob("*.jsonl")) + list(wurzel.glob("*/subagents/**/agent-*.jsonl"))
    for p in dateien:
        bucket, info = einordnen(p, wurzel)
        reqs = requests_lesen(p, a.seit, a.bis)
        if not reqs:
            continue
        for r in reqs:
            u = r["usage"]
            c = kosten(r["model"], u)
            for n, v in c.items():
                komp[bucket][n] += v
            g = agg[bucket]
            g["requests"] += 1
            g["output"] += u.get("output_tokens", 0) or 0
            g["cread"] += u.get("cache_read_input_tokens", 0) or 0
            g["cwrite"] += u.get("cache_creation_input_tokens", 0) or 0
            g["kosten"] += sum(c.values())
            modelle[bucket][str(r["model"])] += 1
            efforts[bucket][str(r["effort"])] += 1
            ts_min = r["ts"] if ts_min is None or r["ts"] < ts_min else ts_min
            ts_max = r["ts"] if ts_max is None or r["ts"] > ts_max else ts_max
            if bucket == "MAIN":
                kontext = sum((u.get(k, 0) or 0) for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
                haupt_kontext.append((kontext, sum(c.values())))
        if bucket != "MAIN":
            agg[bucket]["spawns"] += 1
            u0 = reqs[0]["usage"]
            erster_prompt[bucket].append(sum((u0.get(k, 0) or 0) for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")))
            turns[bucket].append(len(reqs))
            if bucket.endswith("reviewer-kritisch"):
                rk_phasen[info.get("workflowPhase") or "-"] += 1

    gesamt = sum(g["kosten"] for g in agg.values()) or 1.0
    print(f"Zeitraum: {ts_min} .. {ts_max} | Projekt: {a.projekt}")
    print(f"Gesamt API-Aequivalent: ${gesamt:,.2f}\n")
    print(f"{'Bucket':36} {'Spawns':>6} {'Req':>6} {'Out MTok':>9} {'CRead MTok':>10} {'$':>9} {'%':>5} {'1.Prompt':>8} {'Turns':>6}")
    for b, g in sorted(agg.items(), key=lambda kv: -kv[1]["kosten"]):
        fp = sum(erster_prompt[b]) / len(erster_prompt[b]) if erster_prompt[b] else 0
        tn = sum(turns[b]) / len(turns[b]) if turns[b] else 0
        print(f"{b:36} {int(g['spawns']):>6} {int(g['requests']):>6} {g['output']/1e6:>9.2f} {g['cread']/1e6:>10.1f} "
              f"{g['kosten']:>9.2f} {100*g['kosten']/gesamt:>5.1f} {fp:>8.0f} {tn:>6.1f}")

    print("\nKostenkomponenten je Bucket ($): input / cache-write / cache-read / output")
    for b, c in sorted(komp.items(), key=lambda kv: -sum(kv[1].values()))[:10]:
        print(f"  {b:34} {c['input']:>7.0f} {c['cwrite']:>8.0f} {c['cread']:>8.0f} {c['output']:>8.0f}")

    print("\nModelle und Effort je Bucket (Requests):")
    for b in sorted(modelle, key=lambda k: -agg[k]["kosten"]):
        print(f"  {b}: {dict(modelle[b])} | effort {dict(efforts[b])}")

    print("\nreviewer-kritisch je Workflow-Phase (Spawns, Top 15):")
    for ph, n in rk_phasen.most_common(15):
        print(f"  {n:5}  {ph}")

    print("\nHauptsession: Kosten nach Kontextgröße je Request")
    tk = sum(c for _, c in haupt_kontext) or 1.0
    for lo, hi in [(0, 100e3), (100e3, 200e3), (200e3, 300e3), (300e3, 500e3), (500e3, 2e6)]:
        sel = [(x, c) for x, c in haupt_kontext if lo <= x < hi]
        cs = sum(c for _, c in sel)
        print(f"  {int(lo/1e3):>4}-{int(hi/1e3):>4}K: {len(sel):5} Req  ${cs:8.0f}  ({100*cs/tk:4.1f}%)")


if __name__ == "__main__":
    main()
