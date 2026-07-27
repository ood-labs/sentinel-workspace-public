#!/usr/bin/env python3
"""Unit tests for the restart cut in sentinel_ipc.py. No running app required.

This is the bug that cost 2E2 a false twelve-lane regression-gate failure: the
cut finds the restart boundary by looking for a backwards step in sample
position, which only exists while records are in detection order. Sorting by
sample position first turned it into a silent no-op and left stale records from
the previous playthrough as false positives. Nothing caught it; it was found by
hand after being misattributed to a detector parameter.

    python -m pytest test_ipc_cut.py -q
    python test_ipc_cut.py
"""

from __future__ import annotations

from sentinel_ipc import cut_pre_restart


def rec(lane: int, serial: int, pos: int) -> dict:
    return {"lane_id": lane, "onset_serial": serial, "sample_position": pos,
            "hop_index": pos // 256}


def build(*records) -> dict:
    return {(r["lane_id"], r["onset_serial"]): r for r in records}


def test_drops_stale_leading_records():
    # Three records from the tail of the previous playthrough, then a real run.
    stale = [rec(0, 1, 900_000), rec(0, 2, 910_000), rec(0, 3, 920_000)]
    fresh = [rec(0, 4 + i, i * 10_000) for i in range(40)]
    dropped, hits = cut_pre_restart(build(*stale, *fresh))
    assert dropped == 3
    assert len(hits) == 40
    assert max(h["sample_position"] for h in hits) < 800_000


def test_clean_run_drops_nothing():
    fresh = [rec(0, 1 + i, i * 10_000) for i in range(30)]
    dropped, hits = cut_pre_restart(build(*fresh))
    assert dropped == 0 and len(hits) == 30


def test_lanes_are_cut_independently():
    # Only the beat lane carries stale records. The onset lane must be untouched
    # even though its serials interleave with the beat lane's.
    onsets = [rec(0, 1 + i, i * 5_000) for i in range(50)]
    beats = [rec(3, 1, 950_000)] + [rec(3, 2 + i, i * 20_000) for i in range(12)]
    dropped, hits = cut_pre_restart(build(*onsets, *beats))
    assert dropped == 1
    assert sum(1 for h in hits if h["lane_id"] == 0) == 50
    assert all(h["sample_position"] < 900_000 for h in hits if h["lane_id"] == 3)


def test_output_is_ordered_by_sample_position():
    # The scorer times everything by sample position, so the merged result must
    # be in time order regardless of the two independent serial sequences.
    a = [rec(0, 1 + i, i * 10_000) for i in range(10)]
    b = [rec(3, 1 + i, 5_000 + i * 10_000) for i in range(10)]
    _, hits = cut_pre_restart(build(*a, *b))
    pos = [h["sample_position"] for h in hits]
    assert pos == sorted(pos)


def test_short_lanes_are_safe():
    # Zero-length and single-record lanes must not raise or drop anything.
    assert cut_pre_restart({}) == (0, [])
    dropped, hits = cut_pre_restart(build(rec(3, 1, 12_345)))
    assert dropped == 0 and len(hits) == 1


def test_position_ordered_input_cannot_find_the_boundary():
    # THE REGRESSION ITSELF, stated as an assertion. Feeding the same records
    # already ordered by sample position makes a backwards step impossible, so
    # the stale records survive. This documents WHY run_pattern must hand over
    # serial-keyed records and must not pre-sort, and it fails loudly if someone
    # reintroduces the sort upstream.
    stale = [rec(0, 1, 900_000), rec(0, 2, 910_000)]
    fresh = [rec(0, 3 + i, i * 10_000) for i in range(20)]
    good_dropped, _ = cut_pre_restart(build(*stale, *fresh))
    assert good_dropped == 2

    # Re-key so that iteration order follows sample position rather than serial.
    by_pos = {}
    for i, r in enumerate(sorted([*stale, *fresh],
                                 key=lambda h: h["sample_position"])):
        by_pos[(r["lane_id"], i + 1)] = r
    bad_dropped, bad_hits = cut_pre_restart(by_pos)
    assert bad_dropped == 0
    assert any(h["sample_position"] >= 900_000 for h in bad_hits)


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
