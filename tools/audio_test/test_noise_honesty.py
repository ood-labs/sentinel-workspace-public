#!/usr/bin/env python3
"""2E2 criterion 2: does the tracker admit it has nothing?

An adaptive detector normalises to whatever is present, so a noise floor is not
a quiet signal to it -- it is a full-scale signal with no structure. That is how
cryo_pulse came to report 99% confidence at -44 dBFS, and it is the single
failure this whole phase exists to not repeat. A comb filter makes it worse: fed
noise it still finds a best-fitting period, because some period always fits
best.

Both halves are required and they fail differently. Digital silence is the easy
case -- every level is exactly zero. A -44 dBFS floor is the case that actually
catches adaptive normalisation, because the numbers all look healthy.

Asserted on both:
  - tempo_conf decays below 0.1
  - BPM holds its last trusted value rather than wandering
  - kick/snare/hihat counts and beat_count do not advance
  - the detector was genuinely locked beforehand, and is still cooking after

The phase doc names `beat_pulse` for the third clause; this asserts on
`beat_count` instead, which is strictly stronger. `beat_pulse` is a per-cook
transient set from the same emission path as the counter (`Q.h = pulse` beside
`Q.g = beats` in pll.hlsl), so polling it every 0.25 s would miss almost every
pulse it was meant to catch. A `beat_count` that has not moved over the whole
window proves no cook emitted a beat, hence `beat_pulse` was never raised.

    python test_noise_honesty.py
"""

from __future__ import annotations

import json
import time
from pathlib import Path

from sentinel_ipc import Sentinel, AudioRunner

HERE = Path(__file__).resolve().parent
SETTLE_S = 6.0      # let the gate's hold expire and the confidence smoother drain
WATCH_S = 8.0
COUNTERS = ("kick_count", "snare_count", "hihat_count", "beat_count")


def main() -> int:
    cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
    sen = Sentinel()
    d = cfg["detector"]
    runner = AudioRunner(sen, cfg["audio"], cfg["detector"], hits_port=cfg["hits_port"])

    def gv(k: str) -> float:
        g = sen.get(f"/sentinel/pipelines/{d}/control_outputs/{k}")
        return float(g["value"] if isinstance(g, dict) else g)

    def play(stem: str, seconds: float, preroll: bool = False) -> None:
        runner.configure_file(HERE / "corpus" / f"{stem}.wav")
        time.sleep(0.5)
        sen.set(f"/sentinel/pipelines/{cfg['audio']}/parameters/restart_file", 1)
        if preroll:
            # Same whitening pre-roll run_pattern uses. Without it the lock
            # phase inherits the previous pattern's per-bin running peaks -- and
            # since the previous pattern here is a NOISE FLOOR, that is the
            # worst possible starting state. Measured: four_on_floor_128 locked
            # to 85.39 (exactly 2/3 of 128) without the pre-roll and 127.6 with
            # it, which would have been misread as a BPM-hold failure.
            time.sleep(2.0)
            sen.set(f"/sentinel/pipelines/{cfg['audio']}/parameters/restart_file", 1)
        time.sleep(seconds)

    ok = True
    for stem in ("noise_floor_44db", "silence"):
        # Lock onto real music FIRST. Confidence decaying from zero proves
        # nothing; the criterion is that a tracker which HAD a tempo gives it up
        # honestly, and that it keeps reporting the last one it trusted.
        play("four_on_floor_128", 12.0, preroll=True)
        locked_bpm = gv("bpm")
        locked_conf = gv("tempo_conf")

        frames_start = float(sen.pipeline_info(d)["stats"]["framesProcessed"])

        play(stem, SETTLE_S)
        base = {k: gv(k) for k in COUNTERS}
        confs, bpms = [], []
        t0 = time.time()
        while time.time() - t0 < WATCH_S:
            confs.append(gv("tempo_conf"))
            bpms.append(gv("bpm"))
            time.sleep(0.25)
        after = {k: gv(k) for k in COUNTERS}

        conf_max = max(confs)
        # Two separate things, because one alone is not the criterion.
        #
        # FROZEN: once confidence is gone the value must not move AT ALL. Tested
        # as an exact spread over the watch window, which is stricter than any
        # tolerance and is the property that actually matters -- a tracker that
        # creeps while claiming no confidence is lying slowly.
        #
        # STILL THE RIGHT VALUE: frozen at some arbitrary number would satisfy
        # the first test and fail the intent, so it must also still be the tempo
        # it had. Compared with a 1 BPM window rather than an exact match,
        # because the last TRUSTED update lands slightly after the last sample of
        # music -- the comb's ring takes ~4 s to drain and confidence stays above
        # the lock threshold for part of that, so a few genuine updates follow
        # the audio ending. Those are trusted refinements, not drift.
        spread = max(bpms) - min(bpms)
        offset = abs(bpms[-1] - locked_bpm)
        advanced = {k: after[k] - base[k] for k in COUNTERS if after[k] != base[k]}

        # LIVENESS. Frozen confidence, a frozen BPM and flat counters are also
        # exactly what a dead detector produces, so without this the test cannot
        # tell "it gave up honestly" from "it stopped running". Two things are
        # asserted: that it was genuinely locked before the silence (otherwise
        # there was no tempo to give up), and that it is still cooking after.
        frames_end = float(sen.pipeline_info(d)["stats"]["framesProcessed"])
        alive = frames_end > frames_start
        was_locked = locked_conf >= 0.25 and abs(locked_bpm - 128.0) < 2.0

        c1 = conf_max < 0.1
        c2 = spread == 0.0 and offset < 1.0
        c3 = not advanced
        ok &= c1 and c2 and c3 and alive and was_locked

        print(f"=== {stem} (locked on four_on_floor_128 at {locked_bpm:.2f} BPM, "
              f"conf {locked_conf:.3f})")
        print(f"    tempo_conf max over {WATCH_S:.0f}s : {conf_max:.4f}   "
              f"{'PASS' if c1 else 'FAIL'} (< 0.1)")
        print(f"    BPM frozen (spread / offset): {spread:.4f} / {offset:.4f}   "
              f"{'PASS' if c2 else 'FAIL'} (spread 0, offset < 1)")
        print(f"    counters advanced           : {advanced or 'none'}   "
              f"{'PASS' if c3 else 'FAIL'}")
        print(f"    still cooking / was locked  : "
              f"{'PASS' if alive else 'FAIL'} / {'PASS' if was_locked else 'FAIL'}")

    print(f"\ncriterion 2: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
