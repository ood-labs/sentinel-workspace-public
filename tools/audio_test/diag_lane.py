#!/usr/bin/env python3
"""TEMPORARY 2B diagnostic: read specdump's per-lane aggregates.

Uses flux.hlsl's OWN lane assignment and denominator, and reports the compressed
energy y and the max-filtered lookback mx separately. If mx sits near zero the
SuperFlux difference has degenerated into raw energy, which explains high recall
with collapsed precision.

REQUIRES THE `specdump` PASS, which was removed from the module once 2B parity
was proven. To re-run, restore the `dbg` buffer, the `specdump` pass and the
`SpecDump` data output in modules/pulse2_analyzer/manifest.yaml. Kept as the
record of how the binHz and slot-stamp defects were localised.
"""
import json, time
from pathlib import Path
import numpy as np
from sentinel_ipc import Sentinel, AudioRunner, reset_detector

HERE = Path(__file__).resolve().parent
cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
det, aud = cfg["detector"], cfg["audio"]
sen = Sentinel(); runner = AudioRunner(sen, aud, det, hits_port=cfg["hits_port"])
reset_detector(sen, det, aud, mel_slot=cfg["mel_slot"])
runner.configure_file(HERE / "corpus" / "four_on_floor_128.wav")
time.sleep(0.6)
sen.set(f"/sentinel/pipelines/{aud}/parameters/restart_file", 1)

rows = {}
t0 = time.time()
while time.time() - t0 < 14.0:
    els = (sen.data_port(det, "SpecDump", max_elements=1040).get("elements") or [])
    if len(els) < 1040:
        continue
    gen = int(els[1024]["gen"])
    if gen in rows:
        continue
    rows[gen] = [[els[1024+l][f] for f in
              ("y","peak","mag","d","y_prev","spos","k")] for l in range(3)]

a = np.array([rows[g] for g in sorted(rows)])   # (hops, lane, field)
print(f"{len(rows)} distinct hops\n")
print(f"{'lane':>6} {'nbins':>6} {'binHz':>8} | {'flux p99':>9} {'y p99':>8} {'mx p99':>8}"
      f" | {'y med':>8} {'mx med':>8} {'mx/y':>6}")
for i, ln in enumerate(["kick","snare","hat"]):
    d, y, mx = a[:,i,0], a[:,i,1], a[:,i,2]
    print(f"{ln:>6} {a[0,i,3]:>6.0f} {a[0,i,4]:>8.4f} | {np.percentile(d,99):>9.4f}"
          f" {np.percentile(y,99):>8.4f} {np.percentile(mx,99):>8.4f}"
          f" | {np.median(y):>8.4f} {np.median(mx):>8.4f} {np.median(mx)/max(np.median(y),1e-9):>6.3f}")
print(f"\nslot/prevSlot on last sample: {a[-1,0,5]:.0f} / {a[-1,0,6]:.0f}  (must differ by 1 mod 64)")
print("offline reference lane flux p99: kick 0.504  snare 0.609  hat 0.607")
print("picker trace  lane flux p99:     kick 1.490  snare 1.552  hat 1.725")
