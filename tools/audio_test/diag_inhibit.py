#!/usr/bin/env python3
"""2C3 diagnostic: why does lateral inhibition not remove snare false positives?

The sweep showed snare FP essentially flat (284 -> 288 -> 285 -> 279 for
gain 0 -> 0.15 -> 0.3 -> 0.5) while kick and hat FP fell. Two hypotheses, both
testable from the picker's own trace ring:

  H1  RIVAL TOO SMALL. Inhibition subtracts `g * max_{j!=i} O_j`. If the kick
      lane's flux is not actually larger than the snare lane's at the offending
      hops, no g <= 1 can pull the snare below threshold. The 2B offline
      reference already hints at this: lane flux p99 was kick 0.504 vs snare
      0.609 -- the snare lane is the LOUDER one in whitened flux.

  H2  THRESHOLD FOLLOWS. pick.hlsl routes the moving-median background through
      lane_flux() as well as the peak, so thr = alpha + lambda*median(O') moves
      down with the signal. A near-uniform subtraction then cancels out of
      (o - thr) and changes almost nothing.

`hats_under_loud_kick_150` is the clean probe: it contains ZERO true snares, so
every snare-lane firing is by construction cross-lane leakage from the kick.

Run with the analyzer at inhibit_gain=0 so the recorded flux is RAW.

    python diag_inhibit.py [pattern]
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import numpy as np

from sentinel_ipc import Sentinel, AudioRunner, reset_detector

HERE = Path(__file__).resolve().parent
PATTERN = sys.argv[1] if len(sys.argv) > 1 else "hats_under_loud_kick_150"

# Layout read from modules/pulse2_analyzer/common.hlsli. NOTE: diag_trace.py is
# STALE (stride 16, 64 hops); the ring is stride NLANES over TRACE_SLOTS.
TRACE_BASE, NLANES, TRACE_SLOTS = 528, 3, 256
LANES = ["kick", "snare", "hat"]


def main() -> int:
    cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
    detector, audio = cfg["detector"], cfg["audio"]
    assert detector == "pulse2_analyzer", detector

    sen = Sentinel()
    runner = AudioRunner(sen, audio, detector, hits_port=cfg["hits_port"])

    # inhibit_gain=0 => trace records raw, un-inhibited flux.
    reset_detector(sen, detector, audio, mel_slot=cfg["mel_slot"],
                   params={"inhibit_gain": 0.0})
    runner.configure_file(HERE / "corpus" / f"{PATTERN}.wav")
    time.sleep(0.6)
    sen.set(f"/sentinel/pipelines/{audio}/parameters/restart_file", 1)

    # hop -> lane -> (flux, thr, fired)
    seen: dict[int, dict[int, tuple]] = {}
    need = TRACE_BASE + TRACE_SLOTS * NLANES
    t0 = time.time()
    while time.time() - t0 < 16.0:
        d = sen.data_port(detector, "Trace", max_elements=need)
        els = d.get("elements") or []
        if len(els) < need:
            continue
        for slot in range(TRACE_SLOTS):
            for lane in range(NLANES):
                e = els[TRACE_BASE + slot * NLANES + lane]
                spos = int(e["f3"])
                if spos > 0:
                    seen.setdefault(spos, {})[lane] = (e["f0"], e["f1"], e["f2"])

    hops = sorted(h for h, v in seen.items() if len(v) == NLANES)
    print(f"\npattern {PATTERN} - {len(hops)} hops with all {NLANES} lanes")
    if not hops:
        print("NO TRACE DATA - check the analyzer is running and Trace is populated")
        return 1

    F = np.array([[seen[h][l][0] for l in range(NLANES)] for h in hops])
    T = np.array([[seen[h][l][1] for l in range(NLANES)] for h in hops])
    D = np.array([[seen[h][l][2] for l in range(NLANES)] for h in hops])

    print(f"\n{'lane':>6} | {'flux p50':>9} {'flux p99':>9} {'thr p50':>9} {'fires':>6}")
    for i, ln in enumerate(LANES):
        print(f"{ln:>6} | {np.percentile(F[:,i],50):>9.4f} "
              f"{np.percentile(F[:,i],99):>9.4f} {np.median(T[:,i]):>9.4f} "
              f"{int(D[:,i].sum()):>6}")

    # ---- the decisive test: at hops where the SNARE lane fired --------------
    sn = np.flatnonzero(D[:, 1] > 0.5)
    print(f"\nsnare fired on {len(sn)} hops "
          f"(this pattern has ZERO true snares if it is hats_under_loud_kick)")
    if len(sn) == 0:
        return 0

    o_sn, thr_sn = F[sn, 1], T[sn, 1]
    rival = np.maximum(F[sn, 0], F[sn, 2])          # max over kick, hat
    kick = F[sn, 0]

    print(f"  snare flux at fire   : median {np.median(o_sn):.4f}")
    print(f"  snare threshold      : median {np.median(thr_sn):.4f}")
    print(f"  kick  flux same hops : median {np.median(kick):.4f}")
    print(f"  max rival same hops  : median {np.median(rival):.4f}")
    print(f"  rival/snare ratio    : median {np.median(rival/np.maximum(o_sn,1e-9)):.3f}")
    print(f"  fraction of fires where rival > snare flux: "
          f"{float((rival > o_sn).mean()):.2%}")

    # g needed to push each fire below its OWN threshold, holding thr fixed
    need_g = (o_sn - thr_sn) / np.maximum(rival, 1e-9)
    feasible = need_g <= 1.0
    print(f"\n  gain needed to suppress (thr held fixed):")
    print(f"    median {np.median(need_g):.3f}   p25 {np.percentile(need_g,25):.3f}"
          f"   p75 {np.percentile(need_g,75):.3f}")
    print(f"    suppressible with g<=1.0: {feasible.mean():.2%}  "
          f"-> H1 {'REJECTED' if feasible.mean() > 0.8 else 'SUPPORTED'}")
    for g in (0.15, 0.3, 0.5, 0.8, 1.0):
        print(f"    g={g:<4} would suppress {float((need_g <= g).mean()):>6.2%}")

    # ---- H3: TEMPORAL OFFSET ----------------------------------------------
    # The kick lane is near zero at the offending hops, so the FPs are not
    # simultaneous leakage. Flux spikes at a transient; the snare region may
    # only pick up the kick's decay a hop or two later. Look for the kick's
    # energy in a WINDOW around each snare fire rather than at the same hop.
    print("\n  H3 windowed rival - max kick flux within +/-W hops of each snare fire:")
    idx = {h: i for i, h in enumerate(hops)}
    for W in (0, 1, 2, 3, 5, 8, 12, 20):
        best = []
        for h in np.array(hops)[sn]:
            i = idx[h]
            lo, hi = max(i - W, 0), min(i + W + 1, len(hops))
            best.append(F[lo:hi, 0].max())
        best = np.array(best)
        ratio = np.median(best / np.maximum(o_sn, 1e-9))
        frac = float((best > o_sn).mean())
        print(f"    W={W:>2} hops ({W*5.33:>5.1f} ms): median kick {best.max() and np.median(best):>7.4f}"
              f"  rival/snare {ratio:>6.3f}  rival>snare {frac:>6.2%}")

    # Where IS the nearest kick activity, in hops?
    kick_active = np.flatnonzero(F[:, 0] > np.percentile(F[:, 0], 99) * 0.25)
    if len(kick_active):
        dists = [int(np.min(np.abs(kick_active - idx[h]))) for h in np.array(hops)[sn]]
        d = np.array(dists)
        print(f"\n  distance from each snare fire to nearest ACTIVE kick hop:")
        print(f"    median {np.median(d):.0f} hops ({np.median(d)*5.33:.0f} ms)"
              f"   p25 {np.percentile(d,25):.0f}   p75 {np.percentile(d,75):.0f}")
        print(f"    within 3 hops: {float((d<=3).mean()):.2%}   "
              f"within 8: {float((d<=8).mean()):.2%}   "
              f"within 20: {float((d<=20).mean()):.2%}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
