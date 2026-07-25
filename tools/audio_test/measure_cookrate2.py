#!/usr/bin/env python3
"""2B criterion 4, with the control the first attempt was missing.

Raw counts differed by 1-2 between 60 Hz and ~20 Hz. That is only meaningful
against run-to-run variance at a FIXED cook rate: restart_file, the detector's
resume point and EOF detection are not sample-locked, so the first and last hop
included in a run drift between identical repeats. Two unthrottled repeats
establish that floor, and onsets are additionally compared over a common
INTERIOR window (0.5 s inset from both ends) where boundary drift cannot reach.

Requires a `cook_load` module pipeline created from modules/_scratch_cook_load.
"""
import json, time
from pathlib import Path
import numpy as np
from score_detector import load_patterns
from sentinel_ipc import Sentinel, AudioRunner, reset_detector

HERE = Path(__file__).resolve().parent
LOAD, TARGET_ITER, SR, INSET = "cook_load", 14000.0, 48000, 0.5
cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
det, aud = cfg["detector"], cfg["audio"]
meta = [m for m in load_patterns(["four_on_floor_128"])][0]
sen = Sentinel(); runner = AudioRunner(sen, aud, det, hits_port=cfg["hits_port"])
DUR = meta["duration_samples"]


def run():
    reset_detector(sen, det, aud, mel_slot=cfg["mel_slot"])
    return runner.run_pattern(meta["_wav"], DUR)["hits"]


def counts(hits, interior=False):
    lo, hi = (INSET * SR, DUR - INSET * SR) if interior else (-1, 1 << 62)
    c = {}
    for ln, lid in cfg["lanes"].items():
        c[ln] = sum(1 for h in hits
                    if int(h["lane_id"]) == lid and lo <= int(h["sample_position"]) <= hi)
    return c


def hz():
    v = []
    for _ in range(3):
        time.sleep(0.7)
        p = sen.call("GET_GRAPH_PROFILE", summary=True, sort_by="wall_time_ms")
        v.append({x["entity_id"]: x for x in p["nodes"]}[det]["cook_hz"])
    return float(np.median(v))


sen.set(f"/sentinel/pipelines/{LOAD}/enabled", False)
time.sleep(1.5)
hz_a = hz()
a1, a2 = run(), run()

sen.set(f"/sentinel/pipelines/{LOAD}/parameters/iterations", TARGET_ITER)
sen.set(f"/sentinel/pipelines/{LOAD}/enabled", True)
time.sleep(3.0)
hz_b = hz()
b1 = run()
sen.set(f"/sentinel/pipelines/{LOAD}/enabled", False)

print(f"unthrottled {hz_a:.0f} Hz    throttled {hz_b:.0f} Hz\n")
for tag, interior in [("FULL RUN", False), ("INTERIOR (0.5 s inset)", True)]:
    ca1, ca2, cb1 = counts(a1, interior), counts(a2, interior), counts(b1, interior)
    print(f"{tag}")
    print(f"{'lane':>6} | {'60Hz #1':>8} {'60Hz #2':>8} {'repeat d':>9} | "
          f"{'20Hz':>6} {'rate d':>7}")
    ctrl_max = rate_max = 0
    for ln in cfg["lanes"]:
        dr, dc = abs(ca1[ln] - ca2[ln]), abs(ca1[ln] - cb1[ln])
        ctrl_max = max(ctrl_max, dr); rate_max = max(rate_max, dc)
        print(f"{ln:>6} | {ca1[ln]:>8} {ca2[ln]:>8} {dr:>9} | {cb1[ln]:>6} {dc:>7}")
    print(f"  max repeat delta (same rate) {ctrl_max}   "
          f"max cook-rate delta {rate_max}\n")

ca1, cb1 = counts(a1, True), counts(b1, True)
ca2 = counts(a2, True)
print(f"criterion 4a interior counts identical 60 Hz vs ~20 Hz : {ca1 == cb1}")
print(f"  control: two 60 Hz repeats identical on the interior : {ca1 == ca2}")
