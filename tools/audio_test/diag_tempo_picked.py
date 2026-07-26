#!/usr/bin/env python3
"""Would feeding the comb PICKED onsets beat feeding it raw summed flux?

2E1's comb consumes the summed per-lane flux, which is a continuous detection
function. breakbeat_170 locks confidently onto 2/3 tempo from it, yet an ideal
onset train recovers the true 170 by 1.83x -- so the information survives a
clean impulse train and is lost in the envelope. The picker already produces
accepted onsets, so the comb could read those instead.

This measures that BEFORE it is built, using the detector's own accepted hits
rather than ground truth (ground truth would flatter the idea by hiding every
missed and spurious onset the picker actually makes).

It also reports the fraction of WINDOWS at the correct level, not one median.
A median hides an estimate that is right half the time, and after 2E1 that
distinction is the whole point.

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
# No recoverable tempo: silence and noise have no beat, and hats_only_150 is an
# exactly periodic train of byte-identical hats (excluded from criterion 3 by
# recorded decision).
NO_TEMPO = {"silence", "noise_floor_44db", "hats_only_150"}

ORING, NTAU, NTHETA, NPULSE = 800, 100, 160, 4
BPM_MIN, BPM_MAX, SIGMA = 60.0, 200.0, 1.2


def comb_argmax(env: np.ndarray) -> float:
    """Replica of comb/tmax/tempo with gamma = 0, returning the winning BPM."""
    ti = np.arange(NTAU)
    bpm = BPM_MIN * (BPM_MAX / BPM_MIN) ** (ti / (NTAU - 1))
    tau = (60.0 / bpm) * 187.5
    off = tau[:, None] * (np.arange(NTHETA) / NTHETA)[None, :]
    back = off[:, :, None] + tau[:, None, None] * np.arange(NPULSE)[None, None, :]
    ib = np.floor(back).astype(np.int64)
    t = back - ib
    lo = np.clip(ib, 0, ORING - 1)
    hi = np.clip(ib + 1, 0, ORING - 1)
    v = env[lo] * (1.0 - t) + env[hi] * t
    v[back > ORING - 1] = 0.0
    row = v.mean(axis=2).max(axis=1)
    row = row * np.exp(-0.5 * (np.log2(np.maximum(bpm, 1.0) / 120.0) / SIGMA) ** 2)
    return float(bpm[int(np.argmax(row))])


def smear(arr: np.ndarray, w: int) -> np.ndarray:
    """Triangular widening of each impulse.

    A picked onset occupies exactly one hop while tau is fractional, so a comb
    pulse landing half a hop away collects half the energy and the score becomes
    a function of grid alignment rather than of rhythm. Widening trades a little
    time resolution for a score that is stable under fractional sampling.
    """
    if w <= 0:
        return arr
    k = np.concatenate([np.arange(1, w + 2), np.arange(w, 0, -1)]).astype(float)
    return np.convolve(arr, k / k.sum(), mode="same")


def main() -> int:
    cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
    pats = sys.argv[1:]
    if pats:
        leaked = set(pats) & HELD_OUT
        if leaked:
            print(f"REFUSING: held-out pattern(s) requested: {sorted(leaked)}")
            return 2
    else:
        pats = sorted(p.stem for p in (HERE / "corpus").glob("*.wav")
                      if p.stem not in HELD_OUT and p.stem not in NO_TEMPO)

    sen = Sentinel()
    runner = AudioRunner(sen, cfg["audio"], cfg["detector"], hits_port=cfg["hits_port"])

    widths = (0, 1, 2)
    tally = {w: 0 for w in widths}
    n = 0
    print(f"{'pattern':<24} {'ref':>6}" + "".join(f"{'w=%d' % w:>18}" for w in widths))
    for p in pats:
        meta = json.loads((HERE / "corpus" / f"{p}.json").read_text(encoding="utf-8"))
        ref = float(meta["tempo"]["bpm_start"])
        if meta["tempo"].get("kind") == "ramp":
            ref = 0.5 * (float(meta["tempo"]["bpm_start"]) + float(meta["tempo"]["bpm_end"]))
        res = runner.run_pattern(HERE / "corpus" / f"{p}.wav",
                                 int(meta["duration_samples"]))
        hops = [int(h["hop_index"]) for h in res["hits"]]
        if not hops:
            print(f"{p:<24} {ref:>6.1f}   no hits")
            continue
        base = min(hops)
        arr = np.zeros(max(hops) - base + 1 + 8)
        for h in hops:
            arr[h - base] += 1.0

        n += 1
        line = f"{p:<24} {ref:>6.1f}"
        for w in widths:
            a = smear(arr, w)
            ests = [comb_argmax(a[t - ORING:t][::-1])
                    for t in range(ORING, len(a), 100)]
            if not ests:
                line += f"{'--':>18}"
                continue
            e = np.array(ests)
            pct = 100.0 * np.mean(np.abs(e - ref) <= 0.04 * ref)
            ok = abs(np.median(e) - ref) <= 0.04 * ref
            tally[w] += ok
            line += f"  {np.median(e):>7.1f} {pct:>4.0f}% {'ok ' if ok else 'MISS'}"
        print(line)

    print(f"\n{'':<24} " + "  ".join(f"w={w}: {tally[w]}/{n}" for w in widths))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
