---
name: laser-trace-tuning
description: Dial in Laser Trace and Laser Out on real scanners. Covers the trace graph (content, square crop or Depth Slice, Laser Trace, Laser Out over ShowNET), arming and link stability, the scanner protection profile and speed-aware retiming, Trace parameter tuning by symptom, depth-slice line content from StreamDiffusion, and the offline bench against MadMapper. Use when a traced path is incomplete, flickers, blanks, stutters, drops the link, refuses to arm, or when preparing new content for the tracer.
---

# Laser Trace Tuning

Laser Trace (`lasertrace`) turns pixels into ordered Scan Signal paths. Laser
Out (`laserout`) plays them through scanner protection to a DAC. Most "the
laser is not drawing the whole thing" problems come from Laser Out timing or
protection, not from the trace. Check the trace preview first: if the path is
complete there, tune Laser Out.

Safety rules that always apply:

- Arming is operator-only. Never set `armed` or the master arm from automation.
- Never loosen the scanner profile (`max_step`, `max_step_change`,
  `min_visible_speed`, `speed_window`, dwell and guard values) without the
  operator's explicit approval. Raising a limit lets the galvos move harder.
- ShowNET credentials are NDA-confidential. They live only in
  `~/.sentinel/shownet_credentials.txt` via `SHOWNET_CREDENTIALS_FILE`; never
  echo them into chat, docs, commits or logs.
- Never kill or relaunch MadMapper, and never send it OSC while it is running
  a show; an earlier OSC send crashed it.

## The graph

```
content ──► Square_Crop (square-crop Module, 1080 x 1080) ──► Trace ──(Scan Signal, slot 1)──► Laser Out (shownet)
StreamDiffusion Depth (slot 1) ──► Depth_Slice ──────────────► Trace                        └─► Laser Out (record)
```

- Feed Trace square content. Scan Signal coordinates are normalised by the
  longest side, so a 16:9 frame wastes scanner area and the crop keeps the
  preview and the wall in the same frame. Crop a 1920 x 1080 source to a
  width of 0.5625 for an exact square.
- Trace output slot 0 is the preview texture; slot 1 is the Scan Signal.
- A `record` Laser Out on the same Scan Signal is a free timing oracle: it
  writes exactly what would have been sent.

## Arming and link stability

- The node arm now applies the requested `point_rate` at the moment of arming.
  Before the fix, every launch sat at 20 kpps and arming was refused silently
  until someone pressed Apply. The status line shows `pending=<rate> (Apply)`
  while the two differ; that is expected before arming.
- Node arms are saved with the project and survive a dropped link; only the
  laser master needs arming after a launch. A changed input element count
  counts as a re-route, and a re-route closes and reopens the ShowNET session. Any Scan Signal producer must publish
  a fixed element count (Trace always spans the 4096-record buffer and carries
  the live count in the header). If the link reopens every few hundred ms,
  suspect a producer whose element count changes per frame.
- Watch for drops with a log monitor on `%APPDATA%\Sentinel\logs\sentinel.log`
  counting `link dropped` lines. The drop warning carries the SDK error, frame
  size and rate.
- `WriteFrame` error -3 means device lost. The output keeps its arm and
  blanks until the session reopens (`link restored` in the log). After force-killed
  sessions the box can report device lost every few seconds; power-cycle the
  box, then relaunch Sentinel. `libShowNet.dll` can crash Sentinel when the
  box is power-cycled under an open session, so expect one crash and relaunch.
- Stop Sentinel with `sentinel_app kill` (graceful) rather than a forced
  taskkill whenever the link is open.
- When Sentinel hangs (for example a StreamDiffusion engine load), Laser Out's
  dead-man blanks output. That is correct behaviour.

## Scanner protection and timing

Laser Out walks the Scan Signal, retimes it, then passes every sample through
`ScannerProtection`:

- A move whose per-sample distance is within
  `min(max_step, max_step_change / 2)` goes straight through. Anything larger
  becomes a rest-to-rest quintic ease, which reads as stop-and-go and makes
  the cycle longer than authored.
- The slow-beam guard averages lit speed over `speed_window` samples and
  blanks samples whose average is at or below `min_visible_speed`. A lit path
  that moves too slowly disappears in sections.

Speed-aware retiming (`ScanSignalWalker::submit`, `SpeedBounds`): when
`desired_fps > 0`, lit travel per output sample is kept between
`1.5 x min_visible_speed` and `0.9 x min(max_step, max_step_change / 2)`,
measured after `amplitude_limit`. `desired_fps` is a target that gives way to
those bounds: short content draws fast enough to stay visible, dense content
slows until the protection stops easing. One setting (60) works for a single
depth line and for the full grid. `desired_fps 0` keeps the producer's
authored timing and skips these bounds; avoid it for traced content.

Changing `desired_fps`, `amplitude_limit`, the applied rate or any of the
three speed limits retimes the current snapshot immediately.

Operator mapping profile for the DS-3000 RGB at full amplitude. It is used for
the alignment grid and every earlier mapping session, and draws the 4x4 grid through Laser_Map at
about 20 fps:

| Parameter | Value |
|---|---|
| amplitude_limit | 1.0 |
| max_step / max_step_change | 0.5 / 0.5 |
| min_visible_speed / speed_window | 0.0005 / 64 |
| blank_guard / end_dwell / corner_dwell | 13 / 5 / 5 |
| desired_fps | 72.742 |

With the tighter bench profile below at amplitude 1.0, the same grid crawls at
about 6 fps.

Tighter bench profile at amplitude 0.25, used for the first traced content:

| Parameter | Value |
|---|---|
| point_rate | 30000 |
| desired_fps | 60 |
| amplitude_limit | 0.25 |
| max_step / max_step_change | 0.02 / 0.01 |
| min_visible_speed / speed_window | 0.0015 / 64 |
| blank_guard / end_dwell / corner_dwell / insert_cap | 17 / 9 / 0 / 64 |
| flip_y | true |

With these limits the lit step window is 0.00225 to 0.0045 per sample. At
30 kpps and amplitude 0.25 (a frame 0.5 output units wide) that is about 2.25
to 4.5 frame widths of lit travel per 1/60 s, so content longer than that
refreshes below 60 fps by design.

## Symptoms

| Symptom | Likely cause | What to do |
|---|---|---|
| Path complete in the Trace preview, incomplete on the wall, worse with less geometry | Slow-beam guard: lit speed below `min_visible_speed` | Make sure `desired_fps > 0` so the speed bounds apply; check `amplitude_limit` is not tiny |
| Path complete in preview, stutters or corners bulge on dense content | Steps larger than the direct-path limit, protection easing | Retiming handles it with `desired_fps > 0`; faster refresh needs a higher `max_step_change`, operator approval only |
| Link reopens every few hundred ms, arm drops | Producer element count changing per frame | Fix the producer to publish a fixed element count |
| Node arm does nothing | Refused arm (e-stop, master arm, device lost) | Read the log; the rate mismatch no longer blocks arming |
| Device lost loop | Stale box session | Power-cycle the box, relaunch Sentinel |
| Refresh visibly flickers | Too much lit length for the rate | Reduce content (bands, `min_length`, `max_paths`), or raise `point_rate` within the DAC's rating |
| Trace path wrong in the preview | Trace parameters or content | See the next section |

## Trace parameters

Use `display` to see what the tracer sees: Processed (binary), Polylines,
Processed + Polylines, Order (hue by tour position, grey blank jumps, white
start dots). The status line reads `N strokes, M segments, X ms`, and
`cpu_ms`, `blank_ratio`, `strokes`, `match_rate` and `overflow_count` are
live control outputs.

| Parameter | Default | Notes |
|---|---|---|
| channel | Luma | Max RGB traces any lit colour; pair with `use_color` to send source colours at full brightness |
| threshold / threshold_low | 0.3 / 0.15 | Hysteresis; lower `threshold_low` to keep faint continuations attached |
| working_res | Source | 720 or 540 cut trace time roughly by the pixel ratio; lines under 2 px may break |
| mode, max_line_width | Auto, 10 | Auto traces a component as contours when its mean width exceeds `max_line_width`; thin lines stay single centerlines |
| simplify_px | 1 | Douglas-Peucker tolerance. 3 or more visibly polygonises curves |
| spur_px | 2 | Prunes short branches; large values (tens of px) eat real line ends |
| join_gap_px | 4 | Bridges collinear gaps |
| min_length, max_paths, keep | 0, 1024, Longest | Content reduction when the laser flickers |
| stability | 0.7 | Temporal coherence: 0 always re-optimises; higher keeps order, direction and loop starts steady at some blank cost |
| desired_fps (Trace) | 60 | Authored timing only; Laser Out retimes |

Content that traces best: white one-to-five pixel lines on black, square
frame, no anti-aliased halos wider than `max_line_width`. Filled shapes trace
as outlines in Auto.

## Depth slices from StreamDiffusion

A depth-slice Module turns a depth map into contour lines built for Trace:
StreamDiffusion `Depth` (slot 1) into `Depth_Slice`, `Depth_Slice` into Trace.

| Parameter | Effect |
|---|---|
| bands | Number of evenly spaced depth levels in the window |
| near / far | Depth window; nearer than `near` is dropped, farther than `far` is background |
| offset | Slides the levels through depth; animate it for moving slices |
| smooth | Box smoothing radius in px before quantising; raise it for noisy depth |
| merge | Crossings closer than this fuse into one stroke, so a depth cliff crossing several bands becomes one line |
| silhouette | Draws the far cut as an outline of the subject |
| invert | Flip depth polarity |

StreamDiffusion saved in Freeze mode can reload with no snapshot and emit
nothing; set it back to Normal after loading the project.

## Performance

Laser Trace runs its per-pixel work on the GPU and ships only a raster-ordered
list of foreground candidates to its worker thread. Worker cost scales with lit
pixels, not frame area.

- **Live readouts.** The graph node footer always shows
  `strokes | worker ms | GPU ms | traces/s`, in amber when over budget. The
  control outputs are `cpu_ms` (worker), `gpu_ms` (GPU passes), `render_ms`
  (render thread, smoothed) and `over_budget`. The Stats panel and
  `sentinel_graph profile` carry the same GPU timing.
- **Typical worker cost at 1080:**
  - a depth slice under 1 ms;
  - drift and simple shapes about 1 ms;
  - grid about 3 ms;
  - dense isolines about 10 ms.

  Eight nodes held 60 fps with frame p99 10.4 ms.
- **Over budget.** More than 300,000 candidate pixels (about 26 percent of a
  1080 square frame) sets `over_budget`, and the node keeps its last trace.
  Filled or noisy content should be edge-detected or sliced first, like Depth
  Slice.
- **Headroom.** `working_res` 720 or 540 cuts worker cost roughly by the pixel
  ratio. Watch lines narrower than 2 px.


## Colour

- **Channel.** Colour content needs `channel` set to Max RGB. The default Luma
  weights pure red at 0.21 and blue at 0.07, so red and blue lines fall under
  the 0.3 threshold and disappear. Dim colours also need Max RGB.
- **`color_mode`.**
  - Stroke (the default) gives each path one averaged colour. A red line
    touching a green one draws as yellow.
  - Along path samples colour at every path point. It draws gradients, rainbow
    loops and colour changes along a line, and keeps a breakpoint wherever the
    colour departs from a straight blend.
  - Along path also makes junctions prefer same-colour continuations. Where
    another line crosses, the short off-colour run takes the colour of the line
    around it.
  - It costs about 0.2 ms more per trace.
- **`color_delay` (Laser Out).** When colour spills into the next segment or
  starts before a line, shift it in samples. A positive value delays colour and
  a negative value makes it lead. Dial it in on the RGB lines or end-to-end
  pattern, 1 to 3 samples at a time.
- **`brightness`.** Normalize draws every colour at full output. Keep
  preserves source brightness, so dim lines stay dim.
- **Shallow crossings.** A crossing can split one line into two paths at the
  junction. Each piece keeps its own colour, and the split adds one blank jump.
- **Test content.** Check colour on RGB lines, a crossing, curves, an
  end-to-end line, a rainbow circle, a gradient, dim and bright lines, and a
  mixed pattern before trusting a colour setting on a show.

## References

- Content authoring: the `laser-content-authoring` skill
