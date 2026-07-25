#!/usr/bin/env python3
"""Score-driven parameter sweep for pulse2_analyzer.

Tier 1 self-serve, and NON-HELD-OUT PATTERNS ONLY - tuning against
halftime_shuffle_88 or kick_snare_coincident_124 is a Hard Blocker. This script
refuses to load them.

    python sweep.py --param pick_lambda --values 2.2 3.0 4.0 5.0
    python sweep.py --param refractory_s --values 0.04 0.06 0.09 --patterns dense_140
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

import metrics
from score_detector import HELD_OUT, load_patterns, score_pattern
from sentinel_ipc import Sentinel, AudioRunner, reset_detector

HERE = Path(__file__).resolve().parent

DEFAULT_PATTERNS = ["four_on_floor_128", "dense_140", "hats_under_loud_kick_150"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--param", required=True)
    ap.add_argument("--values", nargs="+", type=float, required=True)
    ap.add_argument("--patterns", nargs="*", default=DEFAULT_PATTERNS)
    ap.add_argument("--lane-map", default="lane_map_pulse2.json")
    ap.add_argument("--hold", nargs="*", default=[],
                    help="extra param=value pairs held fixed for every run")
    args = ap.parse_args()

    bad = set(args.patterns) & HELD_OUT
    if bad:
        raise SystemExit(f"REFUSED: {sorted(bad)} are held out and must not be tuned against")

    cfg = json.loads((HERE / args.lane_map).read_text(encoding="utf-8"))
    detector, audio = cfg["detector"], cfg["audio"]
    held = dict(p.split("=", 1) for p in args.hold)

    patterns = [m for m in load_patterns(args.patterns)]
    sen = Sentinel()
    runner = AudioRunner(sen, audio, detector, hits_port=cfg["hits_port"])

    print(f"sweeping {args.param} over {args.values} on {[m['name'] for m in patterns]}")
    if held:
        print(f"holding {held}")
    lanes = list(cfg["lanes"])
    print()
    head = f"{args.param:>12} " + " ".join(f"{ln[:5]:>6}" for ln in lanes) + f" {'aggF1':>7}"
    print(head)
    print("-" * len(head))

    best, rows = None, []
    for v in args.values:
        params = {args.param: v, **held}
        per_lane = {ln: [] for ln in lanes}
        aggs = []
        for meta in patterns:
            reset_detector(sen, detector, audio, mel_slot=cfg["mel_slot"], params=params)
            run = runner.run_pattern(meta["_wav"], meta["duration_samples"])
            r = score_pattern(meta, run["hits"], cfg, [], compensate=False)
            for ln in lanes:
                if r["lanes"][ln]["n_ref"] > 0:
                    per_lane[ln].append(r["lanes"][ln]["f1"])
            aggs.append(r["aggregate_f1"])
        means = {ln: float(np.mean(per_lane[ln])) if per_lane[ln] else 0.0 for ln in lanes}
        agg = float(np.mean(aggs))
        rows.append((v, means, agg))
        print(f"{v:>12.4g} " + " ".join(f"{means[ln]:>6.3f}" for ln in lanes) + f" {agg:>7.3f}")
        if best is None or agg > best[1]:
            best = (v, agg)

    print(f"\nbest {args.param} = {best[0]:g}  (aggregate F1 {best[1]:.3f})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
