"""Proof harness: map the laser Alignment Grid onto the PROJECTED Alignment Grid by
dragging the Mapping Editor's corner handles with real drag gestures, exactly as a
person would. Not part of the graph; it only exercises it.

It reads the Laser_Fixture pose and Laser_Out flips live, inverts the fixture's
optics (Laser Lab LS_Projector: flips, x mirror, scan angles, pitch then yaw) to
find the scan point that lands on each tape corner, converts that to a handle
position, and drags the handle there in the open Mapping Editor panel.

Usage (Sentinel running, Mapping Editor panel open): python scripts/map_to_tape.py [--edges]
"""
import math
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lm_mcp import Client  # noqa: E402

# The video projector maps its image onto the taped frame (Laser_Previs/site.hlsli), so the
# projected grid's outer lines sit at Alignment_Grid extent x the frame half-size.
FRAME_C = np.array([0.0, 1.5])
FRAME_HALF = np.array([1.5, 0.9])


def get(c, node, name):
    v = c.call("sentinel_state", action="get", path=f"/sentinel/pipelines/{node}/parameters/{name}")["value"]
    return v in ("true", "1") if isinstance(v, str) and v in ("true", "false") else float(v)


def land(xy, P):
    """LS_Projector directionFor + wall hit, for one scan point (pre-flip, as sent by Laser Out)."""
    x, y = xy
    if P["flip_x"]:
        x = -x
    if P["flip_y"]:
        y = -y
    x = -x  # BLINK: right-handed room frame
    d = np.array([x * math.tan(math.radians(P["scan_x"] * .5)), y * math.tan(math.radians(P["scan_y"] * .5)), 1.0])
    d /= np.linalg.norm(d)
    p, yw = math.radians(P["aim_pitch"]), math.radians(P["aim_yaw"])
    d = np.array([d[0], d[1] * math.cos(p) + d[2] * math.sin(p), d[2] * math.cos(p) - d[1] * math.sin(p)])
    d = np.array([d[0] * math.cos(yw) + d[2] * math.sin(yw), d[1], d[2] * math.cos(yw) - d[0] * math.sin(yw)])
    o = np.array([P["position_x"], P["position_y"], P["position_z"]])
    t = -o[2] / d[2]
    return (o + d * t)[:2]


def inverse(target, P):
    s = np.zeros(2)
    for _ in range(60):
        f = land(s, P) - target
        J = np.zeros((2, 2))
        for k in range(2):
            ds = np.zeros(2); ds[k] = 1e-6
            J[:, k] = (land(s + ds, P) - land(s, P)) / 1e-6
        s = s - np.linalg.solve(J, f)
    return s


def main():
    with Client() as c:
        P = {k: get(c, "Laser_Fixture", k) for k in ("scan_x", "scan_y", "aim_yaw", "aim_pitch", "position_x", "position_y", "position_z")}
        P["flip_x"] = get(c, "Laser_Out", "flip_x")
        P["flip_y"] = get(c, "Laser_Out", "flip_y")
        slot = int(get(c, "Mapping_Editor", "slot"))
        ext = get(c, "Mapping_Editor", "extent_" + "abc"[slot])
        info = c.call("sentinel_pipeline", action="info", pipeline_id="Mapping_Editor")
        rect = info["panel"]["view"]["content_rect"]
        W, H = info["panel"]["render_size"]
        sx = (rect[2] - rect[0]) / W
        view = c.port("Mapping_Editor", "Canvas State", 1)[0]["state"]

        def client(uv):
            px = (np.array(uv) - view[:2]) * view[2] * min(W, H) + 0.5 * np.array([W, H])
            return rect[0] + px[0] * sx, rect[1] + px[1] * sx

        # Handle index -> which tape corner. Editor uv y grows downward = scan +y;
        # with Laser Out flip_y the top of the editor is the top of the wall.
        gext = get(c, "Alignment_Grid", "extent")                 # projected grid spans +-extent of the frame
        corners = {0: (-1, 1), 4: (1, 1), 20: (-1, -1), 24: (1, -1)}
        if not P["flip_y"]:
            corners = {k: (sxn, -syn) for k, (sxn, syn) in corners.items()}
        base = slot * 52                                    # each slot is a 52-element bank
        pts = c.port("Mapping_Editor", "Mapping Points", base + 25)
        for k, (cx, cy) in corners.items():
            target = FRAME_C + FRAME_HALF * gext * np.array([cx, cy])
            s = inverse(target, P)                          # scan point that lands on the tape corner
            uv = ((s / ext) + 1) * 0.5 * 0.8 + 0.1           # handle uv (lattice corner = grid corner)
            cur = pts[base + k]["position"][:2]
            a, b = client(cur), client(uv)
            print(f"handle {k:2d}: uv {np.round(cur, 4)} -> {np.round(uv, 4)}  (projected grid corner {np.round(target, 3)})")
            c.call("sentinel_ui", action="drag_at", start_x=a[0], start_y=a[1], end_x=b[0], end_y=b[1],
                   button=0, steps=16, duration_ms=500)
            time.sleep(0.4)
            pts = c.port("Mapping_Editor", "Mapping Points", base + 25)
        print("slot", "ABC"[slot], "final corners:", [np.round(pts[base + k]["position"][:2], 4).tolist() for k in corners])


if __name__ == "__main__":
    main()
