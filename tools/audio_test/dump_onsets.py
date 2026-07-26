#!/usr/bin/env python3
"""Dump the live onset ring the comb filter actually consumes, one file per pattern.

2E1's tempo stage is a decision rule sitting on top of this ring. Iterating on
that rule against the running app costs a 12 s playback per pattern per idea,
which is how 2C3 burned three attempts on guesses. Dumping the ring once lets
the rule be chosen offline against the SAME data the GPU sees -- not against
ground-truth impulses, which would be an idealisation that flatters any rule.

Held-out patterns are REFUSED. A scoring rule selected by looking at these
dumps is tuned on them, and the two octave-trap patterns are the evaluation.

    python dump_onsets.py            # all 9 permitted patterns
    python dump_onsets.py sparse_90
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

from sentinel_ipc import Sentinel, AudioRunner

HERE = Path(__file__).resolve().parent
OUT = HERE / "scores" / "onset_rings"
HELD_OUT = {"halftime_shuffle_88", "kick_snare_coincident_124"}
ORING, OHDR = 800, 800


def main() -> int:
    cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
    # An explicit held-out name is refused; the no-argument default simply omits
    # them. Refusing the default would only teach the next person to pass a list.
    pats = sys.argv[1:]
    if pats:
        leaked = set(pats) & HELD_OUT
        if leaked:
            print(f"REFUSING: held-out pattern(s) requested: {sorted(leaked)}")
            return 2
    else:
        pats = sorted(p.stem for p in (HERE / "corpus").glob("*.wav")
                      if p.stem not in HELD_OUT)

    OUT.mkdir(parents=True, exist_ok=True)
    sen = Sentinel()
    runner = AudioRunner(sen, cfg["audio"], cfg["detector"], hits_port=cfg["hits_port"])

    for p in pats:
        meta = json.loads((HERE / "corpus" / f"{p}.json").read_text(encoding="utf-8"))
        t = meta.get("tempo", {})
        ref = float(t.get("bpm_start", 0.0))
        if t.get("kind") == "ramp":
            ref = 0.5 * (float(t["bpm_start"]) + float(t["bpm_end"]))

        runner.configure_file(HERE / "corpus" / f"{p}.wav")
        time.sleep(0.4)
        sen.set(f"/sentinel/pipelines/{cfg['audio']}/parameters/restart_file", 1)
        time.sleep(10.0)          # mid-file, ring fully refilled (800 hops = 4.27 s)

        els = sen.data_port(cfg["detector"], "Onsets", max_elements=ORING + 1)["elements"]
        hdr = els[OHDR]
        # (value, generation-stamp) per slot; the stamp is what makes a slot
        # readable -- a slot holding a different generation is a lap-old value.
        ring = [{"v": float(e["strength"]), "gen": float(e["stamp"])} for e in els[:ORING]]
        rec = {
            "pattern": p, "ref_bpm": ref, "held_out": False,
            "judged": float(hdr["strength"]), "hops_per_second": float(hdr["spos"]),
            "ring": ring,
        }
        (OUT / f"{p}.json").write_text(json.dumps(rec), encoding="utf-8")
        nz = sum(1 for r in ring if r["v"] > 0.0)
        print(f"{p:<30} judged={rec['judged']:.0f} hps={rec['hops_per_second']:.2f} "
              f"nonzero={nz}/{ORING}")

    print(f"\nwrote {len(pats)} ring dumps to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
