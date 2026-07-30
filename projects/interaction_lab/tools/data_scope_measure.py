#!/usr/bin/env python3
"""Measure an Interaction Lab Data Scope capture in pixels.

The useful criteria are about what the plot does -- does it rescale, does a
transient survive a long span -- and eyeballing a screenshot cannot answer
either. This reads the capture back and reports, per lane, the plotted peak
height as a fraction of the strip and the row the reference line sits on.

Lane strips are found by their frame hairlines rather than by recomputing the
module's layout, so a layout change does not silently invalidate the
measurement.

Usage:
    python projects/interaction_lab/tools/data_scope_measure.py <capture.png> [--json]
"""

from __future__ import annotations

import argparse
import json
import sys

from PIL import Image

# The renderer's palette. Fill is T.mid * 0.50, accent is the excursion above
# the reference; both count as plotted signal for height purposes.
ACCENT_MIN_R = 90
FILL_MIN_LUMA = 40


def is_accent(px) -> bool:
    r, g, b = px[0], px[1], px[2]
    return r >= ACCENT_MIN_R and r > b + 30 and r > g + 15


def is_fill(px) -> bool:
    r, g, b = px[0], px[1], px[2]
    if is_accent(px):
        return True
    luma = 0.299 * r + 0.587 * g + 0.114 * b
    return luma >= FILL_MIN_LUMA and abs(r - b) <= 30


def find_lanes(img: Image.Image, lanes: int = 3):
    """Locate the strip rects from the inset well background.

    Two earlier approaches both failed on exactly the captures that matter.
    Deriving the band from the FILL makes the tallest column 1.000 by
    construction, so a healthy plot and a clipping one read identically.
    Deriving it from the FRAME hairline fails on a clipping capture too: the
    frame is drawn additively, so where it crosses accent fill it stops being
    neutral grey and the row is missed.

    The strip interior is T.well (3,3,3) on a T.field (1,1,2) page. That
    difference is tiny but it is a property of the LAYOUT, not of the signal,
    so it holds whatever the plot is doing.
    """
    w, h = img.size
    px = img.load()
    # Sample a column band well inside the plot to avoid the gutter and margin.
    x0, x1 = int(w * 0.35), int(w * 0.95)
    step = max((x1 - x0) // 200, 1)

    inside = []
    for y in range(h):
        n = tot = 0
        for x in range(x0, x1, step):
            r, g, b = px[x, y]
            tot += 1
            if max(r, g, b) >= 3:
                n += 1
        inside.append(bool(tot) and n / tot >= 0.90)

    runs, start = [], None
    for y, on in enumerate(inside):
        if on and start is None:
            start = y
        elif not on and start is not None:
            runs.append((start, y - 1))
            start = None
    if start is not None:
        runs.append((start, h - 1))

    runs = [r for r in runs if r[1] - r[0] >= 16]
    if len(runs) < lanes:
        raise SystemExit(
            f"found {len(runs)} strip bands, expected {lanes}; "
            f"is this a Data Scope capture?"
        )
    runs.sort(key=lambda r: r[1] - r[0], reverse=True)
    return sorted(runs[:lanes]), x0, x1


def measure(path: str):
    img = Image.open(path).convert("RGB")
    w, h = img.size
    px = img.load()
    lanes, x0, x1 = find_lanes(img)

    out = {"path": path, "width": w, "height": h, "lanes": []}
    for idx, (top, bot) in enumerate(lanes):
        # Interior only. The frame hairline reads as fill, and including it made
        # every column report a height of exactly 1.000 -- the same reading a
        # genuinely clipping plot gives, which is the one thing this tool exists
        # to tell apart.
        y_lo, y_hi = top + 2, bot - 1
        span = max(y_hi - y_lo, 1)

        heights, accent_rows = [], []
        for x in range(x0, x1):
            # Walk UP from the baseline and stop at the first gap, so the height
            # is the contiguous column of plotted signal.
            #
            # Scanning down from the top instead finds the highest fill-coloured
            # pixel, which on a silent input is the floating dashed reference
            # line: an empty plot then measured 0.876 of full height, the same
            # reading a saturated one gives.
            run = 0
            for y in range(y_hi, y_lo - 1, -1):
                if not is_fill(px[x, y]):
                    break
                run += 1
            if run > 0:
                heights.append((run - 1) / span)
            # lowest accent pixel marks the reference row for this column
            low = None
            for y in range(y_hi, y_lo - 1, -1):
                if is_accent(px[x, y]):
                    low = y
                    break
            if low is not None:
                accent_rows.append(low)

        heights.sort()
        ref_frac = None
        if accent_rows:
            accent_rows.sort()
            mid = accent_rows[len(accent_rows) // 2]
            ref_frac = (y_hi - mid) / span

        out["lanes"].append({
            "index": idx,
            "top": top,
            "bottom": bot,
            "columns_with_signal": len(heights),
            "peak_height_frac": round(heights[-1], 4) if heights else 0.0,
            "p95_height_frac": round(heights[int(len(heights) * 0.95) - 1], 4) if heights else 0.0,
            "median_height_frac": round(heights[len(heights) // 2], 4) if heights else 0.0,
            "reference_frac": round(ref_frac, 4) if ref_frac is not None else None,
        })
    return out


def edge_segment_lit(path: str, cols: int = 3, lanes: int = 4):
    """Lit-pixel count per column at the live edge, per lane, right column first.

    `measure` deliberately stops at 95% of the width to stay clear of the
    margin, so it never looks at the live edge -- and the live edge is exactly
    where a stale-sample read shows up.

    What it looks like is not a shifted height, which was the first guess and
    measured almost nothing. A connected trail draws a segment between one
    column's value and the next, so a single stale sample at the end renders as
    a near-vertical bar from the live value to a value about a full ring old.
    The signature is therefore the LENGTH of the lit run in the last columns,
    and it separates cleanly. Measured over 6 frames x 4 channels with the
    clamp removed and restored:

        column      clamp removed          clamp restored
        right-0     mean 13.8, max 20      mean 3.7, max 5
        right-1     mean 23.3, max 40      mean 4.3, max 5
        columns over 6 lit: 22/24 and 20/24   vs   0/24 and 0/24

    Columns further left are unaffected in both builds, which is what makes the
    reading positional rather than a general smoothness heuristic.
    """
    img = Image.open(path).convert("RGB")
    w, _ = img.size
    px = img.load()
    rects, _, _ = find_lanes(img, lanes)

    out = []
    for (top, bot) in rects:
        y_lo, y_hi = top + 2, bot - 1
        lit = lambda x: sum(
            1 for y in range(y_lo, y_hi)
            if 0.299 * px[x, y][0] + 0.587 * px[x, y][1] + 0.114 * px[x, y][2] >= 60
        )
        right = None
        for x in range(w - 1, int(w * 0.4), -1):
            if lit(x):
                right = x
                break
        out.append([] if right is None else [lit(right - o) for o in range(cols)])
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("capture")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    res = measure(args.capture)
    if args.json:
        print(json.dumps(res, indent=1))
        return

    print(f"{res['path']}  {res['width']}x{res['height']}")
    for lane in res["lanes"]:
        ref = lane["reference_frac"]
        print(f"  lane {lane['index']}  rows {lane['top']:>4}-{lane['bottom']:<4} "
              f"peak={lane['peak_height_frac']:.3f}  p95={lane['p95_height_frac']:.3f}  "
              f"median={lane['median_height_frac']:.3f}  "
              f"ref={'n/a' if ref is None else f'{ref:.3f}'}  "
              f"cols={lane['columns_with_signal']}")


if __name__ == "__main__":
    sys.exit(main())
