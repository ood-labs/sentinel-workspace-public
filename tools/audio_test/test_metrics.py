#!/usr/bin/env python3
"""Unit tests for metrics.py. No running app, no corpus, no GPU.

Every number this project reports comes out of these four functions, and until
now none of them had a test. The harness bug that produced a twelve-lane
regression-gate failure in 2E2 was found by hand, and the continuity denominator
bug below had been silently inflating scores since the metric was written.

    python -m pytest test_metrics.py -q
    python test_metrics.py            # also runs standalone
"""

from __future__ import annotations

import metrics

TOL = 0.025


# --- f_measure -------------------------------------------------------------

def test_f_measure_both_empty_is_perfect():
    # Nothing to find and nothing claimed is a correct result, not a failure.
    assert metrics.f_measure([], [], TOL)["f1"] == 1.0


def test_f_measure_missed_everything():
    r = metrics.f_measure([1.0, 2.0], [], TOL)
    assert r["f1"] == 0.0 and r["recall"] == 0.0


def test_f_measure_all_false_positives():
    r = metrics.f_measure([], [1.0], TOL)
    assert r["f1"] == 0.0 and r["fp"] == 1


def test_f_measure_tolerance_boundary_is_inclusive():
    assert metrics.f_measure([1.0], [1.0 + TOL], TOL)["tp"] == 1
    assert metrics.f_measure([1.0], [1.0 + TOL * 1.001], TOL)["tp"] == 0


def test_f_measure_burst_matches_one_to_one():
    # Three estimates crowding one reference must yield one hit and two false
    # positives, never three hits. A detector that machine-guns onsets would
    # otherwise score perfectly.
    r = metrics.f_measure([1.0], [0.99, 1.0, 1.01], TOL)
    assert r["tp"] == 1 and r["fp"] == 2


# --- metrical_level --------------------------------------------------------

def test_metrical_level_octaves_and_edges():
    assert metrics.metrical_level(256.0, 128.0)[1] == "2x"
    assert metrics.metrical_level(64.0, 128.0)[1] == "0.5x"
    assert metrics.metrical_level(128.0, 128.0) == (True, "1x")
    assert metrics.metrical_level(0.0, 128.0)[1] == "none"


def test_metrical_level_only_unity_counts_as_ok():
    # A doubled tempo is a recognised relation, not a pass.
    assert metrics.metrical_level(256.0, 128.0)[0] is False


# --- continuity ------------------------------------------------------------

def _grid(n, step=0.5):
    return [i * step for i in range(n)]


def test_continuity_perfect_grid():
    ref = _grid(100)
    assert metrics.continuity_scores(ref, list(ref))["CMLc"] == 1.0


def test_continuity_does_not_reward_under_emission():
    # THE REGRESSION THIS FILE EXISTS FOR. Dividing the longest correct run by
    # len(est) alone gave three-beats-out-of-a-hundred a perfect 1.0, identical
    # to a tracker that got every beat right. Under-emitting is the most likely
    # silent failure of a beat clock; the metric must not pay a bonus for it.
    ref = _grid(100)
    assert metrics.continuity_scores(ref, [0.0, 0.5, 1.0])["CMLc"] < 0.2


def test_continuity_offbeat_is_an_allowed_variation():
    # Consistently half a beat late is wrong at the correct metrical level and
    # right at an allowed one, so the two scores must disagree.
    ref = _grid(100)
    est = [t + 0.25 for t in ref]
    s = metrics.continuity_scores(ref, est)
    assert s["CMLc"] < 0.1 and s["AMLc"] > 0.8


def test_continuity_degenerate_inputs():
    assert metrics.continuity_scores([], [])["CMLc"] == 0.0
    assert metrics.continuity_scores([1.0], [1.0])["CMLc"] == 0.0


def test_continuity_amlc_never_below_cmlc():
    ref = _grid(60)
    est = [t + 0.01 for t in ref]
    s = metrics.continuity_scores(ref, est)
    assert s["AMLc"] >= s["CMLc"]


if __name__ == "__main__":
    fails = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"  PASS  {name}")
            except AssertionError:
                fails += 1
                print(f"  FAIL  {name}")
    print(f"\n{'PASSED' if not fails else str(fails) + ' FAILED'}")
    raise SystemExit(1 if fails else 0)
