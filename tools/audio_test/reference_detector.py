#!/usr/bin/env python3
"""Offline numpy reference of the pulse2_analyzer algorithm.

Same maths as the HLSL passes, run on the corpus WAVs directly. Two uses:

1. Constant selection. A GPU sweep costs ~25 s per pattern per value; this runs
   the whole corpus in seconds, so constants are chosen here and then ported.
2. Parity. 2E1 requires the GPU comb matrix to match an offline Python
   reference; this module is where that reference lives.

It deliberately mirrors the shader structure (whiten -> superflux -> pick)
rather than using a library, so a divergence means a real disagreement.
"""

from __future__ import annotations

import json
import wave
from pathlib import Path

import numpy as np

import metrics

HERE = Path(__file__).resolve().parent
CORPUS = HERE / "corpus"

SR = 48000
FFT = 2048
HOP = 256


def load_mono(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as w:
        n = w.getnframes()
        raw = np.frombuffer(w.readframes(n), dtype="<i2").reshape(-1, 2)
    # Sentinel's documented stereo contract: 0.5 * (left + right)
    return 0.5 * (raw[:, 0].astype(np.float64) + raw[:, 1].astype(np.float64)) / 32768.0


def spectrogram(x: np.ndarray) -> np.ndarray:
    win = np.hanning(FFT)
    nh = (len(x) - FFT) // HOP + 1
    S = np.empty((nh, FFT // 2 + 1))
    for i in range(nh):
        S[i] = np.abs(np.fft.rfft(x[i * HOP:i * HOP + FFT] * win))
    return S / FFT          # scale toward Sentinel's magnitude range


def whiten(S: np.ndarray, r: float, floor: float) -> np.ndarray:
    """P[n,k] = max(r*P[n-1,k], |X[n,k]|);  Y = |X| / max(P, floor)"""
    Y = np.empty_like(S)
    P = np.full(S.shape[1], floor)
    for n in range(S.shape[0]):
        P = np.maximum(r * P, S[n])
        P = np.clip(P, floor, 1e4)
        Y[n] = np.clip(S[n] / np.maximum(P, floor), 0.0, 1.0)
    return Y


def superflux(Y: np.ndarray, gamma: float, mu: int = 2) -> np.ndarray:
    """D[n,k] = max(0, Yc[n,k] - max_{m in [-mu,mu]} Yc[n-1,k+m])"""
    Yc = np.log1p(gamma * Y)
    # max filter across bins on the PREVIOUS frame
    stack = [np.roll(Yc, m, axis=1) for m in range(-mu, mu + 1)]
    mx = np.maximum.reduce(stack)
    D = np.zeros_like(Yc)
    D[1:] = np.maximum(0.0, Yc[1:] - mx[:-1])
    return D


def lane_flux(D: np.ndarray, edges_hz: list[tuple[float, float]]) -> np.ndarray:
    binhz = SR / FFT
    out = np.zeros((D.shape[0], len(edges_hz)))
    for i, (lo, hi) in enumerate(edges_hz):
        k0, k1 = int(lo / binhz), int(hi / binhz)
        k1 = min(k1, D.shape[1] - 1)
        if k1 > k0:
            out[:, i] = D[:, k0:k1].mean(axis=1)
    return out


def pick(o: np.ndarray, lam: float, alpha: float, M: int, refractory_hops: float):
    """Moving-median threshold, one-hop-lookahead local max, refractory."""
    n = len(o)
    thr = np.empty(n)
    for i in range(n):
        lo = max(0, i - M + 1)
        thr[i] = alpha + lam * np.median(o[lo:i + 1])
    hits, last = [], -1e9
    for i in range(1, n - 1):
        if o[i] > thr[i] and o[i] >= o[i - 1] and o[i] >= o[i + 1] and (i - last) > refractory_hops:
            hits.append(i)
            last = i
    return hits, thr


LANES = ["kick", "snare", "hat"]


def run_pattern(meta: dict, cfg: dict):
    x = load_mono(CORPUS / f"{meta['name']}.wav")
    S = spectrogram(x)
    Y = whiten(S, cfg["r"], cfg["floor"])
    D = superflux(Y, cfg["gamma"])
    edges = [(cfg["low_hz"], cfg["split_kick"]),
             (cfg["split_kick"], cfg["split_snare"]),
             (cfg["split_snare"], cfg["high_hz"])]
    O = lane_flux(D, edges)

    ref = {ln: [] for ln in LANES}
    for h in meta["hits"]:
        if h["lane"] in ref:
            ref[h["lane"]].append(h["sample"] / SR)

    out = {}
    for i, ln in enumerate(LANES):
        idx, _ = pick(O[:, i], cfg["lam"], cfg["alpha"], cfg["M"],
                      cfg["refractory_s"] * SR / HOP)
        # frame i covers samples [i*HOP, i*HOP+FFT); report the window END, which
        # is what Sentinel's sample_position reports for that hop.
        est = [(i2 * HOP + FFT) / SR for i2 in idx]
        out[ln] = metrics.f_measure(ref[ln], est, cfg["tol"])
    return out, O, S, Y, D


def load_patterns(names=None):
    pats = []
    for jf in sorted(CORPUS.glob("*.json")):
        m = json.loads(jf.read_text())
        if m.get("role") != "pattern":
            continue
        if names and m["name"] not in names:
            continue
        pats.append(m)
    return pats


DEFAULT = dict(r=0.992, floor=1e-6, gamma=8.0, lam=2.2, alpha=0.08, M=16,
               refractory_s=0.055, tol=0.025, low_hz=25.0, split_kick=200.0,
               split_snare=2400.0, high_hz=20000.0)


if __name__ == "__main__":
    import sys
    names = sys.argv[1:] or None
    cfg = dict(DEFAULT)
    print(f"{'pattern':<28} " + " ".join(f"{l[:5]:>6}" for l in LANES) + f" {'agg':>6}")
    aggs = []
    for m in load_patterns(names):
        res, *_ = run_pattern(m, cfg)
        a = float(np.mean([res[l]["f1"] for l in LANES if res[l]["n_ref"] > 0]))
        aggs.append(a)
        print(f"{m['name']:<28} " + " ".join(f"{res[l]['f1']:>6.3f}" for l in LANES) + f" {a:>6.3f}")
    print(f"{'MEAN':<28} " + " " * (7 * len(LANES)) + f"{np.mean(aggs):>6.3f}")
