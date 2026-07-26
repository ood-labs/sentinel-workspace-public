#!/usr/bin/env python3
"""2E2 criterion 4: does it still work after half an hour?

A beat tracker is a stateful thing -- phase accumulators, running peaks, ring
buffers, monotonic counters -- and every one of those is a place for a slow leak
that a twenty-second corpus run cannot reach. This plays the frozen corpus
continuously for thirty minutes and asserts that nothing drifted, saturated or
went non-finite, then re-scores the same pattern and requires the detector to be
as accurate at minute 30 as it was at minute 1.

Restarting the file each lap rather than looping it seamlessly is deliberate:
there is no loop parameter, and the restart discontinuity is the harsher test.

    python test_soak.py [--minutes 30] [--pattern four_on_floor_128]
"""

from __future__ import annotations

import argparse
import json
import math
import time
from pathlib import Path

import metrics
from sentinel_ipc import Sentinel, AudioRunner
from score_detector import score_pattern

HERE = Path(__file__).resolve().parent
HELD_OUT = {"halftime_shuffle_88", "kick_snare_coincident_124"}

# Sampled throughout. The counters must only ever climb; the rest must stay
# finite and in range.
COUNTERS = ("kick_count", "snare_count", "hihat_count", "onset_count",
            "beat_count", "beat_cycles", "drop_signal", "drop_ring")
GAUGES = ("bpm", "tempo_conf", "pll_phase", "pll_period", "bpm_locked",
          "beat_conf", "phase_coherence")

F1_TOLERANCE = 0.02


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--minutes", type=float, default=30.0)
    ap.add_argument("--pattern", default="four_on_floor_128")
    a = ap.parse_args()
    if a.pattern in HELD_OUT:
        raise SystemExit(f"held-out, not for tuning: {a.pattern}")

    cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
    sen = Sentinel()
    d = cfg["detector"]
    runner = AudioRunner(sen, cfg["audio"], cfg["detector"], hits_port=cfg["hits_port"])
    meta = json.loads((HERE / "corpus" / f"{a.pattern}.json").read_text(encoding="utf-8"))
    wav = HERE / "corpus" / f"{a.pattern}.wav"
    dur = int(meta["duration_samples"])

    def gv(k: str) -> float:
        g = sen.get(f"/sentinel/pipelines/{d}/control_outputs/{k}")
        return float(g["value"] if isinstance(g, dict) else g)

    def score_once() -> dict:
        res = runner.run_pattern(wav, dur)
        return score_pattern(meta, res["hits"], cfg, [], False)["lanes"]

    print(f"scoring minute 1 on {a.pattern} ...")
    first = score_once()
    for ln, s in sorted(first.items()):
        print(f"    {ln:6s} F1 {s['f1']:.3f}")

    print(f"soaking {a.minutes:.0f} minutes ...")
    t_end = time.time() + a.minutes * 60.0
    last = {k: gv(k) for k in COUNTERS}
    laps, bad = 0, []
    next_report = time.time() + 300.0

    runner.configure_file(wav)
    sen.set(f"/sentinel/pipelines/{cfg['audio']}/parameters/restart_file", 1)

    while time.time() < t_end:
        time.sleep(2.0)

        for k in GAUGES:
            v = gv(k)
            if not math.isfinite(v):
                bad.append(f"{k} non-finite: {v}")
            if k in ("pll_phase",) and not (0.0 <= v <= 1.0):
                bad.append(f"{k} out of range: {v}")
            if k in ("pll_period",) and not (1.0 <= v <= 1000.0):
                bad.append(f"{k} out of range: {v}")

        cur = {k: gv(k) for k in COUNTERS}
        for k in COUNTERS:
            if not math.isfinite(cur[k]):
                bad.append(f"{k} non-finite: {cur[k]}")
            elif cur[k] < last[k]:
                # A counter going backwards means a ring or accumulator wrapped
                # or was reset, which is exactly the class of long-run failure
                # this test exists to catch.
                bad.append(f"{k} went backwards: {last[k]} -> {cur[k]}")
        last = cur

        # Relap when the file has played out. Position stops advancing at EOF in
        # File mode, so a repeated position is the signal.
        pos = runner.head_sample_position()
        time.sleep(0.35)
        if runner.head_sample_position() == pos:
            sen.set(f"/sentinel/pipelines/{cfg['audio']}/parameters/restart_file", 1)
            laps += 1

        if time.time() >= next_report:
            next_report += 300.0
            print(f"    t+{(a.minutes * 60.0 - (t_end - time.time())) / 60.0:5.1f} min  "
                  f"laps {laps:4d}  bpm {gv('bpm'):6.2f}  conf {gv('tempo_conf'):.3f}  "
                  f"beats {gv('beat_count'):.0f}  issues {len(bad)}")

    print(f"soak done: {laps} laps, {len(bad)} issues")
    for b in bad[:20]:
        print("    " + b)

    print("scoring minute 30 ...")
    final = score_once()
    drift_ok = True
    for ln in sorted(first):
        d0, d1 = first[ln]["f1"], final[ln]["f1"]
        ok = abs(d1 - d0) <= F1_TOLERANCE
        drift_ok &= ok
        print(f"    {ln:6s} F1 {d0:.3f} -> {d1:.3f}  ({d1 - d0:+.3f})  "
              f"{'PASS' if ok else 'FAIL'}")

    ok = drift_ok and not bad
    print(f"\ncriterion 4: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
