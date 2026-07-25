#!/usr/bin/env python3
"""Scoring metrics for the Phase 2 audio harness.

Kept separate from score_detector.py so the four absolute self-tests can
exercise the maths directly, with no Sentinel in the loop.

All times are in SECONDS. The caller converts `sample_position` to seconds
using the corpus sample rate; nothing here knows about hops or wall clock.
"""

from __future__ import annotations

import numpy as np

# ---------------------------------------------------------------------------
# Onset F-measure
# ---------------------------------------------------------------------------


def match_events(ref: list[float], est: list[float], tolerance: float):
    """Maximum one-to-one matching between reference and estimated times.

    Candidate pairs within `tolerance` are considered in order of increasing
    absolute error, and a pair is accepted when both sides are still free.
    Greedy-by-error is optimal for this interval structure and avoids the
    double-counting that plain nearest-neighbour matching produces when a
    detector emits bursts.
    """
    ref = sorted(ref)
    est = sorted(est)
    pairs = []
    for i, r in enumerate(ref):
        for j, e in enumerate(est):
            d = abs(e - r)
            if d <= tolerance:
                pairs.append((d, i, j))
    pairs.sort()

    used_r, used_e, matches = set(), set(), []
    for d, i, j in pairs:
        if i in used_r or j in used_e:
            continue
        used_r.add(i)
        used_e.add(j)
        matches.append((i, j, est[j] - ref[i]))
    return matches


def f_measure(ref: list[float], est: list[float], tolerance: float) -> dict:
    if not ref and not est:
        return dict(f1=1.0, precision=1.0, recall=1.0, tp=0, fp=0, fn=0, n_ref=0, n_est=0, offset_ms=0.0)
    matches = match_events(ref, est, tolerance)
    tp = len(matches)
    fp = len(est) - tp
    fn = len(ref) - tp
    precision = tp / len(est) if est else 0.0
    recall = tp / len(ref) if ref else 0.0
    f1 = (2 * precision * recall / (precision + recall)) if (precision + recall) > 0 else 0.0
    offs = [m[2] for m in matches]
    return dict(
        f1=f1, precision=precision, recall=recall,
        tp=tp, fp=fp, fn=fn, n_ref=len(ref), n_est=len(est),
        offset_ms=float(np.median(offs) * 1000.0) if offs else 0.0,
    )


# ---------------------------------------------------------------------------
# Tempo
# ---------------------------------------------------------------------------


def metrical_level(est_bpm: float, ref_bpm: float, tol: float = 0.04):
    """Return (correct_at_reference_level, ratio_label)."""
    if est_bpm <= 0 or ref_bpm <= 0:
        return False, "none"
    for ratio, label in ((1.0, "1x"), (2.0, "2x"), (0.5, "0.5x"),
                         (3.0, "3x"), (1 / 3, "0.33x"), (4.0, "4x"), (0.25, "0.25x")):
        if abs(est_bpm - ref_bpm * ratio) <= tol * ref_bpm * ratio:
            return label == "1x", label
    return False, "off"


# ---------------------------------------------------------------------------
# Beat-tracking continuity (CMLc / AMLc)
# ---------------------------------------------------------------------------
#
# Standard continuity-based metrics (Hainsworth / Klapuri, as used by mir_eval's
# `beat.continuity`). A beat is correct when it falls inside a tolerance window
# (default 17.5% of the current reference inter-beat interval) AND the previous
# beat also matched with a consistent interval. CMLc is the longest continuously
# correct stretch at the *correct metrical level*; AMLc allows the standard
# allowed metrical variations (double, half, offbeat).


def _continuity(ref: np.ndarray, est: np.ndarray, tol: float = 0.175):
    if len(ref) < 2 or len(est) < 2:
        return 0.0
    correct = np.zeros(len(est), dtype=bool)
    for k, e in enumerate(est):
        j = int(np.argmin(np.abs(ref - e)))
        interval = (ref[j + 1] - ref[j]) if j + 1 < len(ref) else (ref[j] - ref[j - 1])
        if interval <= 0:
            continue
        if abs(e - ref[j]) > tol * interval:
            continue
        if k == 0:
            correct[k] = True
            continue
        est_int = est[k] - est[k - 1]
        correct[k] = abs(est_int - interval) <= tol * interval
    # longest run of consecutive correct beats
    best = run = 0
    for c in correct:
        run = run + 1 if c else 0
        best = max(best, run)
    return best / len(est)


def _variations(ref: np.ndarray):
    """Reference sequence plus the standard allowed metrical variations."""
    out = [ref]
    if len(ref) >= 2:
        out.append(ref[::2])                                  # half tempo
        interp = np.interp(np.arange(0, len(ref) - 0.5, 0.5),
                           np.arange(len(ref)), ref)
        out.append(interp)                                    # double tempo
        if len(ref) >= 3:
            out.append((ref[:-1] + ref[1:]) / 2.0)            # offbeat
    return out


def continuity_scores(ref_beats: list[float], est_beats: list[float]) -> dict:
    ref = np.asarray(sorted(ref_beats), dtype=float)
    est = np.asarray(sorted(est_beats), dtype=float)
    if len(ref) < 2 or len(est) < 2:
        return {"CMLc": 0.0, "AMLc": 0.0}
    cmlc = _continuity(ref, est)
    amlc = max(_continuity(v, est) for v in _variations(ref))
    return {"CMLc": float(cmlc), "AMLc": float(max(amlc, cmlc))}
