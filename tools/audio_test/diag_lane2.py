#!/usr/bin/env python3
"""TEMPORARY 2B diagnostic: correlate specdump's lane flux with offline.

specdump computes the SAME lane reduction as flux.hlsl but derives its slot and
prevSlot straight from `latest`, bypassing flux.hlsl's per-slot myGen
bookkeeping. If specdump correlates well with the offline flux where flux.hlsl
does not, the bookkeeping is the bug.

REQUIRES THE `specdump` PASS, which was removed from the module once 2B parity
was proven. To re-run, restore the `dbg` buffer, the `specdump` pass and the
`SpecDump` data output in modules/pulse2_analyzer/manifest.yaml. Kept as the
record of how the binHz and slot-stamp defects were localised.
"""
import json, time
from pathlib import Path
import numpy as np
import reference_detector as R
from sentinel_ipc import Sentinel, AudioRunner, reset_detector

HERE = Path(__file__).resolve().parent
PAT = "four_on_floor_128"
cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
det, aud = cfg["detector"], cfg["audio"]
sen = Sentinel(); runner = AudioRunner(sen, aud, det, hits_port=cfg["hits_port"])
reset_detector(sen, det, aud, mel_slot=cfg["mel_slot"])
runner.configure_file(HERE / "corpus" / f"{PAT}.wav")
time.sleep(0.6)
sen.set(f"/sentinel/pipelines/{aud}/parameters/restart_file", 1)

rows = {}
t0 = time.time()
while time.time() - t0 < 20.0:
    els = (sen.data_port(det, "SpecDump", max_elements=1040).get("elements") or [])
    if len(els) < 1040:
        continue
    sp = int(els[0]["spos"])
    if sp <= 0 or sp in rows:
        continue
    rows[sp] = [els[1024 + l]["y"] for l in range(3)]

S = R.spectrogram(R.load_mono(HERE / "corpus" / f"{PAT}.wav"))[:, :1024]
Do = R.superflux(R.whiten(S, R.DEFAULT["r"], R.DEFAULT["floor"]), R.DEFAULT["gamma"])
Oo = R.lane_flux(Do, [(R.DEFAULT["low_hz"], R.DEFAULT["split_kick"]),
                      (R.DEFAULT["split_kick"], R.DEFAULT["split_snare"]),
                      (R.DEFAULT["split_snare"], R.DEFAULT["high_hz"])])

print(f"{len(rows)} hops\n")
print(f"{'lane':>6} | {'pearson':>8} | {'gpu p90':>8} {'off p90':>8} | {'gpu>thr':>8} {'off>thr':>8}")
for i, ln in enumerate(["kick", "snare", "hat"]):
    g, o = [], []
    for sp in sorted(rows):
        fr = sp // R.HOP - R.FFT // R.HOP
        if 1 <= fr < len(Oo):
            g.append(rows[sp][i]); o.append(Oo[fr, i])
    g, o = np.array(g), np.array(o)
    print(f"{ln:>6} | {np.corrcoef(g,o)[0,1]:>8.3f} | {np.percentile(g,90):>8.4f} "
          f"{np.percentile(o,90):>8.4f} | {(g>0.08).mean():>8.1%} {(o>0.08).mean():>8.1%}")
print("\nflux.hlsl (trace) pearson was: kick 0.299  snare 0.506  hat 0.428")
print("flux.hlsl (trace) p90 was    : kick 0.0122 snare 0.0935 hat 0.3579")
