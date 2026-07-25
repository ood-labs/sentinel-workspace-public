#!/usr/bin/env python3
"""TEMPORARY 2B diagnostic: compare the GPU's whitened spectrum against the
offline reference bin-for-bin.

The GPU detector's lane flux has a ~2x fatter upper tail than the offline
reference at an identical median and threshold, which is a separation failure
rather than a threshold failure. Aggregate statistics cannot say which stage
diverges, so this samples the analyzer's own per-bin Y / P / raw magnitude
during real File playback and lines each dump up with the offline spectrogram
frame covering the same sample position.

Delete alongside the specdump pass once parity is closed.

REQUIRES THE `specdump` PASS, which was removed from the module once 2B parity
was proven. To re-run, restore the `dbg` buffer, the `specdump` pass and the
`SpecDump` data output in modules/pulse2_analyzer/manifest.yaml. Kept as the
record of how the binHz and slot-stamp defects were localised.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

import numpy as np

import reference_detector as R
from sentinel_ipc import Sentinel, AudioRunner, reset_detector

HERE = Path(__file__).resolve().parent
PATTERN = "four_on_floor_128"
NBINS = 1024


def main() -> int:
    cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
    detector, audio = cfg["detector"], cfg["audio"]
    meta = json.loads((HERE / "corpus" / f"{PATTERN}.json").read_text(encoding="utf-8"))

    sen = Sentinel()
    runner = AudioRunner(sen, audio, detector, hits_port=cfg["hits_port"])
    reset_detector(sen, detector, audio, mel_slot=cfg["mel_slot"])

    runner.configure_file(HERE / "corpus" / f"{PATTERN}.wav")
    time.sleep(0.6)
    sen.set(f"/sentinel/pipelines/{audio}/parameters/restart_file", 1)

    dumps: dict[int, np.ndarray] = {}
    t0 = time.time()
    while time.time() - t0 < 18.0:
        d = sen.data_port(detector, "SpecDump", max_elements=NBINS)
        els = d.get("elements") or []
        if len(els) < NBINS:
            continue
        spos = int(els[0]["spos"])
        if spos <= 0 or spos in dumps:
            continue
        dumps[spos] = np.array(
            [[e["y"], e["peak"], e["mag"], e["d"], e["y_prev"]] for e in els],
            dtype=np.float64)

    print(f"captured {len(dumps)} distinct hops during playback\n")
    if not dumps:
        print("NO DUMPS - specdump pass produced nothing")
        return 1

    # Offline side, same audio, same constants.
    x = R.load_mono(HERE / "corpus" / f"{PATTERN}.wav")
    # The port publishes 1024 bins; rfft yields FFT/2+1 = 1025. Both start at
    # DC, so the offline side is trimmed to the same span.
    S = R.spectrogram(x)[:, :NBINS]
    Y = R.whiten(S, R.DEFAULT["r"], R.DEFAULT["floor"])

    print(f"{'spos':>9} {'frame':>6} | {'gpu_mag_sum':>12} {'off_mag_sum':>12} {'ratio':>7}"
          f" | {'gpu_Y_mean':>10} {'off_Y_mean':>10}"
          f" | {'gpu_Y>0.9':>9} {'off_Y>0.9':>9}")
    ratios, gy, oy, gsat, osat = [], [], [], [], []
    for spos in sorted(dumps)[:14]:
        arr = dumps[spos]
        n = spos // R.HOP - R.FFT // R.HOP     # sample_position = window END
        if n < 1 or n >= len(S):
            continue
        gmag, omag = arr[:, 2], S[n]
        r = gmag.sum() / max(omag.sum(), 1e-30)
        ratios.append(r)
        gy.append(arr[:, 0].mean()); oy.append(Y[n].mean())
        gsat.append((arr[:, 0] > 0.9).sum()); osat.append((Y[n] > 0.9).sum())
        print(f"{spos:>9} {n:>6} | {gmag.sum():>12.6f} {omag.sum():>12.6f} {r:>7.3f}"
              f" | {arr[:,0].mean():>10.4f} {Y[n].mean():>10.4f}"
              f" | {(arr[:,0]>0.9).sum():>9} {(Y[n]>0.9).sum():>9}")

    print()
    print(f"magnitude sum ratio gpu/offline : median {np.median(ratios):.4f}")
    print(f"mean whitened Y  gpu {np.mean(gy):.4f}  offline {np.mean(oy):.4f}")
    print(f"bins with Y>0.9  gpu {np.mean(gsat):.1f}  offline {np.mean(osat):.1f}  (of 1024)")

    # --- flux stage -------------------------------------------------------
    # The raw-magnitude readback races the producer ring, so frames are aligned
    # by matching the whitened vector itself rather than by trusting spos.
    D = R.superflux(Y, R.DEFAULT["gamma"])
    edges = [(R.DEFAULT["low_hz"], R.DEFAULT["split_kick"]),
             (R.DEFAULT["split_kick"], R.DEFAULT["split_snare"]),
             (R.DEFAULT["split_snare"], R.DEFAULT["high_hz"])]
    O = R.lane_flux(D, edges)
    binhz = R.SR / R.FFT
    slices = [(int(lo / binhz), min(int(hi / binhz), NBINS - 1)) for lo, hi in edges]

    offs, gl, ol, yerr = [], [], [], []
    for spos in sorted(dumps):
        arr = dumps[spos]
        centre = spos // R.HOP - R.FFT // R.HOP
        lo, hi = max(1, centre - 16), min(len(Y) - 1, centre + 4)
        if hi <= lo:
            continue
        n = lo + int(np.argmin(np.abs(Y[lo:hi] - arr[:, 0]).sum(axis=1)))
        offs.append(n - centre)
        yerr.append(np.abs(Y[n] - arr[:, 0]).mean())
        gl.append([arr[k0:k1, 3].mean() for k0, k1 in slices])
        ol.append(list(O[n]))

    gl, ol = np.array(gl), np.array(ol)
    print()
    print(f"best-match frame offset vs spos-derived: median {np.median(offs):+.0f} "
          f"hops, iqr {np.percentile(offs,25):+.0f}..{np.percentile(offs,75):+.0f}")
    print(f"whitened Y mean abs error at matched frame: {np.mean(yerr):.4f}")
    print()
    print(f"{'lane':>6} | {'gpu p99':>9} {'off p99':>9} {'ratio':>6}"
          f" | {'gpu med':>9} {'off med':>9}")
    for i, ln in enumerate(R.LANES):
        gp, op = np.percentile(gl[:, i], 99), np.percentile(ol[:, i], 99)
        print(f"{ln:>6} | {gp:>9.4f} {op:>9.4f} {gp/max(op,1e-9):>6.2f}"
              f" | {np.median(gl[:,i]):>9.5f} {np.median(ol[:,i]):>9.5f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
