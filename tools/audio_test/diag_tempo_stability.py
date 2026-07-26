#!/usr/bin/env python3
"""Is the tempo estimate WRONG, or is it RIGHT and unstable?

2E1 reports one BPM per pattern, a median over the run, which cannot tell those
apart: an estimate that sits on the correct period for 60% of the run and jumps
to a harmonic for 40% has the same median as one that never finds it at all.
The two need different fixes -- better evidence versus temporal integration --
and 2E2's PLL is only the right answer to the second.

Runs through AudioRunner.run_pattern so the whitening pre-roll, the restart and
the generation assertion all apply; sampling the control output by hand skips
those and reads a held value from whatever played last.

Held-out patterns are REFUSED.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

from sentinel_ipc import Sentinel, AudioRunner

HERE = Path(__file__).resolve().parent
HELD_OUT = {"halftime_shuffle_88", "kick_snare_coincident_124"}


def main() -> int:
    cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
    pats = sys.argv[1:] or ["breakbeat_170", "sparse_90", "dense_140",
                            "four_on_floor_128", "syncopated_funk_105"]
    leaked = set(pats) & HELD_OUT
    if leaked:
        print(f"REFUSING: held-out pattern(s) requested: {sorted(leaked)}")
        return 2

    sen = Sentinel()
    runner = AudioRunner(sen, cfg["audio"], cfg["detector"], hits_port=cfg["hits_port"])

    print(f"{'pattern':<24} {'ref':>6} {'median':>7} {'p10':>7} {'p90':>7} "
          f"{'%at ref':>8} {'%at 2/3':>8} {'%at 1/2':>8} {'conf':>6}")
    for p in pats:
        meta = json.loads((HERE / "corpus" / f"{p}.json").read_text(encoding="utf-8"))
        ref = float(meta["tempo"]["bpm_start"])
        res = runner.run_pattern(HERE / "corpus" / f"{p}.wav",
                                 int(meta["duration_samples"]),
                                 extra_polls={"bpm": "bpm", "conf": "tempo_conf"})
        v = np.array([s["bpm"] for s in res["samples"] if np.isfinite(s.get("bpm", np.nan))])
        c = np.array([s["conf"] for s in res["samples"] if np.isfinite(s.get("conf", np.nan))])
        if v.size == 0:
            print(f"{p:<24} {ref:>6.1f}   no samples")
            continue

        def pct(mult):
            t = ref * mult
            return 100.0 * np.mean(np.abs(v - t) <= 0.04 * t)

        print(f"{p:<24} {ref:>6.1f} {np.median(v):>7.1f} {np.percentile(v,10):>7.1f} "
              f"{np.percentile(v,90):>7.1f} {pct(1.0):>7.1f}% {pct(2/3):>7.1f}% "
              f"{pct(0.5):>7.1f}% {c.mean():>6.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
