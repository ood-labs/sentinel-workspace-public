---
name: laser-show-setup
description: Get a laser show running in Sentinel end to end. Laser Out on Simulate first, then Ether Dream, LaserCube or ShowNET (DS-3000) hardware, the two arms, first light and orientation, the scanner profile, Frame Lock and Output Delay against a projector, several lasers, and looks that switch video and laser together. Use when a user connects a laser, asks why a laser is dark, flickers or drifts from the video, or wants to build a laser show.
---

# Laser Show Setup

Read `knowledge/laser-output.md` first; it has every Laser Out setting. For
what to draw, use `laser-content-authoring` (Modules that write Scan Signals)
or `laser-trace-tuning` (Laser Trace from pixels). For mapping onto a surface,
read `knowledge/laser-mapping.md` and open `projects/laser_mapping_lab`. For
looks that carry video and laser paths together, read
`knowledge/bundle-links.md`.

## Rules that do not bend

- Build and prove everything on `protocol=simulate`. It runs the full output
  (protection, retiming, Sent Stream, preview, badges) with no hardware and no
  light.
- Never arm the laser master. Only a person clicking **ARM LASERS** in the
  menu bar can. When the show is ready, say so and let the operator arm.
- Never loosen the scanner profile (`max_step`, `max_step_change`,
  `min_visible_speed`, dwell and guard values) to make content fit. Reduce the
  content instead. A change to a working rig's profile needs the operator.
- Read the current arm state immediately before any change that could move
  the beam, and prepare changes with the output disarmed.
- Feed `Sent Stream`, never the raw Scan Signal, to anything that shows the
  beam (previs, haze, sparks).

## Workflow

1. **Ping and discover.** `sentinel_app action=ping`, then
   `sentinel_pipeline action=list_types` to confirm `laserout` and
   `lasertrace` exist in this build.
2. **Content.** Build or open the look that makes the Scan Signal. Check it in
   the producer's preview (Laser Trace's `display` shows the paths it found).
3. **Laser Out on Simulate.** `sentinel_pipeline action=create type=laserout
   name=Laser_A`, link the Scan Signal into it with `sentinel_graph
   action=add_link`, arm the node (Simulate needs only its own arm), and read
   `sentinel_pipeline action=info`: the badge reads LIVE, `scan_fps` is near
   `desired_fps`, and `clamp_trips` stays still. CLAMP or a low `scan_fps`
   means the content asks for more than the profile allows; simplify it now,
   before hardware.
4. **Hardware.** The operator connects the DAC. Set `protocol` and `device`
   (IP or MAC; empty takes the first discovered). Changing either disarms.
   Check Properties lists the device. In a trial install, hardware protocols
   run as record and open no link.
5. **First light, with the operator.** Small `amplitude_limit` (new nodes
   start at 0.25), the projector aimed at a wall with nobody in the beam, node
   armed, then the operator clicks ARM LASERS. Check orientation with
   `test_pattern` Orientation F (upright and unmirrored from the audience
   side; fix with `flip_x`, `flip_y`, `rotate_180`), then return the pattern
   to Input and let the operator raise the amplitude.
6. **Sync with video.** Keep `frame_lock` on and `desired_fps` above 0. The
   status line ends with `frame lock`. Measure the projector's latency with
   the Sync Sweep in `laser_mapping_lab` and set `output_delay_ms`.
7. **Save.** The node arm saves with the project; the master never does, so
   the show reopens held off until the operator arms.

## Several lasers and looks

- One Laser Out per laser, each with its own `device`. They run on
  independent clocks and Frame Lock holds each to the same content frames.
- Put each look in a Scene Group whose Module publishes a bundle with one
  `laser.<name>.scan` channel per laser plus the projector video. A Groups
  Mux switches looks; Bundle Split peels each laser's channel off for its
  Laser Out. Give laser channels `transition: {mode: handoff}` with
  `neutral: empty` so a fade blanks one path before the next appears.
- `laser_mapping_lab` is the worked example: copy its Shapes look to start a
  new one.

## When it goes wrong

| Symptom | Check |
|---|---|
| Dark, badge BLANKED | `blanked_reason` in Properties: an arm missing (node or master), dead-man expired (input older than `deadman_ms`), or invalid input |
| Amber ARM, INHIBIT | The master is off. Tell the operator; never try to arm it |
| CLAMP | Content moves faster than the profile allows; simplify it, or turn `desired_fps` on so lit travel is retimed |
| Flicker | Too much lit length for the point rate; reduce content or raise `point_rate` within the DAC's rating |
| Drifts behind video, jumps ahead once a second | `frame_lock` off, `desired_fps` 0, or content too dense to hold the frame rate |
| Laser and projector offset in time | `output_delay_ms`, measured with the Sync Sweep |
| Mirrored or upside down | `flip_x`, `flip_y`, `rotate_180` with Orientation F |
| Link drops, device lost | Power-cycle the DAC, then relaunch Sentinel; check the adapter and the `device` address |

Protection bounds scanner motion. It does not certify audience safety; the
operator owns the rig, the zones and the arm.
