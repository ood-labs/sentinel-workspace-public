"""Count-accuracy check for the audio_bands detector against the frozen corpus.

Plays each corpus WAV through the Audio In node in File mode and compares the
detector's hit counts against the pattern's ground-truth lane_counts.

This measures COUNT accuracy, not onset timing. A pattern can score a perfect
count while placing hits in the wrong places, so treat a pass here as "not
over- or under-firing" rather than "detects correctly". It is deliberately the
cheap regression net: it runs in real time, one pass per file, no per-hit
timestamps and no data port.

The two silent patterns are the important ones. `silence` and `noise_floor_44db`
must produce ZERO on every lane; anything else is a false-positive leak that a
count comparison on musical material would not expose.

Usage:
    python count_bands.py                     # every corpus pattern
    python count_bands.py four_on_floor_128   # named patterns only
    python count_bands.py --set hat_threshold=5 -- dense_140

Values passed with --set are applied to the detector before the run and are
recorded in the written table, so a result can never be read back without the
settings that produced it.
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

from sentinel_ipc import Sentinel

CORPUS = Path(__file__).parent / "corpus"
AUDIO = "pulse2_audio"
DET = "audio_bands"
LANES = ("kick", "snare", "hat")

# Wall-clock guards. Files are 20 s; the tail allows the last hit's refractory
# and the render's own cadence to settle before the counters are read.
SETTLE_S = 1.2
TAIL_S = 1.5


def counts(sen: Sentinel) -> dict[str, int]:
    return {ln: int(sen.control_output(DET, f"{ln}_count")) for ln in LANES}


def run_one(sen: Sentinel, name: str) -> dict:
    wav = CORPUS / f"{name}.wav"
    truth = json.loads((CORPUS / f"{name}.json").read_text())
    dur = float(truth["duration_seconds"])
    want = {ln: int(truth["lane_counts"].get(ln, 0)) for ln in LANES}

    # Playback restarts on a CHANGE of file_path. Re-setting the same path is a
    # silent no-op that leaves the node Inactive publishing timestamped silence,
    # which reads downstream as "the detector stopped working". Bounce through
    # another file so re-running one pattern twice in a row still restarts.
    bounce = CORPUS / ("silence.wav" if name != "silence" else "sparse_90.wav")
    sen.set(f"/sentinel/pipelines/{AUDIO}/parameters/file_path", str(bounce))
    time.sleep(0.25)
    sen.set_many({
        f"/sentinel/pipelines/{AUDIO}/parameters/file_path": str(wav),
        f"/sentinel/pipelines/{AUDIO}/parameters/file_start_sample": 0,
    })
    sen.set(f"/sentinel/pipelines/{AUDIO}/parameters/restart_file", 1)

    state = sen.get(f"/sentinel/pipelines/{AUDIO}/diagnostics/capture_state")
    if isinstance(state, dict):
        state = state.get("value")
    if state != "Streaming":
        print(f"  warning: {name} capture_state={state!r}, expected Streaming",
              file=sys.stderr)

    # Baseline AFTER the restart has taken hold, so the previous file's tail is
    # not counted into this one.
    time.sleep(SETTLE_S)
    base = counts(sen)

    time.sleep(dur - SETTLE_S + TAIL_S)
    end = counts(sen)
    got = {ln: end[ln] - base[ln] for ln in LANES}

    # A negative delta means the detector's persistent counters were reset
    # mid-run. Editing any of the module's shader or manifest files does that:
    # Sentinel hot-reloads them, which zeroes the persistent buffers and can move
    # where the control outputs read from. A run corrupted that way produced
    # counts like -2297 and must be reported as invalid, never averaged in.
    reset = any(got[ln] < 0 for ln in LANES)

    return {"name": name, "want": want, "got": got, "reset": reset,
            "err": {ln: got[ln] - want[ln] for ln in LANES}}


def main() -> int:
    argv = sys.argv[1:]
    overrides: dict[str, float] = {}
    names: list[str] = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--set":
            i += 1
            while i < len(argv) and argv[i] != "--" and "=" in argv[i]:
                k, v = argv[i].split("=", 1)
                overrides[k] = float(v)
                i += 1
            continue
        if a == "--":
            i += 1
            continue
        names.append(a)
        i += 1

    if not names:
        names = sorted(p.stem for p in CORPUS.glob("*.json"))

    sen = Sentinel()
    if not sen.ping():
        print("Sentinel is not reachable", file=sys.stderr)
        return 1

    if overrides:
        sen.set_many({
            f"/sentinel/pipelines/{DET}/parameters/{k}": v
            for k, v in overrides.items()
        })
        print("set " + "  ".join(f"{k}={v:g}" for k, v in overrides.items()))

    print(f"{'pattern':28s} {'kick':>12s} {'snare':>12s} {'hat':>12s}")
    print("-" * 68)

    rows = []
    for n in names:
        r = run_one(sen, n)
        rows.append(r)
        if r["reset"]:
            print(f"{n:28s} INVALID - counters reset mid-run "
                  f"(module files edited while running?)")
            continue
        cells = []
        for ln in LANES:
            e = r["err"][ln]
            cells.append(f"{r['got'][ln]:4d}/{r['want'][ln]:<4d}{e:+4d}")
        print(f"{n:28s} " + " ".join(f"{c:>12s}" for c in cells))

    good = [r for r in rows if not r["reset"]]
    bad = len(rows) - len(good)

    print("-" * 68)
    for ln in LANES:
        tot_err = sum(abs(r["err"][ln]) for r in good)
        tot_want = sum(r["want"][ln] for r in good)
        rate = (100.0 * tot_err / tot_want) if tot_want else 0.0
        print(f"{ln:6s} total absolute count error {tot_err:5d} "
              f"of {tot_want:5d} expected  ({rate:.1f}%)")
    if bad:
        print(f"\n{bad} pattern(s) INVALID and excluded from the totals.")

    out = Path(__file__).parent / "count_bands_last.json"
    out.write_text(json.dumps({"overrides": overrides, "rows": rows}, indent=1))
    print(f"\nwrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
