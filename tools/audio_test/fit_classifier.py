#!/usr/bin/env python3
"""Fit the 2D weighted decision from the measured feature study.

Reads scores/_2D_feature_study.json (produced by diag_features.py on the
NON-held-out patterns only) and fits a logistic model

    s = b + w_cent*cent + w_flat*flatness + w_decay*decay + w_energy*energy
    keep the detection when s > 0

which is exactly the "weighted decision" the phase doc asks for, and maps to
four multiplies and a compare in HLSL.

Logistic regression rather than a hand-picked threshold because the features are
correlated (a noisy snare is both flat AND high-centroid), so tuning them one at
a time double-counts the same evidence.

L2 regularisation is deliberately strong: 4 weights over a few hundred samples
from 8 patterns will otherwise memorise the corpus, and the whole point of the
held-out set is that it must not.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
FEAT = ["cent", "flatness", "decay", "energy"]
L2 = 1.0


def sigmoid(z):
    """Numerically stable: exp(-z) overflows for the large |z| an unscaled fit
    produces, which silently poisoned the first version of this script."""
    out = np.empty_like(z)
    pos = z >= 0
    out[pos] = 1.0 / (1.0 + np.exp(-z[pos]))
    e = np.exp(z[~pos])
    out[~pos] = e / (1.0 + e)
    return out


def fit(X, y, l2=L2, iters=20000, lr=0.5):
    """Gradient descent on STANDARDISED features, returned in raw units.

    Standardising is not cosmetic here. `decay` sits in 0.96..1.00 while
    `energy` ranges over ~0..2, so on raw features the fit has to grow the decay
    weight by two orders of magnitude to use it at all. The first version of
    this script skipped this step and produced weights of +96 and -164 with an
    exp() overflow, scoring WORSE (F1 0.661) than the single best feature
    thresholded by hand (0.726) -- a fit failure that looked like a weak
    feature set.
    """
    mu, sd = X.mean(axis=0), X.std(axis=0)
    sd[sd < 1e-9] = 1.0
    Z = (X - mu) / sd

    Zb = np.hstack([np.ones((len(Z), 1)), Z])
    w = np.zeros(Zb.shape[1])
    for _ in range(iters):
        p = sigmoid(Zb @ w)
        grad = Zb.T @ (p - y) / len(y)
        grad[1:] += l2 * w[1:] / len(y)
        w -= lr * grad

    # Back to raw units so HLSL needs no normalisation state.
    raw = np.empty_like(w)
    raw[1:] = w[1:] / sd
    raw[0] = w[0] - np.sum(w[1:] * mu / sd)
    return raw


def report(w, X, y, label):
    s = np.hstack([np.ones((len(X), 1)), X]) @ w
    keep = s > 0
    tp = int(np.sum(keep & (y == 1)))
    fp = int(np.sum(keep & (y == 0)))
    fn = int(np.sum(~keep & (y == 1)))
    prec = tp / max(tp + fp, 1)
    rec = tp / max(tp + fn, 1)
    f1 = 2 * prec * rec / max(prec + rec, 1e-9)
    print(f"  {label:<22} keeps {tp:>3}/{tp+fn:<3} true, admits {fp:>3}/"
          f"{int(np.sum(y==0)):<3} false  ->  P {prec:.3f}  R {rec:.3f}  F1 {f1:.3f}")
    return f1


def main() -> int:
    d = json.loads((HERE / "scores" / "_2D_feature_study.json").read_text())
    T = np.array(d["true"], dtype=float)
    F = np.array(d["false"], dtype=float)
    X = np.vstack([T, F])
    y = np.concatenate([np.ones(len(T)), np.zeros(len(F))])
    print(f"fitting on {len(T)} true / {len(F)} false, features {FEAT}")
    print(f"patterns: {d['patterns']}\n")

    w = fit(X, y)
    print("baseline (accept everything, i.e. current 2C1 snare lane):")
    report(np.array([1e9, 0, 0, 0, 0]), X, y, "no classifier")
    print("\nfitted weighted decision:")
    report(w, X, y, "logistic, L2=%.1f" % L2)

    print("\n  s = %.4f" % w[0])
    for i, n in enumerate(FEAT):
        print(f"      %+0.4f * %s" % (w[i + 1], n))
    print("  keep when s > 0")

    # The snare lane needs RECALL held near 1.0 while precision rises: the 2D
    # criterion allows almost no recall loss. Sweep the bias widely so the
    # operating point is chosen from the frontier rather than from the fit's
    # own 50% cut, which optimises accuracy and not what is being asked for.
    print("\nprecision/recall frontier along the bias:")
    best = None
    for shift in np.arange(-6.0, 6.01, 0.5):
        w2 = w.copy(); w2[0] += shift
        f1 = report(w2, X, y, f"bias {shift:+.1f}")
        if best is None or f1 > best[0]:
            best = (f1, float(shift))
    print(f"\nbest F1 on this sample at bias {best[1]:+.1f} -> {best[0]:.3f}")

    out = {"features": FEAT, "bias": float(w[0]),
           "weights": {n: float(w[i + 1]) for i, n in enumerate(FEAT)},
           "l2": L2, "n_true": len(T), "n_false": len(F),
           "patterns": d["patterns"]}
    p = HERE / "scores" / "_2D_classifier.json"
    p.write_text(json.dumps(out, indent=1), encoding="utf-8")
    print(f"\nwrote {p}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
