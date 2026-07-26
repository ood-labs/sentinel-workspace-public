#!/usr/bin/env python3
"""2D separability study: do the features actually tell a snare from a kick tail?

This runs BEFORE any decision rule is written. 2C3 failed three times because
each mechanism was designed from a plausible story and only then measured. Here
the measurement comes first: collect the feature vector at every snare-lane
firing, label each one true or false against the corpus ground truth, and look
at whether the distributions are separable at all.

If they overlap, no weighting of them will work and 2D needs a different feature
set -- better to learn that from a histogram than from a failed corpus run.

Held-out patterns are EXCLUDED. A boundary chosen here would otherwise be tuned
on data reserved for evaluation.

    python diag_features.py [pattern ...]
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import numpy as np

from sentinel_ipc import Sentinel, AudioRunner, reset_detector

HERE = Path(__file__).resolve().parent
HELD_OUT = {"halftime_shuffle_88", "kick_snare_coincident_124"}
TUNE = ["four_on_floor_128", "hats_only_150", "dense_140", "breakbeat_170",
        "sparse_90", "syncopated_funk_105", "hats_under_loud_kick_150",
        "quiet_intro_drop_128"]

TRACE_BASE, NLANES, TRACE_SLOTS = 528, 3, 256
LANES = ["kick", "snare", "hat"]
TOL_S = 0.025          # the scorer's +/-25 ms matching tolerance
FEAT = ["cent", "flatness", "decay", "energy", "centD", "flatD"]
FEAT_ELEMS = 1024   # fstate: [slot*16 + lane], 64 slots x 16 lanes


def collect(sen, runner, pattern, cfg, seconds=16.0):
    """Play one pattern and return every trace record it emitted."""
    # w_centD/w_flatD non-zero switch ON the flux-moment computation in
    # features.hlsl, which the shipped model skips for cost. They cannot affect
    # any decision here because classify_mode is 0 and classify_score() is
    # therefore never consulted.
    #
    # classify_mode MUST be 0 here. With the classifier on, the picker only
    # emits firings it already accepted, so the study would collect a filtered
    # sample of its own decisions and any refit would chase its own tail. This
    # is set explicitly rather than trusted from live state, which at this point
    # still carries classify_mode=1 from the last scored run.
    reset_detector(sen, cfg["detector"], cfg["audio"], mel_slot=cfg["mel_slot"],
                   params={"classify_mode": 0.0, "w_centD": 1.0, "w_flatD": 1.0})
    runner.configure_file(HERE / "corpus" / f"{pattern}.wav")
    time.sleep(0.6)
    sen.set(f"/sentinel/pipelines/{cfg['audio']}/parameters/restart_file", 1)

    need = TRACE_BASE + TRACE_SLOTS * NLANES
    fired: dict[tuple, float] = {}   # (lane, spos) -> 1.0 when the picker accepted
    feats: dict[tuple, tuple] = {}   # (lane, spos) -> full feature vector
    t0 = time.time()
    while time.time() - t0 < seconds:
        # Which hops FIRED comes from the picker's own trace ring (1.37 s deep).
        d = sen.data_port(cfg["detector"], "Trace", max_elements=need)
        els = d.get("elements") or []
        if len(els) >= need:
            for slot in range(TRACE_SLOTS):
                for lane in range(NLANES):
                    e = els[TRACE_BASE + slot * NLANES + lane]
                    spos = int(e["f3"])
                    if spos > 0 and e["f2"] > 0.5:
                        fired[(lane, spos)] = 1.0
        # The feature vector comes from the Features port, which carries all six
        # features. The trace ring has only four spare fields, so it cannot.
        # This ring is shallower (64 hops, 341 ms), hence the tight poll loop.
        f = sen.data_port(cfg["detector"], "Features", max_elements=FEAT_ELEMS)
        fe = f.get("elements") or []
        if len(fe) >= FEAT_ELEMS:
            for slot in range(64):
                for lane in range(NLANES):
                    e = fe[slot * 16 + lane]
                    spos = int(e["spos"])
                    if spos > 0:
                        feats[(lane, spos)] = (e["cent"], e["flatness"],
                                               e["decay"], e["energy"],
                                               e["centD"], e["flatD"])
    return fired, feats


def main() -> int:
    pats = sys.argv[1:] or TUNE
    leaked = set(pats) & HELD_OUT
    if leaked:
        print(f"REFUSING: held-out pattern(s) requested: {sorted(leaked)}")
        return 2

    cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
    assert cfg["detector"] == "pulse2_analyzer"
    sen = Sentinel()
    runner = AudioRunner(sen, cfg["audio"], cfg["detector"],
                         hits_port=cfg["hits_port"])

    rows = []   # (pattern, is_true, cent, flatness, decay, energy, flux, thr)
    for p in pats:
        meta = json.loads((HERE / "corpus" / f"{p}.json").read_text(encoding="utf-8"))
        sr = float(meta["sample_rate"])
        truth = np.array([h["sample"] / sr for h in meta["hits"]
                          if h["lane"] == "snare"])

        fired, feats = collect(sen, runner, p, cfg)
        sn = [(lane, spos) for (lane, spos) in fired if lane == 1]
        missing = 0
        for key in sn:
            v = feats.get(key)
            if v is None:
                missing += 1     # firing seen but its feature hop already rolled out
                continue
            t = key[1] / sr
            hit = bool(len(truth) and np.min(np.abs(truth - t)) <= TOL_S)
            rows.append((p, hit) + tuple(v))
        n_t = sum(1 for r in rows if r[0] == p and r[1])
        n_p = sum(1 for r in rows if r[0] == p)
        print(f"  {p:<26} fired {len(sn):>4}  matched {n_p:>4}  true {n_t:>4}  "
              f"false {n_p-n_t:>4}  (ref snares {len(truth)}"
              + (f", {missing} unmatched)" if missing else ")"))

    if not rows:
        print("NO FIRINGS COLLECTED - is the analyzer running and linked?")
        return 1

    T = np.array([r[2:8] for r in rows if r[1]], dtype=float)
    F = np.array([r[2:8] for r in rows if not r[1]], dtype=float)
    print(f"\ncollected {len(T)} TRUE and {len(F)} FALSE snare firings")
    if not len(T) or not len(F):
        print("need both classes to study separability")
        return 1

    print(f"\n{'feature':>10} | {'true p25':>9} {'true med':>9} {'true p75':>9}"
          f" | {'false p25':>9} {'false med':>9} {'false p75':>9} | {'AUC':>6}")
    for i, name in enumerate(FEAT):
        t, f = T[:, i], F[:, i]
        # AUC via rank statistic: P(random true > random false).
        allv = np.concatenate([t, f])
        ranks = allv.argsort().argsort().astype(float) + 1
        rt = ranks[:len(t)].sum()
        auc = (rt - len(t) * (len(t) + 1) / 2) / (len(t) * len(f))
        print(f"{name:>10} | {np.percentile(t,25):>9.4f} {np.median(t):>9.4f} "
              f"{np.percentile(t,75):>9.4f} | {np.percentile(f,25):>9.4f} "
              f"{np.median(f):>9.4f} {np.percentile(f,75):>9.4f} | {auc:>6.3f}")

    print("\n  AUC 0.5 = useless, 1.0 = perfectly separating true above false,")
    print("  0.0 = perfectly separating the other way (equally usable, inverted).")

    # Best single-feature threshold, by F1 on this sample.
    print("\nbest single-feature split (kept if feature > x, or < x if inverted):")
    for i, name in enumerate(FEAT):
        t, f = T[:, i], F[:, i]
        cand = np.unique(np.concatenate([t, f]))
        best = (0.0, None, None)
        for x in cand:
            for sign in (1, -1):
                tp = int(np.sum(t * sign > x * sign))
                fp = int(np.sum(f * sign > x * sign))
                fn = len(t) - tp
                if tp == 0:
                    continue
                prec, rec = tp / (tp + fp), tp / (tp + fn)
                f1 = 2 * prec * rec / (prec + rec)
                if f1 > best[0]:
                    best = (f1, x, sign)
        if best[1] is not None:
            f1, x, sign = best
            op = ">" if sign > 0 else "<"
            tp = int(np.sum(T[:, i] * sign > x * sign))
            fp = int(np.sum(F[:, i] * sign > x * sign))
            print(f"  {name:>10} {op} {x:>8.4f}  ->  F1 {f1:.3f}  "
                  f"keeps {tp}/{len(T)} true, admits {fp}/{len(F)} false")

    # Per-row pattern labels matter: without them a model cannot be checked for
    # leave-one-pattern-out generalisation, and a failure concentrated in ONE
    # pattern (hats_under_loud_kick_150 kept all 48 of its false positives)
    # looks identical to a uniform weakness in the pooled numbers.
    out = HERE / "scores" / "_2D_feature_study.json"
    out.write_text(json.dumps(
        {"patterns": pats, "features": FEAT,
         "true": T.tolist(), "false": F.tolist(),
         "true_pat": [r[0] for r in rows if r[1]],
         "false_pat": [r[0] for r in rows if not r[1]]}, indent=1), encoding="utf-8")
    print(f"\nwrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
