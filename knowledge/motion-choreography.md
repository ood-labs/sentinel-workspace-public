# Motion Choreography And Sequencing

Sentinel has a time-structuring system for choreographed animation: a shared motion vocabulary (springs, staggers, seamless loops), a `conductor` pipeline that owns musical and timecode clocks, cue sheets that compile into live expressions, and a `timeline_hud` module that visualizes the arrangement. Use this page when a scene needs staggered entrances, beat-locked hits, scene hand-offs, or precisely timed sequences rather than free-running LFOs.

## Motion Vocabulary (anim.hlsli + ExprTk)

Module shaders include the shared header:

```hlsl
#include "../_shared/anim/anim.hlsli"
```

- `an_spring(t, m, k, c)`: closed-form spring progress from 0 to 1.
- `an_spring_v(t, x0, v0, m, k, c)`: the same spring evaluated from a stamped initial value and velocity.
- `an_stagger_index`, `an_stagger_radial`, `an_stagger_wave`, `an_stagger_noise`: per-instance delays. Canonical use is `local_t = max(0, T - delay)`.
- `an_anticipate(t, bias)`: back-ease anticipation (moves opposite the travel direction first).
- `an_squash(vel_approx, gamma)`: volume-preserving stretch/squash scale pair.
- `an_loop_noise(t, period, radius, seed)`: noise that is seamless when `t` advances by `period`.

Preset spring triples: `AN_BOUNCY`, `AN_SNAPPY`, `AN_SMOOTH`, `AN_HEAVY` as `(mass, stiffness, damping)`. Prefer switching presets over authoring separate curves.

The same equations are registered in the expression engine as `spring`, `spring_v`, `stagger`, `anticipate`, and `loop_noise`, so parameter expressions and shader motion share one reference. Do not hand-roll springs or staggers in either place.

## Continuity Rules

- Rate-class changes (speed ramps, tempo drift, LFO frequency rides) must use phase accumulation: `phase += rate * dt` in a persistent buffer or the Conductor's transports. Never compute `absolute_time * live_rate`; a live rate change rescales history and pops.
- Target-class changes (cue jumps, new targets) use retarget stamps: stamp the current value and velocity, then continue with `an_spring_v` so value and velocity stay continuous. The Conductor does this automatically on `jump`.

## The Conductor Node

Create with `sentinel_pipeline action=create type=conductor`. It processes no video; it publishes clocks, cue envelopes, and macros as control outputs that any expression can `ref()`:

- Beat transport: `bpm`, `total_beats`, `beat`, `bar`, `beat_phase`, `bar_phase`, `is_downbeat`, `quantum`, `loop_phase`. `total_beats` is an accumulator, so live BPM changes never jump the clock. `bpm` is an ordinary parameter, so external OSC tempo works through its StateTree address.
- Per-cue envelopes: `cue_phase`, `enter_phase`, `exit_phase` (spring-shaped). Cue hand-offs overlap: the outgoing cue's exit envelope runs while the incoming cue's enter envelope rises, so beat-locked scenes cross-blend.
- Macros: `energy`, `tightness`, `spread` as plain parameters published as control outputs, for feel-level live tweaks.
- Timecode transport: StateTree controls `transport_mode`, `transport_run`, `transport_seconds` (seek), `transport_rate`, `clock_source`, plus chunk mapping outputs (`chunk_index`, chunk-local time). `clock_source: video:<source_id>` slaves the clock to a Video File source's `currentTime`: scrubbing the video scrubs the show, pausing it freezes the show.
- Quantized triggers: `fire` requests hold until the next beat or bar boundary per `quantize_grid`, so scene swaps land on the grid.

## Cue Sheets (sentinel_conductor)

The `sentinel_conductor` MCP tool actions: `load_sheet`, `bake_sheet`, `status`, `fire`, `jump`, `set_tempo`, `transport`.

A cue sheet is YAML: `transport` (`beat` or `timecode`), optional `tempo` (`bpm`, `beats_per_bar`, `quantize_grid`), optional `chunks` (timecode), and `tracks` of `cues`. Each cue has `name`, `at` (number or a reference like `intro.end - 0.5`), `duration`, optional `enter`/`exit`, and `elements` driving target parameters through `layers` (`conductor_output` reads a clock output, envelope, or macro; blends are `override`, `additive`, `multiply`, folded in order into one generated expression per target).

`load_sheet` validates targets, registers every timing and intensity literal as a live parameter under `/sentinel/pipelines/<conductor>/parameters/sheet/...`, and installs the generated expressions. Tweak the sheet parameters live (MCP, UI, OSC), then `bake_sheet` writes the tweaked values back into the YAML (`dry_run: true` previews). Unknown targets and bad references return structured `compile_errors` and install nothing.

## Timeline HUD And Ghost Preview

- `timeline_hud` (in `modules/`) consumes the Conductor's `Cue Records` data port (`track`, `start`, `duration`, `state`, `color_id`) and renders lanes, cue blocks, a beat grid, and a playhead. Drive `playhead_seconds` with `ref("Conductor/control_outputs/transport_seconds")` or `total_beats`.
- `choreo_cascade` (in `modules/`) is the reference stagger/spring consumer: a radial cascade over instance records with spring presets and a `ghost_mode` toggle that renders past and future evaluations of the closed-form motion as translucent onion-skin copies. Because motion is a pure function of time, the leading ghost shows where instances will be.

## Verification

- `sentinel_capture action=sweep_record` plus the `motion-eval` skill for motion review.
- `tools/verify_motion_energy.py` (main repo) analyzes a recorded MP4's frame-difference energy: use it to prove no-pop continuity across cue jumps and tempo ramps, and always run its positive control (a forced discontinuity must spike) in the same session.
- Loop seams: the wrap-around frame difference of one loop period should not exceed the mean adjacent-frame difference.
