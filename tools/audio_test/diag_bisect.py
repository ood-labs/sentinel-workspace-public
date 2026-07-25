#!/usr/bin/env python3
"""TEMPORARY 2B diagnostic: run the OFFLINE picker on the GPU's OWN flux series.

flux percentiles now match the offline reference yet the GPU emits ~3x too many
onsets, so the fault is either in the flux time series (right distribution,
wrong shape) or in pick.hlsl. Feeding the GPU's trace flux through
reference_detector.pick separates the two: if the offline picker returns roughly
ground-truth counts on GPU flux, the picker is at fault; if it also over-fires,
the flux is.
"""
import json, time
from pathlib import Path
import numpy as np
import metrics, reference_detector as R
from sentinel_ipc import Sentinel, AudioRunner, reset_detector

HERE = Path(__file__).resolve().parent
PAT = "four_on_floor_128"
TRACE_BASE, MAXLANES, HOPS, NLANES = 528, 16, 64, 3
LANES = ["kick", "snare", "hat"]

cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
det, aud = cfg["detector"], cfg["audio"]
meta = json.loads((HERE / "corpus" / f"{PAT}.json").read_text(encoding="utf-8"))
sen = Sentinel(); runner = AudioRunner(sen, aud, det, hits_port=cfg["hits_port"])
reset_detector(sen, det, aud, mel_slot=cfg["mel_slot"])
runner.configure_file(HERE / "corpus" / f"{PAT}.wav")
time.sleep(0.6)
sen.set(f"/sentinel/pipelines/{aud}/parameters/restart_file", 1)

seen = {}
t0 = time.time()
while time.time() - t0 < 22.0:
    els = (sen.data_port(det, "Trace", max_elements=TRACE_BASE + HOPS * MAXLANES).get("elements") or [])
    if len(els) <= TRACE_BASE:
        continue
    for slot in range(HOPS):
        for lane in range(NLANES):
            e = els[TRACE_BASE + slot * MAXLANES + lane]
            sp = int(e["f3"])
            if sp > 0:
                seen[(lane, sp)] = (e["f0"], e["f1"], e["f2"])

sp_all = sorted({sp for _, sp in seen})
h0, h1 = min(sp_all) // R.HOP, max(sp_all) // R.HOP
n = h1 - h0 + 1
print(f"{len(sp_all)} distinct hops spanning {n} hop slots -> coverage {len(sp_all)/n:.1%}")

ref = {ln: [] for ln in LANES}
for h in meta["hits"]:
    if h["lane"] in ref:
        ref[h["lane"]].append(h["sample"] / R.SR)

print(f"\n{'lane':>6} | {'GT':>5} {'gpu pick':>9} {'off-on-gpu':>11} | "
      f"{'gpu F1':>7} {'off-on-gpu F1':>13}")
for i, ln in enumerate(LANES):
    o = np.zeros(n); have = np.zeros(n, bool); gpu_hits = []
    for (l, sp), (f, t, hit) in seen.items():
        if l != i:
            continue
        j = sp // R.HOP - h0
        o[j] = f; have[j] = True
        if hit > 0.5:
            gpu_hits.append(sp / R.SR)
    idx, _ = R.pick(o, R.DEFAULT["lam"], R.DEFAULT["alpha"], R.DEFAULT["M"],
                    R.DEFAULT["refractory_s"] * R.SR / R.HOP)
    off_est = [((j + h0) * R.HOP) / R.SR for j in idx]
    fg = metrics.f_measure(ref[ln], sorted(gpu_hits), R.DEFAULT["tol"])
    fo = metrics.f_measure(ref[ln], sorted(off_est), R.DEFAULT["tol"])
    print(f"{ln:>6} | {len(ref[ln]):>5} {len(gpu_hits):>9} {len(off_est):>11} | "
          f"{fg['f1']:>7.3f} {fo['f1']:>13.3f}")

# --- shape comparison against the offline flux series ----------------------
S = R.spectrogram(R.load_mono(HERE / "corpus" / f"{PAT}.wav"))[:, :1024]
Yo = R.whiten(S, R.DEFAULT["r"], R.DEFAULT["floor"])
Do = R.superflux(Yo, R.DEFAULT["gamma"])
edges = [(R.DEFAULT["low_hz"], R.DEFAULT["split_kick"]),
         (R.DEFAULT["split_kick"], R.DEFAULT["split_snare"]),
         (R.DEFAULT["split_snare"], R.DEFAULT["high_hz"])]
Oo = R.lane_flux(Do, edges)

print(f"\n{'lane':>6} | {'pearson':>8} | {'gpu>thr':>8} {'off>thr':>8} | "
      f"{'gpu p50':>8} {'off p50':>8} {'gpu p90':>8} {'off p90':>8}")
for i, ln in enumerate(LANES):
    g, o2 = [], []
    for (l, sp), (f, t, hit) in sorted(seen.items()):
        if l != i:
            continue
        fr = sp // R.HOP - R.FFT // R.HOP
        if 1 <= fr < len(Oo):
            g.append(f); o2.append(Oo[fr, i])
    g, o2 = np.array(g), np.array(o2)
    r = np.corrcoef(g, o2)[0, 1]
    print(f"{ln:>6} | {r:>8.3f} | {(g>0.08).mean():>8.1%} {(o2>0.08).mean():>8.1%} | "
          f"{np.percentile(g,50):>8.4f} {np.percentile(o2,50):>8.4f} "
          f"{np.percentile(g,90):>8.4f} {np.percentile(o2,90):>8.4f}")
