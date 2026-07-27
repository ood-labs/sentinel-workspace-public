#!/usr/bin/env python3
"""Why is CMLc low when the BPM is right?

2E2 scored 127.6 BPM on four_on_floor_128 (true 128) and CMLc 0.21. Those two
numbers cannot both describe a working beat clock, so this dumps the emitted
beat train itself: inter-beat intervals, where they depart from the period the
PLL reports, and how each beat sits against the ground-truth grid.

A continuity metric is a LONGEST RUN, so it is destroyed by rare events rather
than by average error -- one dropped or doubled beat resets the run to zero and
costs far more than a steady small phase offset. This prints the run structure
so the failure mode is visible rather than inferred.

    python diag_beats.py four_on_floor_128
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
    stems = sys.argv[1:] or ["four_on_floor_128"]
    bad = HELD_OUT.intersection(stems)
    if bad:
        sys.exit(f"held-out, not for tuning: {', '.join(sorted(bad))}")

    cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
    beat_lane = int(cfg["beat_lane"])
    sen = Sentinel()
    runner = AudioRunner(sen, cfg["audio"], cfg["detector"], hits_port=cfg["hits_port"])

    for stem in stems:
        meta = json.loads((HERE / "corpus" / f"{stem}.json").read_text(encoding="utf-8"))
        sr = float(meta["sample_rate"])
        ref = np.asarray(sorted(float(b["time"]) for b in meta["beats"]), dtype=float)

        res = runner.run_pattern(HERE / "corpus" / f"{stem}.wav",
                                 int(meta["duration_samples"]))
        beats = [h for h in res["hits"] if int(h["lane_id"]) == beat_lane]
        est = np.asarray([int(h["sample_position"]) / sr for h in beats], dtype=float)

        print(f"=== {stem}  ref {len(ref)} beats  est {len(est)} beats")
        if len(est) < 2:
            print("    no beat train\n")
            continue

        d = np.diff(est)
        med = float(np.median(d))
        print(f"    median inter-beat {med * 1000:.1f} ms = {60.0 / med:.2f} BPM "
              f"(ref {60.0 / float(np.median(np.diff(ref))):.2f})")
        print(f"    interval spread    min {d.min() * 1000:.1f}  max {d.max() * 1000:.1f} ms")

        # Intervals binned by how many reference beats they actually span. A
        # clock that is right on average but drops beats shows up here as a
        # population at 2x, which no mean-error statistic would separate from
        # jitter.
        ratio = d / med
        for label, sel in (("short (<0.6x)", ratio < 0.6),
                           ("normal",        (ratio >= 0.6) & (ratio <= 1.4)),
                           ("double (~2x)",  (ratio > 1.4) & (ratio < 2.6)),
                           ("longer",        ratio >= 2.6)):
            n = int(sel.sum())
            if n:
                print(f"      {label:14s} {n:4d}  ({100.0 * n / len(d):.1f}%)")

        # Phase against the grid, in fractions of a beat -- the tolerance CMLc
        # actually applies is 0.175 of the local interval, not a millisecond.
        off = []
        for e in est:
            j = int(np.argmin(np.abs(ref - e)))
            iv = ref[j + 1] - ref[j] if j + 1 < len(ref) else ref[j] - ref[j - 1]
            off.append((e - ref[j]) / iv)
        off = np.asarray(off)
        within = float((np.abs(off) <= 0.175).mean())
        print(f"    phase offset  mean {off.mean():+.3f} beat  sd {off.std():.3f}  "
              f"within 0.175: {within * 100:.1f}%")

        # Reproduce CMLc's own accept test per beat and print the sequence, so
        # the run structure is visible rather than inferred from a summary. The
        # two clauses fail for different reasons and the fix differs, so they are
        # reported separately: `p` is a beat in the wrong PLACE, `i` a beat at
        # the wrong SPACING from its predecessor.
        marks, why_p, why_i = [], 0, 0
        for k, e in enumerate(est):
            j = int(np.argmin(np.abs(ref - e)))
            iv = ref[j + 1] - ref[j] if j + 1 < len(ref) else ref[j] - ref[j - 1]
            okp = abs(e - ref[j]) <= 0.175 * iv
            oki = k == 0 or abs((est[k] - est[k - 1]) - iv) <= 0.175 * iv
            if not okp:
                why_p += 1
            if not oki:
                why_i += 1
            marks.append("." if (okp and oki) else ("p" if not okp else "i"))
        print(f"    reject: place {why_p}  spacing {why_i}   (. = counted)")
        print("    " + "".join(marks))
        print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
