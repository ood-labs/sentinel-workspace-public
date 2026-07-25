#!/usr/bin/env python3
"""TEMPORARY 2B diagnostic: read the picker's OWN flux/threshold trace ring.

specdump proves the per-bin SuperFlux matches the offline reference, but it
reduces bins using the offline lane slices. This reads what pick.hlsl actually
thresholded, so a wrong lane reduction inside flux.hlsl cannot hide.

    python diag_trace.py [peak_floor ...]
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import numpy as np

from sentinel_ipc import Sentinel, AudioRunner, reset_detector

HERE = Path(__file__).resolve().parent
PATTERN = "four_on_floor_128"
TRACE_BASE, MAXLANES, HOPS, NLANES = 528, 16, 64, 3
LANES = ["kick", "snare", "hat"]


def main() -> int:
    floors = [float(a) for a in sys.argv[1:]] or [1e-6]
    cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
    detector, audio = cfg["detector"], cfg["audio"]

    sen = Sentinel()
    runner = AudioRunner(sen, audio, detector, hits_port=cfg["hits_port"])

    for floor in floors:
        reset_detector(sen, detector, audio, mel_slot=cfg["mel_slot"],
                       params={"peak_floor": floor})
        runner.configure_file(HERE / "corpus" / f"{PATTERN}.wav")
        time.sleep(0.6)
        sen.set(f"/sentinel/pipelines/{audio}/parameters/restart_file", 1)

        seen: dict[tuple, tuple] = {}
        t0 = time.time()
        while time.time() - t0 < 14.0:
            d = sen.data_port(detector, "Trace", max_elements=TRACE_BASE + HOPS * MAXLANES)
            els = d.get("elements") or []
            if len(els) <= TRACE_BASE:
                continue
            for slot in range(HOPS):
                for lane in range(NLANES):
                    e = els[TRACE_BASE + slot * MAXLANES + lane]
                    spos = int(e["f3"])
                    if spos > 0:
                        seen[(lane, spos)] = (e["f0"], e["f1"], e["f2"])

        print(f"\npeak_floor {floor:g} - {len(seen)} distinct (lane, hop) trace records")
        print(f"{'lane':>6} | {'flux p99':>9} {'flux max':>9} | {'thr med':>9} "
              f"| {'hop hits':>9} {'hops':>7} {'rate':>7}")
        for i, ln in enumerate(LANES):
            rows = [v for (l, _), v in seen.items() if l == i]
            if not rows:
                continue
            f = np.array([r[0] for r in rows])
            t = np.array([r[1] for r in rows])
            h = np.array([r[2] for r in rows])
            print(f"{ln:>6} | {np.percentile(f,99):>9.4f} {f.max():>9.4f} "
                  f"| {np.median(t):>9.4f} | {int(h.sum()):>9} {len(f):>7} "
                  f"{h.sum()/max(len(f),1):>7.4f}")
    print("\noffline reference lane flux p99: kick 0.504  snare 0.609  hat 0.607")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
