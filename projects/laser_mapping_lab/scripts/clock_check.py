"""Clock check: does a Laser Out draw every content frame, once, at a steady delay?

Laser Out plays one cycle per content snapshot at the DAC's own point clock. If that clock runs at
a different rate from the one Laser Out plans cycles with, the laser's cycle rate drifts against
the content's frame rate. Faster content means frames are replaced before they're drawn (the motion
jumps ahead); slower content means frames are drawn twice (the motion holds). Either way the
laser-to-projector delay creeps and snaps, which a rotating shape or Alignment_Grid's Sync Sweep
makes plain on the wall.

Samples a Laser Out node for a while and prints:
  - the point rate requested and the rate the DAC reports actually playing (min / mean / max)
  - cycles the laser drew per second (cycle_generation) against the content's frames per second
  - the expected frame skips (or repeats) per second from that difference, and what Laser Out's
    own snapshots_dropped counter says over the same time

  python scripts/clock_check.py [--node Laser_Sim] [--content Adaptive_Mapping] [--seconds 10]
"""
import argparse
import time

import lm_mcp


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--node", default="Laser_Sim", help="the Laser Out node (armed, playing content)")
    ap.add_argument("--content", default="Adaptive_Mapping", help="the node feeding it")
    ap.add_argument("--seconds", type=float, default=10)
    args = ap.parse_args()
    m = lm_mcp.Client()
    time.sleep(0.5)

    def snap():
        r = m.call("sentinel_pipeline", action="info", pipeline_id=args.node)
        d = {c["name"]: c["value"] for c in r["control_outputs"]}
        return time.time(), d, r["metadata"], r["stats"]["statusMessage"]

    t0, d0, md0, status = snap()
    print(status)
    requested = float(m.call("sentinel_state", action="get",
                             path="/sentinel/pipelines/%s/parameters/point_rate" % args.node)["value"])
    desired = float(m.call("sentinel_state", action="get",
                           path="/sentinel/pipelines/%s/parameters/desired_fps" % args.node)["value"])
    rates, content = [], []
    t = t0
    while t - t0 < args.seconds:
        time.sleep(0.25)
        t, d, md, _ = snap()
        rates.append(d["dac_point_rate"])
        content.append(m.call("sentinel_pipeline", action="info", pipeline_id=args.content)["stats"]["fps"])
    t1, d1, md1, _ = snap()
    dt = t1 - t0
    cycles = (int(md1["cycle_generation"]) - int(md0["cycle_generation"])) / dt
    fps = sum(content) / len(content)
    dropped = (d1["snapshots_dropped"] - d0["snapshots_dropped"]) / dt
    print("point rate: requested %.0f, DAC plays %.0f / %.0f / %.0f (min / mean / max), %.1f%% off"
          % (requested, min(rates), sum(rates) / len(rates), max(rates),
             100 * (sum(rates) / len(rates) - requested) / requested))
    print("laser %.2f cycles/s (Desired FPS %.1f)  vs  content %.2f frames/s" % (cycles, desired, fps))
    gap = fps - cycles
    if abs(gap) < 0.05:
        print("locked: every content frame is drawn once")
    elif gap > 0:
        print("%.2f content frames/s are never drawn: the motion jumps ahead about every %.2f s" % (gap, 1 / gap))
    else:
        print("%.2f frames/s are drawn twice: the motion holds about every %.2f s" % (-gap, 1 / -gap))
    print("Laser Out's snapshots_dropped over the same %.1f s: %.2f/s" % (dt, dropped))


if __name__ == "__main__":
    main()
