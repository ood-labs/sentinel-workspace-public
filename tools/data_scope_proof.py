#!/usr/bin/env python3
"""Assert Phase 4B's measurable criteria against the live Data Scope.

Each check states what must be true, measures it, and prints PASS or FAIL. None
of them is satisfied by a capture merely existing.

  4B.2  scroll rate follows the DATA, not the cook
  4B.3  autoscale is real and bounded, and silence does not autoscale
  4B.4  a transient survives the longest span

Requires the Interaction Lab loaded with Scope_Audio -> Data_Scope, and the
looped corpus signal playing. Run:

    python tools/data_scope_proof.py
"""

from __future__ import annotations

import argparse
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from data_scope_measure import measure          # noqa: E402
from sentinel_bridge import Sentinel            # noqa: E402

PIPE = "Data_Scope"
AUDIO = "Scope_Audio"
CO = f"/sentinel/pipelines/{PIPE}/control_outputs"
PARAM = f"/sentinel/pipelines/{PIPE}/parameters"

CORPUS = Path(__file__).resolve().parent / "audio_test"
LOOP_WAV = CORPUS / "loops" / "quiet_intro_drop_128_x9.wav"
SILENCE_WAV = CORPUS / "corpus" / "silence.wav"

results: list[tuple[str, bool, str]] = []


def record(name: str, ok: bool, detail: str) -> None:
    results.append((name, ok, detail))
    print(f"{'PASS' if ok else 'FAIL'}  {name:<44} {detail}")


def settle(seconds: float) -> None:
    time.sleep(seconds)


def restart_stream(s: Sentinel, wait: float = 1.5) -> None:
    """Rewind the paced WAV and wait for hops to start arriving again.

    File mode plays once and reports Inactive; there is no loop. The first run
    of this harness measured a stream that had simply ended, and reported a
    dead autoscale, a dead sample rate, and a silence check that "failed"
    against three-minute-old frozen data. Every one of those readings looked
    like a module defect and none of them was.
    """
    s.call("sentinel_state", action="invoke",
           path=f"/sentinel/pipelines/{AUDIO}/actions/restart_file")
    settle(wait)


def require_live(s: Sentinel, what: str) -> bool:
    """Assert hops are actually arriving. A frozen stream must fail loudly."""
    drained = s.get(f"{CO}/drained")
    status = s.call("sentinel_pipeline", action="info", pipeline_id=AUDIO)
    msg = status.get("stats", {}).get("statusMessage", "")
    ok = drained > 0.0 and "Inactive" not in msg
    if not ok:
        record(f"PRECONDITION stream live for {what}", False,
               f"drained={drained:.0f} status={msg!r}")
    return ok


def check_scroll_rate(s: Sentinel) -> None:
    """4B.2: samples_shown is span / hop_dt and owes nothing to the frame rate.

    Measured two ways. The plotted history must equal span divided by the
    stream's own sample interval, and write_idx must advance at the stream rate
    rather than the cook rate. A plot that sampled once per cook would show
    write_idx climbing at ~60/s instead of ~187.5/s.
    """
    restart_stream(s)
    if not require_live(s, "4B.2"):
        return
    hop_dt = s.get(f"{CO}/hop_dt")
    for span in (1.0, 3.0):
        s.set(f"{PARAM}/span_seconds", span)
        settle(0.6)
        shown = s.get(f"{CO}/samples_shown")
        want = span / hop_dt
        err = abs(shown - want) / want
        record(f"4B.2 samples_shown = span/hop_dt @ {span}s",
               err < 0.02,
               f"shown={shown:.1f} expected={want:.1f} err={err*100:.2f}%")

    w0 = s.get(f"{CO}/write_idx")
    t0 = time.time()
    settle(3.0)
    w1 = s.get(f"{CO}/write_idx")
    dt = time.time() - t0
    rate = (w1 - w0) / dt
    stream_rate = 1.0 / hop_dt
    err = abs(rate - stream_rate) / stream_rate
    record("4B.2 sample rate tracks the stream, not the cook",
           err < 0.05,
           f"{rate:.1f}/s vs stream {stream_rate:.1f}/s (err {err*100:.1f}%)")


def plotted_peaks(s: Sentinel, tmp: Path, tag: str) -> list[float]:
    png = tmp / f"{tag}.png"
    s.capture(PIPE, str(png))
    m = measure(str(png))
    return [lane["peak_height_frac"] for lane in m["lanes"]]


def check_autoscale(s: Sentinel, tmp: Path) -> None:
    """4B.3: the same material 24 dB apart must plot to the same height.

    The corpus file steps its own level by 24 dB at 8 s of every 20 s loop, so
    the two regimes are the same drums at two amplitudes. Rather than trying to
    time the capture to the loop phase, sample across a whole loop and split on
    the full-scale readout, which is what the autoscale actually moved.
    """
    s.set(f"{PARAM}/span_seconds", 3.0)
    s.set(f"{PARAM}/autoscale", True)
    restart_stream(s)
    if not require_live(s, "4B.3 autoscale"):
        return
    settle(1.0)

    samples = []
    for i in range(14):
        fs = s.get(f"{CO}/low_fs")
        peaks = plotted_peaks(s, tmp, f"auto_{i}")
        samples.append((fs, peaks[0]))
        settle(1.6)

    samples.sort(key=lambda r: r[0])
    quiet, loud = samples[0], samples[-1]

    # The lane value is normalized dB, so the correct check is how many dB the
    # scale moved, not a linear ratio. The corpus steps by 24 dB; against the
    # dB window that is a 1.37x change in full scale, and an earlier ">1.5x"
    # assertion failed a module that was tracking the input exactly.
    window = abs(s.get(f"{PARAM}/db_floor"))
    headroom = 1.15
    delta_db = (loud[0] - quiet[0]) / headroom * window
    record("4B.3 full scale tracked the material's 24 dB step",
           20.0 <= delta_db <= 28.0,
           f"fs {quiet[0]:.3f} -> {loud[0]:.3f} = {delta_db:.1f} dB (want 20-28)")

    diff = abs(loud[1] - quiet[1]) / max(quiet[1], 1e-6)
    record("4B.3 plotted peak height stayed put across the jump",
           diff < 0.15,
           f"quiet={quiet[1]:.3f} loud={loud[1]:.3f} diff={diff*100:.1f}% (<15%)")

    over = [p for _, p in samples if p > 0.999]
    record("4B.3 nothing clipped at any point in the loop",
           not over,
           f"{len(over)}/{len(samples)} captures pinned at full height")


def check_silence_floor(s: Sentinel, tmp: Path) -> None:
    """4B.3b: silence must NOT autoscale its own noise to full height."""
    original = None
    try:
        res = s.call("sentinel_state", action="get",
                     path=f"/sentinel/pipelines/{AUDIO}/parameters/file_path")
        original = res["value"]
        s.set(f"/sentinel/pipelines/{AUDIO}/parameters/file_path", str(SILENCE_WAV))
        restart_stream(s)
        if not require_live(s, "4B.3 silence"):
            return
        # Long enough that the whole 3 s window is silence, short enough that
        # the 20 s file has not ended and frozen the ring again.
        settle(5.0)
        peaks = plotted_peaks(s, tmp, "silence")
        worst = max(peaks)
        record("4B.3 silence does not autoscale to full height",
               worst < 0.35,
               f"tallest lane plotted {worst:.3f} of strip (<0.35)")
    finally:
        if original:
            s.set(f"/sentinel/pipelines/{AUDIO}/parameters/file_path", original)
            settle(3.0)


def check_transient(s: Sentinel, tmp: Path) -> None:
    """4B.4: a transient must survive the longest span.

    At 5 s the plot holds ~940 samples in ~1000 px, so a column covers several
    samples and a mean would bury the hats. The hat lane is the test: its hits
    are the shortest events in the material. Compare the tallest plotted column
    at the shortest and longest spans; max-reduction keeps them comparable,
    averaging would visibly flatten the long span.
    """
    restart_stream(s)
    if not require_live(s, "4B.4"):
        return
    heights = {}
    for span in (0.5, 5.0):
        s.set(f"{PARAM}/span_seconds", span)
        restart_stream(s)
        settle(6.5 if span > 2 else 2.5)
        peaks = plotted_peaks(s, tmp, f"span_{span}")
        heights[span] = peaks[2]

    short, long = heights[0.5], heights[5.0]
    loss = (short - long) / max(short, 1e-6)
    record("4B.4 transient survives the longest span",
           loss < 0.15,
           f"hat peak {short:.3f} @0.5s vs {long:.3f} @5.0s (loss {loss*100:.1f}%)")

    s.set(f"{PARAM}/span_seconds", 3.0)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true", help="keep the capture PNGs")
    args = ap.parse_args()

    tmpdir = Path(tempfile.mkdtemp(prefix="data_scope_proof_"))
    print(f"captures: {tmpdir}\n")

    with Sentinel() as s:
        health = s.call("sentinel_pipeline", action="info", pipeline_id=PIPE)
        stats = health.get("stats", {})
        if not stats.get("healthy"):
            print(f"FAIL  {PIPE} is not healthy: {stats.get('health_reasons')}")
            return 1

        check_scroll_rate(s)
        check_autoscale(s, tmpdir)
        check_silence_floor(s, tmpdir)
        check_transient(s, tmpdir)

    passed = sum(1 for _, ok, _ in results if ok)
    failed = len(results) - passed
    print(f"\n{passed} passed, {failed} failed")
    if not args.keep:
        print(f"(captures left in {tmpdir})")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
