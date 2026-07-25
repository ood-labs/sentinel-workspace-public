#!/usr/bin/env python3
"""2B criterion 5: analyzer wall-time budget and graph-total impact.

`wall_time_ms` is a CPU wall-clock sample and is visibly noisy run to run, so
enabled/disabled samples are INTERLEAVED and compared by median. Taking all the
enabled samples first and all the disabled samples second lets ordinary drift
masquerade as the analyzer's cost - an earlier pass of this measurement swung
0.59 -> 0.73 ms between back-to-back runs with no code change in between.

Sampling runs during real File playback so the node does genuine catch-up work.
"""
import json, time
from pathlib import Path
import numpy as np
from sentinel_ipc import Sentinel, AudioRunner

HERE = Path(__file__).resolve().parent
cfg = json.loads((HERE / "lane_map_pulse2.json").read_text(encoding="utf-8"))
det, aud = cfg["detector"], cfg["audio"]
sen = Sentinel(); runner = AudioRunner(sen, aud, det, hits_port=cfg["hits_port"])
N = 14


def sample():
    p = sen.call("GET_GRAPH_PROFILE", summary=True, sort_by="wall_time_ms")
    nodes = {x["entity_id"]: x for x in p["nodes"]}
    n = nodes.get(det, {})
    return n.get("wall_time_ms", 0.0), p["frame"]["total_ms"], n.get("cook_hz")


def restart():
    runner.configure_file(HERE / "corpus" / "four_on_floor_128.wav")
    time.sleep(0.4)
    sen.set(f"/sentinel/pipelines/{aud}/parameters/restart_file", 1)


on_w, on_t, off_t, hz = [], [], [], []
restart()
time.sleep(1.0)
for i in range(N):
    if i % 12 == 0:
        restart(); time.sleep(0.8)
    sen.set(f"/sentinel/pipelines/{det}/enabled", True)
    time.sleep(0.55)
    w, t, c = sample()
    on_w.append(w); on_t.append(t)
    if c:
        hz.append(c)
    sen.set(f"/sentinel/pipelines/{det}/enabled", False)
    time.sleep(0.55)
    _, t2, _ = sample()
    off_t.append(t2)
sen.set(f"/sentinel/pipelines/{det}/enabled", True)

gw = sen.call("GET_GRAPH_PROFILE", summary=True, sort_by="wall_time_ms")
graph_hz = np.median([x["cook_hz"] for x in gw["nodes"] if x.get("cook_hz")])

w_med, w_mean = np.median(on_w), np.mean(on_w)
d = abs(np.median(on_t) - np.median(off_t))
print(f"samples: {N} interleaved pairs")
print(f"analyzer wall_time_ms : median {w_med:.3f}  mean {w_mean:.3f}  "
      f"p90 {np.percentile(on_w,90):.3f}  max {max(on_w):.3f}")
print(f"graph total_ms        : enabled {np.median(on_t):.3f}  disabled {np.median(off_t):.3f}  delta {d:.3f}")
print(f"analyzer cook_hz {np.median(hz):.2f} vs graph cook_hz {graph_hz:.2f}")
print()
print(f"criterion 5a wall <= 0.6 ms (mean of 5+)  : {w_mean <= 0.6}  ({w_mean:.3f} ms)")
print(f"criterion 5b graph total within 0.5 ms    : {d <= 0.5}  (delta {d:.3f} ms)")
print(f"criterion 5c cook_hz matches graph rate   : {abs(np.median(hz)-graph_hz) < 1.0}")
