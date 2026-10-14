"""Record and compare what every shipped look does, for regression checks on the show system.

Recalls all 64 pads on the live rig through the Surface's rig_command seam (as the desk does), with Phage_Show
frozen so the lanes, palettes and strobe clock hold still, and records per look the programmer rows (Phage_Program's
Fixture Program port), all 57 universes of DMX (Phage_Lighting) and the truss axes (Phage_Kinetics Axis State).

    python tools/phage_baseline.py capture v0                 record captures/baseline/v0.npz (about 8 minutes)
    python tools/phage_baseline.py compare v0 v0b             differences between two records, per look
    python tools/phage_baseline.py compare v0 v1 --noise v0b  ... and only what exceeds v0 vs v0b
    python tools/phage_baseline.py ab l0                      per look, the DMX with layered 0 against 1 (exact)

A partial look is recalled on top of FULL LOOK 01 each time, so every record starts from the same rig. Run
`capture` twice on the same build to measure the run-to-run floor: a spinning capsid and the pixel patterns drawn in
world space keep moving with the show frozen, so their DMX differs between runs anyway. Phage_Show is unfrozen
afterwards, even after an error; the project must never be saved with it frozen.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "captures" / "baseline"
STATE = "/sentinel/pipelines/Phage_Surface/state/"
COMMIT = "/sentinel/pipelines/Phage_Program/parameters/commit_revision"
LAYERED = "/sentinel/pipelines/Phage_Program/parameters/layered"
KINDS = ("complete", "static", "effects", "color")
PROGRAM_FIELDS = ("aim", "routing", "movement", "timing", "meta", "extra")


class Mcp:
    """One persistent sentinel-mcp session (stdio JSON-RPC)."""

    def __init__(self):
        command = os.environ.get("SENTINEL_MCP") or json.loads(
            (ROOT.parents[1] / ".mcp.json").read_text(encoding="utf-8"))["mcpServers"]["sentinel-mcp"]["command"]
        self.p = subprocess.Popen([command], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                  text=True, encoding="utf-8", bufsize=1)
        self.next = 1
        self.request("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                                    "clientInfo": {"name": "phage_baseline", "version": "1"}})
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        self.p.stdin.flush()

    def request(self, method, params):
        rid = self.next
        self.next += 1
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": rid, "method": method, "params": params}) + "\n")
        self.p.stdin.flush()
        while True:
            line = self.p.stdout.readline()
            if not line:
                raise RuntimeError("sentinel-mcp closed")
            try:
                value = json.loads(line)
            except ValueError:
                continue
            if value.get("id") == rid:
                return value

    def call(self, tool, args):
        result = self.request("tools/call", {"name": tool, "arguments": args})
        text = result["result"]["content"][0]["text"]
        try:
            return json.loads(text)
        except ValueError:
            return {"raw": text}

    def get(self, path):
        result = self.call("sentinel_state", {"action": "get", "path": path})
        return result.get("value", result)

    def set(self, path, value):
        return self.call("sentinel_state", {"action": "set", "path": path, "value": value})

    def port(self, pipeline, name, count):
        result = self.call("sentinel_pipeline", {"action": "capture_data_port", "pipeline_id": pipeline,
                                                 "port_name": name, "max_elements": count})
        return result.get("elements") or []

    def close(self):
        self.p.kill()


def recall(m: Mcp, kind: str, slot: int, timeout: float = 10.0) -> str:
    """Recall a look through rig_command and wait until the programmer has committed it."""
    before = float(m.get(COMMIT))
    cid = f"bl{int(time.time() * 1000) % 10000000}"
    m.set(STATE + "rig_command", f"{cid}|preset|recall|{kind}|{slot}")
    start = time.time()
    message = ""
    while time.time() - start < timeout:
        message = str(m.get(STATE + "programmer_message"))
        if message.startswith(f"Recalled {kind} {slot} /") and float(m.get(COMMIT)) != before:
            break
        time.sleep(0.1)
    return message


def settle_for(kind: str, slot: int) -> float:
    """Seconds after the commit before recording: truss poses travel for several seconds, movers for about two."""
    return 10.0 if kind == "complete" or (kind == "static" and slot >= 13) else 4.0


def record(m: Mcp):
    program = m.port("Phage_Program", "Fixture Program", 1024)
    dmx = m.port("Phage_Lighting", "DMX", 73)
    axes = m.port("Phage_Kinetics", "Axis State", 64)
    p = np.array([[v for f in PROGRAM_FIELDS for v in e[f]] for e in program], dtype=np.float32)
    d = np.array([[e[f"channels[{c}]"] for c in range(512)] for e in dmx], dtype=np.uint32)
    a = np.array([e["value"] for e in axes], dtype=np.float32)
    return p, d, a


def capture(name: str) -> None:
    m = Mcp()
    show = "Phage_Show"
    labels, programs, dmxs, axes = [], [], [], []
    try:
        print(recall(m, "complete", 1))             # hand the rig to the programmer before freezing its lanes
        time.sleep(2.0)
        m.call("sentinel_pipeline", {"action": "set_mode", "pipeline_id": show, "mode": "freeze"})
        for kind in KINDS:
            for slot in range(1, 17):
                if kind != "complete":
                    recall(m, "complete", 1)
                message = recall(m, kind, slot)
                time.sleep(settle_for(kind, slot))
                p, d, a = record(m)
                labels.append(f"{kind} {slot}")
                programs.append(p)
                dmxs.append(d)
                axes.append(a)
                print(f"{kind} {slot:2d}  rows {p.shape[0]}  {message}", flush=True)
    finally:
        m.call("sentinel_pipeline", {"action": "set_mode", "pipeline_id": show, "mode": "normal"})
        m.close()
    OUT.mkdir(parents=True, exist_ok=True)
    rows = min(p.shape[0] for p in programs)
    np.savez_compressed(OUT / f"{name}.npz", labels=np.array(labels), program=np.stack([p[:rows] for p in programs]),
                        dmx=np.stack(dmxs), axes=np.stack(axes))
    print("wrote", OUT / f"{name}.npz")


def compare(a_name: str, b_name: str, noise_name: str | None = None) -> int:
    a, b = np.load(OUT / f"{a_name}.npz"), np.load(OUT / f"{b_name}.npz")
    noise = np.load(OUT / f"{noise_name}.npz") if noise_name else None
    rows = min(a["program"].shape[1], b["program"].shape[1], 248)
    bad = 0
    for i, label in enumerate(a["labels"]):
        dp = np.abs(a["program"][i, :rows] - b["program"][i, :rows])
        dp[:, 16] = 0.0                                                 # meta.x is the commit revision
        dd = np.abs(a["dmx"][i].astype(int) - b["dmx"][i].astype(int))[9:]   # universes only, not the header
        allowed = np.zeros_like(dd)
        if noise is not None:
            allowed = np.abs(a["dmx"][i].astype(int) - noise["dmx"][i].astype(int))[9:]
        over = dd > np.maximum(allowed, 1)                              # one DMX step is quantisation
        dx = float(np.abs(a["axes"][i] - b["axes"][i]).max()) if a["axes"].shape == b["axes"].shape else -1.0
        line = f"{label:12s} program max {dp.max():.6g}  dmx channels over floor {int(over.sum()):5d}  axes {dx:.4g}"
        if dp.max() > 1e-6 or over.sum() > 0:
            bad += 1
            line += "   <-- differs"
        print(line)
    print(f"{bad} of {len(a['labels'])} looks differ")
    return bad


def ab(name: str) -> int:
    """Per look, with the Show and the truss held still: the DMX with every layer read from its fixture's base row
    (Phage_Program `layered` 0) against each layer read from its own row (`layered` 1), then base again for the floor.
    A look stored before the layers recalls into layer rows that carry what its base rows did, so the two must match
    channel for channel."""
    m = Mcp()
    show, kinetics = "Phage_Show", "Phage_Kinetics"
    mode = lambda node, value: m.call("sentinel_pipeline", {"action": "set_mode", "pipeline_id": node, "mode": value})
    before = m.get(LAYERED)
    labels, programs, base, layered = [], [], [], []
    bad = 0
    try:
        print(recall(m, "complete", 1))
        time.sleep(2.0)
        mode(show, "freeze")
        for kind in KINDS:
            for slot in range(1, 17):
                mode(kinetics, "normal")
                if kind != "complete":
                    recall(m, "complete", 1)
                message = recall(m, kind, slot)
                time.sleep(settle_for(kind, slot))
                mode(kinetics, "freeze")
                time.sleep(0.5)
                runs = []
                for value in (0, 1, 0):
                    m.set(LAYERED, value)
                    time.sleep(0.5)
                    runs.append(record(m))
                (p0, d0, _), (p1, d1, _), (_, d2, _) = runs
                # The floor: base against base a second apart. A mover's fine channels jitter one step between reads.
                floor = int((d0 != d2)[9:].sum())
                diff = int((d0 != d1)[9:].sum())
                step = int(np.abs(d0.astype(int) - d1.astype(int))[9:].max())
                labels.append(f"{kind} {slot}")
                programs.append(p1)
                base.append(d0)
                layered.append(d1)
                flag = "" if diff <= floor and step <= 1 else "   <-- differs"
                bad += 1 if flag else 0
                print(f"{kind} {slot:2d}  layered vs base {diff:5d} channels (max {step} step)  floor {floor:3d}  {message}{flag}", flush=True)
    finally:
        m.set(LAYERED, before)
        mode(kinetics, "normal")
        mode(show, "normal")
        m.close()
    OUT.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(OUT / f"{name}.npz", labels=np.array(labels), program=np.stack(programs),
                        dmx=np.stack(layered), dmx_base=np.stack(base))
    print(f"wrote {OUT / f'{name}.npz'}; {bad} of {len(labels)} looks differ")
    return bad


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "capture":
        capture(sys.argv[2])
    elif len(sys.argv) >= 3 and sys.argv[1] == "ab":
        sys.exit(1 if ab(sys.argv[2]) else 0)
    elif len(sys.argv) >= 4 and sys.argv[1] == "compare":
        noise = sys.argv[sys.argv.index("--noise") + 1] if "--noise" in sys.argv else None
        sys.exit(1 if compare(sys.argv[2], sys.argv[3], noise) else 0)
    else:
        print(__doc__)
