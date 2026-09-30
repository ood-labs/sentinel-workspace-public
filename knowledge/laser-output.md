# Laser Output: Laser Out, Arming, Sync And First Light

`laserout` (Laser Out) sends laser content to one projector. It takes a `Scan
Signal` data input (timed XY segments with colour), runs it through scanner
protection, and plays it over a transport. It also publishes what it actually
sent as a `Sent Stream` data output with the same layout, and draws a live
preview of the sent beam in its node body. Use one Laser Out per projector;
each runs on its own clock.

Content comes from three places:

- A Module that writes a Scan Signal directly (point streams, vector shapes,
  text). See the `laser-content-authoring` skill.
- Laser Trace (`lasertrace`), which turns pixels (a render, a video, depth
  slices) into ordered Scan Signal paths. See the `laser-trace-tuning` skill.
- A mapped look from a surface mapping chain. See `laser-mapping.md` and the
  `laser_mapping_lab` example.

## Protocols

`protocol` picks the transport. Changing it, or `device`, disarms the output.

| Protocol | What it does | Needs the master arm |
|---|---|---|
| `simulate` | The default. Runs the full output (protection, retiming, Sent Stream, preview, badges) against a virtual DAC. Opens no link, writes no file. Use it to build and preview a show with no hardware. | No |
| `record` | Simulate plus a file: every sent sample and event goes to `captures/laser/<node>.jsonl` in the workspace (about 3 MB/s, rolled at 512 MB, four files kept). | Yes |
| `etherdream` | Ether Dream DAC on the network. | Yes |
| `lasercube` | LaserCube over the network. | Yes |
| `shownet` | Laserworld ShowNET boards such as the DS-3000. Sentinel paces frames itself and the board replays the current frame until the next arrives. | Yes |

`device` is the DAC's IP or MAC address (Ether Dream also takes `ip:port`).
Leave it empty to take the first device discovery finds; the discovered list
shows in Properties and in the node's `devices` status. Set it explicitly as
soon as more than one DAC is on the network.

`point_rate` is the requested samples per second (1,000 to 40,000, default
20,000), capped by what the device reports. While armed, press **Apply Point
Rate** to send a new rate; arming sends it too. With **Scale Limits With
Rate** on (the default), a new rate rescales the scanner limits so the
mirrors keep the same physical speed.

In a trial install, Ether Dream, LaserCube and ShowNET run as record: the
output arms, writes the record file and publishes its Sent Stream, but opens
no link. Simulate stays Simulate. A license makes them live on the next tick,
and each output then needs a fresh arm.

## Arming

Light needs two arms:

1. **The output's own ARM**, in the node header (the `armed` parameter). It is
   saved with the project, so a show reopens with its outputs selected but
   held off. Presets, Scene Group recalls, binds and undo never store or
   replay it.
2. **The laser master**, the **ARM LASERS** button in the menu bar. It is
   never saved, starts disarmed on every launch, and arms only from a real
   click. Automation, OSC, expressions and project loads can disarm it and
   can never arm it.

An armed output with the master off shows amber ARM and the INHIBIT state. A
Simulate output ignores the master (it emits no light), shows a blue ARM
button and never reads INHIBIT.

E-stop latches a stop and disarms: press `Shift+Escape` anywhere (it stops
every Laser Out), click **E-stop** in the node's Properties, set `/sentinel/pipelines/<id>/parameters/estop` to 1 over MCP
or OSC, or drive that parameter with an expression. A device fault,
interlock or temperature report also disarms. A dropped ShowNET link keeps the
arm: the output blanks, the link reopens, and output resumes under the master.

For an agent: build and prove everything on `simulate`, then hand over. Never
try to arm the master; tell the operator the output is ready and let them
click ARM LASERS.

## First light on a real projector

1. Create the node: `sentinel_pipeline action=create type=laserout name=Laser_A`.
   It starts on `simulate`, disarmed, with the show scanner profile.
2. Wire content into its `Scan Signal` input with `sentinel_graph
   action=add_link`, and check the node preview draws the shape you expect.
3. Point the projector at a wall with nobody in the beam. Keep
   `amplitude_limit` small for the first frames; a new node starts at 0.25 of
   the full scan angle.
4. Set `protocol` to the transport and `device` to the DAC's address. Check
   Properties shows the device as discovered.
5. Arm the output (header ARM), then the operator clicks ARM LASERS. The badge
   reads LIVE while content plays.
6. Check orientation with **Test Pattern → Orientation F**: the F reads
   upright and unmirrored from the audience side. Fix it with `flip_x`,
   `flip_y` or `rotate_180`. Flip X off is front projection (the ILDA
   convention); turn it on for a rear screen.
7. Raise `amplitude_limit` to the size the show needs.

Test patterns (`test_pattern`): **Input** plays the Scan Signal; **Orientation
F**, **Geometry** and **RGB and White** are built in; **ILDA Test (file)**
plays an ILDA test file (`ilda_file`, sized by `ilda_test_size`) one point per
sample, unprotected, at the file's rated rate. The ILDA test blanks unless the
applied point rate is within 1 percent of the file's rate, and selecting it or
loading a file disarms the output.

## Badges and what they mean

| Badge | Meaning |
|---|---|
| LIVE | Content is playing |
| BLANKED | Output is dark; Properties shows the reason (no input, dead-man expiry, invalid input, disarmed) |
| CLAMP | Scanner protection is steadily changing the lit output: the content asks for moves faster than the scanner profile allows |
| STOP | E-stop latched |
| ILDA TEST | The ILDA test file is playing |

A dark output with a healthy input usually means an arm is missing, the
dead-man expired (`deadman_ms`, input older than 500 ms by default), or the
content failed validation; read `blanked_reason` in Properties or
`sentinel_pipeline info`.

## Scanner protection

Protection shapes every sample the scanner receives. Content cannot remove it.
The defaults are a show profile tuned on a DS-3000 over ShowNET and a
LaserCube at 20 kpps:

| Parameter | Default | What it does |
|---|---|---|
| `max_step` | 0.074 | Largest XY move per sample |
| `max_step_change` | 0.143 | Largest change in the move per sample (acceleration) |
| `min_visible_speed` | 0.002 | Blanks lit motion slower than this, so a still point cannot burn |
| `speed_window` | 64 | Samples in the speed average |
| `duty_limit`, `duty_attenuation` | 0.6, 0.5 | Shrinks the field while the scanner runs at high speed too long |
| `blank_guard` | 25 | Blank samples around lit runs (blank delay) |
| `end_dwell` | 8 | Lit samples held at a stroke's end |
| `corner_dwell` | 8 | Lit samples held at sharp corners |
| `insert_cap` | 16 | Bounds interpolation per authored sample |
| `color_delay` | 0 | Shifts colour against position in samples, for a projector whose colour lags its mirrors |

These protect the scanner's motion. They do not certify audience safety.

`desired_fps` (default 60) is the scan rate to aim for. Laser Out measures
the time protection adds to each frame and retimes the lit travel to fit the
rest. Content too dense to fit runs at its speed limit, and `scan_fps` reports
the lower rate. Reduce the content (fewer strokes, lower resolution in Laser
Trace) rather than loosening the limits.

## Keeping the laser in sync with video

**Frame Lock** (`frame_lock`, on by default) draws each content frame exactly
once at a steady delay behind the render: about 2.5 content frames (about
42 ms at 60 fps). Without it, the DAC's clock and the render clock drift apart
and the laser creeps behind the video, then jumps ahead by a frame about once
a second. Locked, the status line ends with `frame lock`, `frames_skipped`
and `frames_repeated` stay still, and `frame_latency_ms` holds steady. Frame
Lock needs `desired_fps` above 0.

**Output Delay** (`output_delay_ms`, 0 to 500) holds the laser back to match a
projector's latency, on top of Frame Lock's delay. Measure it with the Sync
Sweep pattern in `laser_mapping_lab` (see that project's README): a line
sweeps on both the laser and the projector, and a ruler on the projector
reads how many milliseconds early or late the laser is.

## Monitoring

- The node preview draws the last sent block: coloured lit samples, dim blank
  travel and the amplitude box. `sentinel_capture action=pipeline` and
  `record_pipeline` read this preview.
- Control outputs for expressions and proof: `scan_fps`, `planned_scan_fps`,
  `points_per_second`, `frames_skipped`, `frames_repeated`,
  `frame_latency_ms`, `frame_locked`, `underflows`, `send_errors`,
  `link_lost`, `clamp_trips` and the other `*_trips` counters.
- `Sent Stream` carries exactly what was sent, including blank runs. Feed it,
  never the raw Scan Signal, to anything that visualises the beam (haze,
  sparks, previs), so the visuals show what the audience sees.

## Several lasers

Give each projector its own Laser Out. A look that drives several lasers
publishes one Scan Signal per laser, for example as keys in a Laser Look
bundle split by Bundle Split (see `laser_mapping_lab`), and each lane feeds its
own Laser Out. The lasers keep independent clocks; Frame Lock holds each one
to the same content frames.

## Automation notes

- Wire with `sentinel_graph action=add_link`, then `sentinel_graph
  action=auto_layout` or `layout_neighborhood`.
- Read state with `sentinel_pipeline action=info pipeline_id=<id>`:
  `statusMessage`, `blanked_reason`, `devices` and the control outputs.
- Operator modes: Freeze holds the last sent cycle and Bypass passes the Scan
  Signal straight to Sent Stream; both stop the sender. Use Normal for any
  measurement of real output.
