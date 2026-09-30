"""Zoning proof: count lit samples inside Block zones (and outside Only-In zones) in what is sent.

Reads the Mapping Editor's Calibration (the enabled zones, margin already applied, screen space
+y down), Adaptive Mapping's Mapped Scan, and Laser Out's Sent Stream (ILDA, +y up). Laser Out
may flip or rotate its stream for the device, so the Sent Stream's orientation is found by
matching its lit points against the Mapped Scan before the zones are tested.

The zones in the Calibration are the drawn zones with Mask Margin applied (Block grown, Only-In
shrunk). Laser Out moves lit points a little after the mapper (measured about 0.003 scanner
units on the DS-3000), which is what the margin absorbs. So:
  PASS         nothing lit past the compiled zone edge (1e-4 rounding tolerance)
  PASS/MARGIN  lit points crossed the compiled edge but by less than the margin, so they never
               reached the zone as drawn; the report says how much of the margin was used
  FAIL         lit points reached the drawn zone Run it with the laser armed and a look playing: a
disarmed Laser Out sends a single blanked point, and that is reported rather than passed.

  python scripts/mask_check.py [--samples 64]
"""
import argparse
import math
import sys
import time

import lm_mcp

CAL_N, MASK_BASE, POLY_BASE, POLY_MAX, COOKIE = 577, 32, 65, 32, 5151


def rot(v, a):
    c, s = math.cos(a), math.sin(a)
    return (c * v[0] - s * v[1], s * v[0] + c * v[1])


def zones(cal):
    h = cal[MASK_BASE]
    if len(cal) != CAL_N or h[1] != COOKIE:
        sys.exit("Calibration has no zoning block (%d elements); is the Mapping Editor up to date?" % len(cal))
    out = []
    for j in range(int(h[0])):
        info, r = cal[MASK_BASE + 1 + 2 * j], cal[MASK_BASE + 2 + 2 * j]
        z = {"kind": int(round(info[0])), "block": info[1] < .5, "angle": info[3], "rect": r}
        if z["kind"] == 2:
            z["pts"] = [cal[POLY_BASE + POLY_MAX * j + i][:2] for i in range(int(r[0]))]
        out.append(z)
    return out


def inside(z, p):
    if z["kind"] == 2:
        pts, ins = z["pts"], False
        a = pts[-1]
        for b in pts:
            if (a[1] > p[1]) != (b[1] > p[1]) and p[0] < a[0] + (p[1] - a[1]) * (b[0] - a[0]) / (b[1] - a[1]):
                ins = not ins
            a = b
        return ins
    r = z["rect"]
    l = rot((p[0] - r[0], p[1] - r[1]), -z["angle"])
    if z["kind"] == 0:
        return abs(l[0]) <= r[2] and abs(l[1]) <= r[3]
    return r[2] > 0 and r[3] > 0 and (l[0] / r[2]) ** 2 + (l[1] / r[3]) ** 2 <= 1


def distance(z, p):
    """Signed distance to the zone's edge in scanner units: positive outside, negative inside."""
    if z["kind"] == 2:
        pts = z["pts"]
        d = min(seg_dist(p, pts[i], pts[(i + 1) % len(pts)]) for i in range(len(pts)))
        return -d if inside(z, p) else d
    r = z["rect"]
    l = rot((p[0] - r[0], p[1] - r[1]), -z["angle"])
    if z["kind"] == 0:
        e = (abs(l[0]) - r[2], abs(l[1]) - r[3])
        return math.hypot(max(e[0], 0), max(e[1], 0)) + min(max(e[0], e[1]), 0)
    h = (max(r[2], 1e-9), max(r[3], 1e-9))
    return (math.hypot(l[0] / h[0], l[1] / h[1]) - 1) * min(h)


def seg_dist(p, a, b):
    d = (b[0] - a[0], b[1] - a[1])
    L = d[0] * d[0] + d[1] * d[1]
    t = 0 if L < 1e-20 else max(0, min(1, ((p[0] - a[0]) * d[0] + (p[1] - a[1]) * d[1]) / L))
    return math.hypot(p[0] - a[0] - d[0] * t, p[1] - a[1] - d[1] * t)


def lit_points(records, samples, transform=lambda p: p):
    """Lit sample points of a scan, converted to screen space (+y down)."""
    n = int(records[0]["endpoints"][0])
    pts = []
    for e in records[1:n + 1]:
        if e["timing"][3] > .5 or max(e["color0"][:3] + e["color1"][:3]) <= 0:
            continue
        a = e["endpoints"]
        for i in range(samples + 1):
            t = i / samples
            x, y = transform((a[0] + (a[2] - a[0]) * t, a[1] + (a[3] - a[1]) * t))
            pts.append((x, -y))
    return pts


TOL = 1e-4  # scanner units (0.005% of the field): float rounding of endpoints that sit on an edge


def violations(zs, pts):
    """Counts lit samples more than TOL inside a Block zone or outside every Only-In zone, and the
    worst excess found (so a rounding-level touch is visible rather than silently forgiven)."""
    only_in = [z for z in zs if not z["block"]]
    bad_block = bad_only = 0
    worst = 0.0
    for p in pts:
        depth = max([-distance(z, p) for z in zs if z["block"]] or [-1])
        if depth > 0:
            worst = max(worst, depth)
            bad_block += depth > TOL
        elif only_in:
            out = min(distance(z, p) for z in only_in)
            if out > 0:
                worst = max(worst, out)
                bad_only += out > TOL
    return bad_block, bad_only, worst


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", type=int, default=64, help="points tested along each lit record")
    ap.add_argument("--out", default="Laser_Out")
    args = ap.parse_args()
    m = lm_mcp.Client()
    time.sleep(0.5)
    val = lambda e: e[list(e.keys())[0]]
    cal = [val(e) for e in m.port("Mapping_Editor", "Calibration", 600)]
    zs = zones(cal)
    margin = cal[MASK_BASE][2]
    print("zones: %d enabled (%d block, %d only-in)" % (len(zs), sum(z["block"] for z in zs), sum(not z["block"] for z in zs)))

    mapped = lit_points(m.port("Adaptive_Mapping", "Mapped Scan", 1024), args.samples)
    b, o, w = violations(zs, mapped)
    print("Mapped Scan: %d lit samples, %d inside a Block zone, %d outside every Only-In zone (worst excess %.2g)"
          % (len(mapped), b, o, w))

    sent_raw = m.port(args.out, "Sent Stream", 4096)
    if not lit_points(sent_raw, 1):
        print("Sent Stream: nothing lit (Laser Out disarmed or idle); arm it with a look playing to test the output")
        sys.exit(1 if b or o else 0)
    # Find the Sent Stream's orientation: the transform whose lit points sit closest to the mapped ones.
    ref = lit_points(m.port("Adaptive_Mapping", "Mapped Scan", 1024), 4)
    best = None
    for name, f in (("as-is", lambda p: p), ("flip x", lambda p: (-p[0], p[1])),
                    ("flip y", lambda p: (p[0], -p[1])), ("rotate 180", lambda p: (-p[0], -p[1]))):
        probe = lit_points(sent_raw, 2, f)[:400]
        err = sum(min((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 for q in ref) for p in probe) / max(len(probe), 1)
        if best is None or err < best[0]:
            best = (err, name, f)
    sent = lit_points(sent_raw, args.samples, best[2])
    b2, o2, w2 = violations(zs, sent)
    print("Sent Stream (%s, match rms %.4f): %d lit samples, %d inside a Block zone, %d outside every Only-In zone"
          " (worst excess %.2g)" % (best[1], math.sqrt(best[0]), len(sent), b2, o2, w2))
    worst = max(w, w2)
    if not (b or o or b2 or o2):
        print("PASS")
    elif worst < margin:
        print("PASS/MARGIN: lit points crossed the compiled edge by up to %.4f, %.0f%% of the %.3f margin;"
              " nothing reached the zones as drawn" % (worst, 100 * worst / margin, margin))
    else:
        print("FAIL: lit points reached the drawn zones (%.4f past the edge, margin %.3f)" % (worst, margin))
        sys.exit(1)


if __name__ == "__main__":
    main()
