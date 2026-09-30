"""Laser frames: see what a Laser Out actually draws, cycle after cycle, and make glitches obvious.

Grabs Laser Out's own preview (the plot of what it sent, no projector, no previs, no fixture
model) as fast as capture allows (about 50 per second), then writes:

  <out>/frame_NNN.png        every grab, full size
  <out>/montage.png          all grabs tiled in order, so a dropped edge or stray line jumps out
  <out>/flicker.png          per pixel: how often it was lit. Steady content is bright; anything
                             that comes and goes shows as grey, stray lines as faint streaks
  and prints lit-pixel counts per grab with the spread.

A clean output of static content is pixel-identical every grab (spread 0). Moving content varies a
little with the motion; missing strokes and stray lines show as dips and spikes far outside that.

--freeze <node> first grabs a set with that node frozen (set_mode freeze), then unfreezes it and
grabs again: an A/B that tells an output problem that only happens while content changes from
one that is always there. The node is always returned to normal mode.

Before 0.5.98, record_pipeline recorded Laser Out's preview as black frames,
which is why this grabs stills. From 0.5.98 on, record_pipeline mode=png_sequence works too.

  python scripts/laser_frames.py [--node Laser_Sim] [--grabs 60] [--freeze Trace] [--out DIR]
"""
import argparse
import glob
import os
import sys
import time

import numpy as np
from PIL import Image

import lm_mcp


def grab(m, node, n, folder):
    os.makedirs(folder, exist_ok=True)
    for f in glob.glob(os.path.join(folder, "frame_*.png")):
        os.remove(f)
    t0 = time.time()
    for i in range(n):
        m.call("sentinel_capture", action="pipeline", pipeline_id=node,
               filepath=os.path.join(folder, "frame_%03d.png" % i))
    rate = n / (time.time() - t0)
    frames = [np.asarray(Image.open(f).convert("L")).astype(np.float32)
              for f in sorted(glob.glob(os.path.join(folder, "frame_*.png")))]
    return frames, rate


def report(label, frames, rate, folder, threshold):
    lit = [f > threshold for f in frames]
    counts = np.array([int(l.sum()) for l in lit])
    med = float(np.median(counts))
    spread = (counts.max() - counts.min()) / max(med, 1)
    print("%s: %d grabs at %.0f/s, lit px median %d, min %d, max %d, spread %.0f%%"
          % (label, len(frames), rate, med, counts.min(), counts.max(), 100 * spread))
    print("  per grab: " + " ".join(str(c) for c in counts))
    # Montage, half size, 10 across, with a grid.
    cols, sc = 10, 2
    small = [f[::sc, ::sc] for f in frames]
    h, w = small[0].shape
    rows = (len(small) + cols - 1) // cols
    M = np.zeros((rows * h, cols * w), np.float32)
    for i, s in enumerate(small):
        y, x = (i // cols) * h, (i % cols) * w
        M[y:y + h, x:x + w] = s
        M[y, x:x + w] = 80
        M[y:y + h, x] = 80
    Image.fromarray(M.clip(0, 255).astype(np.uint8)).save(os.path.join(folder, "montage.png"))
    # Flicker map: fraction of grabs each pixel was lit.
    frac = np.mean(np.stack(lit), axis=0)
    Image.fromarray((frac * 255).astype(np.uint8)).save(os.path.join(folder, "flicker.png"))
    return spread


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--node", default="Laser_Sim", help="the Laser Out node")
    ap.add_argument("--grabs", type=int, default=60)
    ap.add_argument("--freeze", help="upstream node to freeze for an A/B (e.g. Trace)")
    ap.add_argument("--threshold", type=float, default=120)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "..", "..",
                                                  "captures", "laser_frames"))
    args = ap.parse_args()
    out = os.path.abspath(os.path.join(args.out, time.strftime("%Y%m%d_%H%M%S")))
    m = lm_mcp.Client()
    time.sleep(0.5)
    if args.freeze:
        try:
            m.call("sentinel_pipeline", action="set_mode", pipeline_id=args.freeze, mode="freeze")
            time.sleep(0.5)
            frames, rate = grab(m, args.node, args.grabs, os.path.join(out, "frozen"))
        finally:
            m.call("sentinel_pipeline", action="set_mode", pipeline_id=args.freeze, mode="normal")
        report("%s frozen" % args.freeze, frames, rate, os.path.join(out, "frozen"), args.threshold)
        time.sleep(0.5)
    frames, rate = grab(m, args.node, args.grabs, os.path.join(out, "live"))
    report("live", frames, rate, os.path.join(out, "live"), args.threshold)
    print("wrote %s" % out)


if __name__ == "__main__":
    main()
