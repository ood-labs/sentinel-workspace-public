#!/usr/bin/env python3
"""Compare candidate tempo decision rules offline against the REAL onset rings.

The comb matrix is settled evidence (criterion 2 proved it matches an offline
float64 reference). What is failing is the rule sitting on top of it: which
(tau, theta) cell to call the tempo. Testing a rule against the running app
costs ~12 s per pattern per idea, so this replicates the shader arithmetic on
the rings dumped by dump_onsets.py and evaluates every rule on all of them at
once. Only the winner is then implemented and re-scored live.

Rules differ in ONE respect -- what counts as evidence for a period:

  peak      rowmax(tau)              what 2E1 shipped
  contrast  rowmax(tau) - rowmean    how much this period PREFERS one phase

`contrast` is the interesting one. A period that is merely a divisor of a dense
onset grid scores well at EVERY phase, so its row is flat and it has no beat to
point at; a real beat concentrates onsets at one phase. Peak height cannot tell
those apart, and the corpus failures are exactly the dense/subdivided patterns.

Held-out patterns are absent by construction: dump_onsets.py never writes them.
"""

from __future__ import annotations

import json
from itertools import product
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
RINGS = HERE / "scores" / "onset_rings"

ORING, NTAU, NTHETA, NPULSE = 800, 100, 160, 4
BPM_MIN, BPM_MAX = 60.0, 200.0
OCTAVE_STEPS = 57
# Patterns with no recoverable tempo are excluded from rule selection: silence
# and noise_floor have no beat at all, and hats_only_150 is an exactly periodic
# train of byte-identical hats whose reference tempo is unrecoverable in
# principle (see the 2E1 devlog). Including them would score every rule the same
# and dilute the comparison.
NO_TEMPO = {"silence", "noise_floor_44db", "hats_only_150"}


def envelope(rec) -> np.ndarray:
    """Chronological onset strengths, index 0 = newest, applying the stamp guard."""
    newest = int(rec["judged"]) - 1
    ring = rec["ring"]
    out = np.zeros(ORING)
    for back in range(ORING):
        g = newest - back
        if g < 0:
            break
        s = ring[g % ORING]
        if int(s["gen"]) == g + 1:
            out[back] = s["v"]
    return out


def comb(env: np.ndarray, hps: float, npulse: int = NPULSE):
    """Replica of comb.hlsl + tmax.hlsl: per-tau row max, row mean, winning phase.

    npulse is swept because the shipped value of 4 spans only four beats, and a
    period that is a wrong SUBDIVISION of the true grid (three eighth-notes
    against two) stays aligned over four beats and only decorrelates once the
    window covers more than one bar. Terms that fall outside the ring contribute
    zero and are still divided by npulse -- biased normalisation, which keeps a
    long lag from being rescued by the handful of terms that do fit.
    """
    ti = np.arange(NTAU)
    bpm = BPM_MIN * (BPM_MAX / BPM_MIN) ** (ti / (NTAU - 1))
    tau = (60.0 / bpm) * hps                              # (NTAU,)
    th = np.arange(NTHETA) / NTHETA
    off = tau[:, None] * th[None, :]                      # (NTAU, NTHETA)
    back = off[:, :, None] + tau[:, None, None] * np.arange(npulse)[None, None, :]

    ib = np.floor(back).astype(np.int64)
    t = back - ib
    lo = np.clip(ib, 0, ORING - 1)
    hi = np.clip(ib + 1, 0, ORING - 1)
    # ring_at interpolates toward the OLDER hop as t rises, matching the shader.
    vals = env[lo] * (1.0 - t) + env[hi] * t
    vals[back > ORING - 1] = 0.0

    C = vals.sum(axis=2) / npulse                         # (NTAU, NTHETA)
    return bpm, C.max(axis=1), C.mean(axis=1), C.argmax(axis=1) / NTHETA


def steps_for(ratio: float) -> int:
    """Grid steps spanning a BPM ratio, on the geometric tau axis."""
    r = (BPM_MAX / BPM_MIN) ** (1.0 / (NTAU - 1))
    return int(round(np.log(ratio) / np.log(r)))


# breakbeat_170 resolves to 112.93 = 170 * 2/3, a DOTTED QUARTER (three eighth
# notes against two), not an octave. Octave-only suppression cannot see that
# relation at all, which is why gamma never helped it at any value.
REL = {"oct": [steps_for(2.0)], "oct32": [steps_for(2.0), steps_for(1.5)]}


def decide(bpm, rowmax, rowmean, *, rule, sigma, gamma, rel="oct"):
    ev = rowmax if rule == "peak" else np.maximum(rowmax - rowmean, 0.0)
    if sigma > 0:
        ev = ev * np.exp(-0.5 * (np.log2(np.maximum(bpm, 1.0) / 120.0) / sigma) ** 2)
    if gamma > 0:
        s = ev.copy()
        for i in range(NTAU):
            acc = 0.0
            for st in REL[rel]:
                acc += ev[i + st] if i + st < NTAU else 0.0
                acc += ev[i - st] if i - st >= 0 else 0.0
            s[i] = ev[i] - gamma * acc
        ev = s
    return int(np.argmax(ev)), ev


def main() -> int:
    raw = []
    for f in sorted(RINGS.glob("*.json")):
        r = json.loads(f.read_text(encoding="utf-8"))
        if r["pattern"] in NO_TEMPO:
            continue
        raw.append((r, envelope(r)))
    print(f"{len(raw)} patterns with a recoverable reference tempo "
          f"(excluded: {', '.join(sorted(NO_TEMPO))})")
    print(f"octave = {steps_for(2.0)} steps, 3:2 = {steps_for(1.5)} steps\n")

    combs = {n: [(r, *comb(e, r["hops_per_second"], n)) for r, e in raw]
             for n in (4, 6, 8, 10)}

    rows = []
    for npulse, rule, sigma, gamma, rel in product(
            (4, 6, 8, 10), ("peak", "contrast"), (0.0, 0.8, 1.2), (0.0, 0.25, 0.5),
            ("oct", "oct32")):
        if gamma == 0.0 and rel != "oct":
            continue                       # identical curve; would double-count
        ok, detail = 0, []
        for rec, bpm, rmax, rmean, ph in combs[npulse]:
            i, _ = decide(bpm, rmax, rmean, rule=rule, sigma=sigma, gamma=gamma, rel=rel)
            hit = abs(bpm[i] - rec["ref_bpm"]) <= 0.04 * rec["ref_bpm"]
            ok += hit
            detail.append((rec["pattern"], rec["ref_bpm"], bpm[i], hit))
        rows.append((ok, npulse, rule, sigma, gamma, rel, detail))

    rows.sort(key=lambda r: (-r[0], r[1]))
    print(f"{'npulse':>7} {'rule':>9} {'sigma':>6} {'gamma':>6} {'rel':>6}   correct")
    for ok, npulse, rule, sigma, gamma, rel, _ in rows[:16]:
        print(f"{npulse:>7} {rule:>9} {sigma:>6.1f} {gamma:>6.2f} {rel:>6}   {ok}/{len(raw)}")

    ok, npulse, rule, sigma, gamma, rel, detail = rows[0]
    print(f"\nbest: npulse={npulse} rule={rule} sigma={sigma} gamma={gamma} rel={rel}"
          f"  ({ok}/{len(raw)})")
    print(f"\n{'pattern':<28} {'ref':>7} {'best':>8}      {'shipped':>8}")
    ship = {r[0]["pattern"]: r for r in combs[4]}
    for name, ref, est, hit in detail:
        rec, bpm, rmax, rmean, ph = ship[name]
        j, _ = decide(bpm, rmax, rmean, rule="peak", sigma=0.8, gamma=0.5, rel="oct")
        sh = abs(bpm[j] - ref) <= 0.04 * ref
        print(f"{name:<28} {ref:>7.1f} {est:>8.2f} {'ok  ' if hit else 'MISS'}"
              f"  {bpm[j]:>8.2f} {'ok' if sh else 'MISS'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
