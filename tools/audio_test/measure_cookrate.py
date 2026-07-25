#!/usr/bin/env python3
"""2B criterion 4: cook-rate independence.

Sentinel exposes no frame-rate cap, so the graph is slowed genuinely with the
_scratch_cook_load fixture until the analyzer's rolling cook_hz sits near 20.
At 20 Hz roughly 9.4 hops arrive per cook against a 64-hop ring, so a correct
catch-up loses nothing; the counts must match the unthrottled run exactly.

The stall case disables the analyzer for longer than the 341 ms ring window,
which DOES destroy hops - the ring has overwritten them and no implementation
can recover them. What is asserted there is that the detector resyncs cleanly:
serials stay strictly increasing with no duplicates and sample_position stays
monotonic, rather than replaying a stale ring or double-counting.

Requires a `cook_load` module pipeline created from modules/_scratch_cook_load
(the fixture pipeline is destroyed after use so a heavy node is never left in
the graph). The raw count comparison here is superseded by measure_cookrate2.py,
which adds the same-rate repeat control; the STALL case still lives here.
"""
import json, time
from pathlib import Path
import numpy as np
import metrics
from score_detector import load_patterns, score_pattern
from sentinel_ipc import Sentinel, AudioRunner, reset_detector

HERE = Path(__file__).resolve().parent
LOAD, TARGET_ITER = "cook_load", 14000.0
cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
det, aud = cfg["detector"], cfg["audio"]
meta = [m for m in load_patterns(["four_on_floor_128"])][0]
sen = Sentinel(); runner = AudioRunner(sen, aud, det, hits_port=cfg["hits_port"])


def cook_hz():
    v = []
    for _ in range(3):
        time.sleep(0.7)
        p = sen.call("GET_GRAPH_PROFILE", summary=True, sort_by="wall_time_ms")
        n = {x["entity_id"]: x for x in p["nodes"]}
        v.append(n[det]["cook_hz"])
    return float(np.median(v))


def counts(hits):
    c = {}
    for ln, lid in cfg["lanes"].items():
        c[ln] = sum(1 for h in hits if int(h["lane_id"]) == lid)
    return c


def run(label, stall=False):
    reset_detector(sen, det, aud, mel_slot=cfg["mel_slot"])
    if stall:
        import threading

        def kick():
            time.sleep(6.0)
            sen.set(f"/sentinel/pipelines/{det}/enabled", False)
            time.sleep(0.6)                     # 600 ms > the 341 ms ring window
            sen.set(f"/sentinel/pipelines/{det}/enabled", True)
        threading.Thread(target=kick, daemon=True).start()
    r = runner.run_pattern(meta["_wav"], meta["duration_samples"])
    sc = score_pattern(meta, r["hits"], cfg, [], compensate=False)
    return r["hits"], counts(r["hits"]), sc


sen.set(f"/sentinel/pipelines/{LOAD}/enabled", False)
time.sleep(1.5)
hz_a = cook_hz()
hits_a, ca, sa = run("unthrottled")

sen.set(f"/sentinel/pipelines/{LOAD}/parameters/iterations", TARGET_ITER)
sen.set(f"/sentinel/pipelines/{LOAD}/enabled", True)
time.sleep(3.0)
hz_b = cook_hz()
hits_b, cb, sb = run("throttled")

sen.set(f"/sentinel/pipelines/{LOAD}/enabled", False)
time.sleep(1.5)
hits_c, cc, sc_ = run("stalled", stall=True)

print(f"unthrottled cook_hz {hz_a:.1f}   throttled cook_hz {hz_b:.1f}\n")
print(f"{'lane':>6} | {'60 Hz':>7} {'20 Hz':>7} {'same':>6} | {'F1 60Hz':>8} {'F1 20Hz':>8} | {'stall':>6}")
same_all = True
for ln in cfg["lanes"]:
    same = ca[ln] == cb[ln]
    same_all &= same
    print(f"{ln:>6} | {ca[ln]:>7} {cb[ln]:>7} {str(same):>6} | "
          f"{sa['lanes'][ln]['f1']:>8.3f} {sb['lanes'][ln]['f1']:>8.3f} | {cc[ln]:>6}")

def monotonic(hits):
    ser = [int(h["onset_serial"]) for h in hits]
    pos = [int(h["sample_position"]) for h in hits]
    return (all(b > a for a, b in zip(ser, ser[1:])), len(ser) == len(set(ser)),
            all(b >= a for a, b in zip(pos, pos[1:])))

print()
print(f"criterion 4a counts identical 60 Hz vs ~20 Hz : {same_all}")
for label, h in [("unthrottled", hits_a), ("throttled", hits_b), ("stalled", hits_c)]:
    inc, uniq, mono = monotonic(h)
    print(f"  {label:<12} n={len(h):<4} serials increasing {inc}  unique {uniq}  sample_position monotonic {mono}")
lost = {ln: ca[ln] - cc[ln] for ln in cfg["lanes"]}
print(f"criterion 4b stall >341 ms resyncs cleanly    : "
      f"{all(monotonic(hits_c))}   onsets lost to the overwritten ring: {lost}")
