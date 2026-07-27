#!/usr/bin/env python3
"""Why did the tempo stage pick that period?

2E1 scored 6/11 on metrical level. Rather than guess at the cause and re-tune --
the mistake 2C3 made three times -- this dumps the actual decision surface for a
pattern: the raw comb score per candidate period, the same curve after the
log-Gaussian prior, and after harmonic suppression, with the reference tempo and
its metrical relatives marked.

That distinguishes the three possible failures, which need different fixes:
  - the raw comb never peaks at the true tempo   -> the evidence is wrong
  - it peaks there but the prior pulls it away   -> the prior is wrong
  - it peaks there but suppression removes it    -> gamma or the octave step

Held-out patterns are REFUSED: a tempo constant chosen by looking at this plot
for halftime_shuffle_88 would be tuned on evaluation data.

    python diag_tempo.py breakbeat_170 [...]
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import numpy as np

from sentinel_ipc import Sentinel, AudioRunner

HERE = Path(__file__).resolve().parent
HELD_OUT = {"halftime_shuffle_88", "kick_snare_coincident_124"}
NTAU, BPM_MIN, BPM_MAX = 100, 60.0, 200.0


def main() -> int:
    pats = sys.argv[1:] or ["breakbeat_170", "dense_140", "hats_only_150", "sparse_90"]
    leaked = set(pats) & HELD_OUT
    if leaked:
        print(f"REFUSING: held-out pattern(s) requested: {sorted(leaked)}")
        return 2

    cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
    sen = Sentinel()
    runner = AudioRunner(sen, cfg["audio"], cfg["detector"], hits_port=cfg["hits_port"])
    g = sen.get(f"/sentinel/pipelines/{cfg['detector']}/parameters/tempo_gamma")
    gamma = float(g["value"] if isinstance(g, dict) else g)
    step = (NTAU - 1) * np.log(2.0) / np.log(BPM_MAX / BPM_MIN)
    octave = int(round(step))
    print(f"tempo_gamma={gamma}  octave={step:.2f} steps (using {octave})\n")

    for p in pats:
        meta = json.loads((HERE / "corpus" / f"{p}.json").read_text(encoding="utf-8"))
        t = meta.get("tempo", {})
        ref = float(t.get("bpm_start", 0.0))
        if t.get("kind") == "ramp":
            ref = 0.5 * (float(t["bpm_start"]) + float(t["bpm_end"]))

        runner.configure_file(HERE / "corpus" / f"{p}.wav")
        time.sleep(0.4)
        sen.set(f"/sentinel/pipelines/{cfg['audio']}/parameters/restart_file", 1)
        time.sleep(10.0)          # mid-file, well clear of lock-in

        M = sen.data_port(cfg["detector"], "CombMax", max_elements=128)["elements"]
        raw = np.array([M[i]["score"] for i in range(NTAU)])
        bpm = np.array([M[i]["bpm"] for i in range(NTAU)])

        w = np.exp(-0.5 * (np.log2(np.maximum(bpm, 1.0) / 120.0) / 0.8) ** 2)
        pri = raw * w
        sup = pri.copy()
        for i in range(NTAU):
            hi = pri[i + octave] if i + octave < NTAU else 0.0
            lo = pri[i - octave] if i - octave >= 0 else 0.0
            sup[i] = pri[i] - gamma * (hi + lo)

        def near(target):
            return int(np.argmin(np.abs(bpm - target))) if target > 0 else -1

        print(f"=== {p}  (reference {ref:.1f} BPM) ===")
        print(f"{'curve':>12} {'argmax BPM':>11} {'value':>9}")
        for nm, c in (("raw", raw), ("+prior", pri), ("+suppress", sup)):
            j = int(np.argmax(c))
            print(f"{nm:>12} {bpm[j]:>11.2f} {c[j]:>9.4f}")

        print(f"\n{'relation':>12} {'BPM':>8} {'raw':>9} {'+prior':>9} {'+suppress':>10}")
        for label, mult in (("ref x1", 1.0), ("ref x2", 2.0), ("ref /2", 0.5),
                            ("ref x3/2", 1.5), ("ref x2/3", 2/3),
                            ("ref x3", 3.0), ("ref /3", 1/3)):
            tgt = ref * mult
            if not (BPM_MIN <= tgt <= BPM_MAX):
                continue
            j = near(tgt)
            print(f"{label:>12} {bpm[j]:>8.2f} {raw[j]:>9.4f} {pri[j]:>9.4f} {sup[j]:>10.4f}")
        print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
