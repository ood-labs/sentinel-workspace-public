"""Review SIMPLE STAGE looks on the live rig through the Surface's rig_command seam.

Talks to a running Sentinel over its bundled MCP server (stdio), recalls looks exactly as the desk does, and writes
stills to captures/looks/ (gitignored).

    python tools/ss_review.py recall complete 1              recall one look, print the ack
    python tools/ss_review.py steady                         paste neutral effect rows (no lanes, no motion, tubes
                                                             dark, plates glowing) for repeatable frames
    python tools/ss_review.py sheet static 1-16              a labelled contact sheet of a bank, one still per pad
    python tools/ss_review.py strip effects 13-16            filmstrips: frames at --times seconds after each recall,
                                                             one row per pad
    python tools/ss_review.py sheet color 1-16 --pre "preset|recall|static|1;steady"
                                                             run commands first (any rig_command; `steady` pastes)

Judge effects over one fixed base (a STATIC, a COLOR) so only the effect changes. A paused clock darkens every
lane-driven fixture, so keep it running. Movers slew: give a position change about 2 s before a still. Fast pulses
alias against a slow frame interval; sample densely (--times) before calling a look dark.

The MCP server comes from the workspace's own .mcp.json; set SENTINEL_MCP to override it.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATE = "/sentinel/pipelines/SS_Surface/state/"
OUT = ROOT / "captures" / "looks"


def server() -> str:
    if os.environ.get("SENTINEL_MCP"):
        return os.environ["SENTINEL_MCP"]
    config = json.loads((ROOT.parents[1] / ".mcp.json").read_text(encoding="utf-8"))
    return config["mcpServers"]["sentinel-mcp"]["command"]


class Mcp:
    """One MCP session for the whole run (a capture sheet is dozens of calls)."""

    def __init__(self):
        self.p = subprocess.Popen([server()], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                  text=True, encoding="utf-8", bufsize=1)
        self.n = 0
        self.request("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                                    "clientInfo": {"name": "ss_review", "version": "1"}})
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        self.p.stdin.flush()

    def request(self, method, params):
        self.n += 1
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params}) + "\n")
        self.p.stdin.flush()
        while True:
            line = self.p.stdout.readline()
            if not line:
                raise RuntimeError("sentinel-mcp closed")
            try:
                value = json.loads(line)
            except ValueError:
                continue
            if value.get("id") == self.n:
                return value

    def call(self, tool, args):
        text = self.request("tools/call", {"name": tool, "arguments": args})["result"]["content"][0]["text"]
        try:
            return json.loads(text)
        except ValueError:
            return {"raw": text}

    def get(self, path):
        r = self.call("sentinel_state", {"action": "get", "path": path})
        return r.get("value", r)

    def set(self, path, value):
        return self.call("sentinel_state", {"action": "set", "path": path, "value": value})

    def close(self):
        self.p.kill()


def command(m: Mcp, text: str, timeout: float = 8.0) -> str:
    """One rig_command, waiting for its ack (the Surface handles only the latest string)."""
    tag = f"r{int(time.time() * 1000) % 1000000}"
    m.set(STATE + "rig_command", f"{tag}|{text}")
    t0 = time.time()
    while time.time() - t0 < timeout:
        ack = m.get(STATE + "rig_command_ack")
        if isinstance(ack, str) and ack.startswith(tag + ":"):
            return ack[len(tag) + 1:]
        time.sleep(.1)
    return "TIMEOUT"


def steady(m: Mcp):
    """Neutral effect rows for every partition, pasted live (undoable, not stored)."""
    sys.path.insert(0, str(ROOT / "tools"))
    import ss_show as S
    for key, text in S.effects_snapshot(S.effect_rows({})).items():
        print("steady", key.rsplit("_", 1)[-1], command(m, f"rows|effects|{key.rsplit('_', 1)[-1]}|{text}"))


def titles():
    text = (ROOT / "scripts" / "show" / "preset_titles.luau").read_text(encoding="utf-8")
    return {k: re.findall(r'"([^"]*)"', v) for k, v in re.findall(r"(\w+)=\{([^}]*)\}", text)}


def slots(spec):
    out = []
    for part in spec.split(","):
        a, _, b = part.partition("-")
        out += list(range(int(a), int(b or a) + 1))
    return out


def grab(m: Mcp, path: Path, width: int) -> Path:
    m.call("sentinel_capture", {"action": "capture_at", "pipeline_id": "SS_Renderer", "overrides": {},
                                "max_width": width, "filepath": str(path), "settle_frames": 1})
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["recall", "steady", "sheet", "strip"])
    ap.add_argument("kind", nargs="?", default="complete")
    ap.add_argument("slots", nargs="?", default="1-16")
    ap.add_argument("--wait", type=float, default=1.5, help="sheet: seconds after the recall")
    ap.add_argument("--times", default="0.5,1.5,2.5,3.5,4.5,5.5", help="strip: seconds after each recall")
    ap.add_argument("--width", type=int, default=480)
    ap.add_argument("--pre", default="", help="commands to run first, ';'-separated ('steady' pastes)")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    m = Mcp()
    try:
        if a.mode == "recall":
            print(command(m, f"preset|recall|{a.kind}|{a.slots}"))
            return
        if a.mode == "steady":
            steady(m)
            return
        from PIL import Image, ImageDraw
        for c in [c for c in a.pre.split(";") if c]:
            steady(m) if c == "steady" else print(c, command(m, c))
            time.sleep(1.0)
        OUT.mkdir(parents=True, exist_ok=True)
        names = titles().get(a.kind, [])
        rows = []
        for s in slots(a.slots):
            ack = command(m, f"preset|recall|{a.kind}|{s}")
            t0 = time.time()
            frames = []
            for i, t in enumerate([a.wait] if a.mode == "sheet" else [float(v) for v in a.times.split(",")]):
                while time.time() - t0 < t:
                    time.sleep(.02)
                frames.append(grab(m, OUT / f"{a.kind}_{s}_{i}.png", a.width))
            rows.append((f"{a.kind} {s} {names[s - 1] if s <= len(names) else ''} [{ack}]", frames))
        ims = [[Image.open(f).convert("RGB") for f in fr] for _, fr in rows]
        w, h = ims[0][0].size
        if a.mode == "sheet":
            cols = 4
            sheet = Image.new("RGB", (cols * w, ((len(ims) + cols - 1) // cols) * h))
            cells = [(i % cols, i // cols, lab, row[0]) for i, ((lab, _), row) in enumerate(zip(rows, ims))]
        else:
            sheet = Image.new("RGB", (max(len(r) for r in ims) * w, len(ims) * h))
            cells = [(c, r, lab if c == 0 else "", im) for r, ((lab, _), row) in enumerate(zip(rows, ims))
                     for c, im in enumerate(row)]
        for c, r, lab, im in cells:
            if lab:
                d = ImageDraw.Draw(im)
                d.rectangle([0, 0, 8 + 7 * len(lab), 16], fill=(0, 0, 0))
                d.text((4, 2), lab, fill=(255, 200, 80))
            sheet.paste(im, (c * w, r * h))
        out = OUT / ((a.out or f"{a.mode}_{a.kind}") + ".jpg")
        sheet.save(out, quality=88)
        print(out)
    finally:
        m.close()


if __name__ == "__main__":
    main()
