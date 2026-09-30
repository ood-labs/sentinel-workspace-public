# PHAGE performance controls and programming

The show is native to Sentinel:

- `Phage_Clock` owns tempo.
- `Phage_Surface` owns the desk, the four-page Push 2 surface and the
  programmer.
- `Phage_Program` publishes one row per fixture to Lighting, LED and Kinetics.

The Push 2 OS package in `scripts/vendor/push2os` is a pinned, unmodified copy.
Its hashes are in `scripts/push2os-provenance.json`.

## Select in Lighting

Open **Phage_Lighting**. Its canvas shows a front elevation and a plan with
the audience below. Selection controls:

- Click, or drag a box.
- Shift adds, Ctrl toggles.
- `A` selects all, `Escape` clears.
- Group buttons: ALL, NONE, MOVERS, STROBES, BARS, AXES, LEFT, RIGHT, PLATE,
  CAPSID, COLLAR, KNEES, FEET, BOOTH, LEGS and ODD.
- HIGHLIGHT shows the selection at full white. SOLO darkens everything else.

The selection is shared with the programmer both ways:

- A programmer selection appears on the canvas through the `remote_selection`
  words.
- A canvas gesture replaces the programmer selection through the
  `selection_word` outputs.

Name and store eight custom groups in the `Phage_Surface` control window
(ADVANCED view) or with `rig_command` `group|<1-8>|<name>`. Custom groups use
stable slots.

## DESK (no Push 2)

`Phage_Desk` is a Module panel with 93 controls, 77 of them pads. A click
travels as follows:

1. It leaves on the `panel` Event cable as a press (1) or release (2) record
   carrying the control index.
2. `scripts/show/desk_panel.luau` runs it as a `rig_command`.
3. The Surface sends state (13) and lit (10) feedback back on
   `panel_feedback`.
4. BPM, bar/beat, PLAY/PAUSE and the status line arrive as text through
   `panel.label`.

The desk renders its own pads, so it keeps working when the Surface window is
closed. If the Surface loses the desk (renamed or deleted), label writes back
off instead of retrying every tick. An earlier build exhausted the Script heap
that way.

A pad is lit when `static_rig.is_lit(bank, slot)` says so; the rules are in
[Persistence](#persistence). The same test drives the Surface window's DESK view
and the Push 2 pads.

## Push 2 pages

| Page | Controls |
|---|---|
| SEQUENCE | Step editor for the three rhythm lanes KICK, SNARE and HI-HAT. Encoders: BPM, length, rate, track, REPEAT/STEPS, cycle, rest and offset beats. Top buttons: PLAY, STOP, TAP, SYNC. |
| GLOBAL | Master, exposure, bloom, sensor whitening start/response, streak strength/length and haze (the renderer's look). Top 1 holds blackout; tops 2-7 run the orbit camera. |
| RIG | Edit the selected fixtures with six attribute banks (below). Encoders 7/8 are overall pitch and rig master. Relative editing keeps differences; absolute gives every selected fixture the same value. The pads hold the four preset banks. |
| COLOR | A/B/C HSV palette editor, eight palettes, copy/paste and a movable pad window. |

RIG attribute banks:

| Bank | Attributes |
|---|---|
| POSITION | pan, tilt |
| LEVEL / COLOR | level, ring (plate for strobes), beam palette, ring palette |
| MOVE FX | move lane, pan size, tilt size, spread, offset, direction |
| CHASE / COLOR FX | intensity lane, width, spread, offset, direction, colour lane |
| LOOK / ORDER | look, order, intensity lane, width, spread, direction |
| STROBE CLOCK | rate per beat (1-24), duty, and the chase knobs. Shown with strobes or bars selected; sets the show-wide clock. |

The RIG pads hold presets:

- STATIC upper-left, EFFECTS upper-right, COLOR lower-left, FULL LOOKS
  lower-right, 16 slots each.
- Tap a populated pad to recall it.
- STORE then a pad stores into that bank.
- UPDATE merges the selected attributes into the last stored or recalled look.
- UNDO EDITS reverses a programmer edit.
- RESET SEL restores the recalled base for the selection.
- FX OFF releases movement, chase and colour modulation on the selection. It
  puts strobes on GLOW and everything else on its plain look.

Every look is described in [LOOKS.md](LOOKS.md).

## Attributes

Every program row has 17 attributes. Each fixture kind reads the ones that
mean something to it:

| Attribute | Movers | Strobes | Bars | Truss axes |
|---|---|---|---|---|
| pan, tilt | aim (deg) | | | axis values (below) |
| level | beam | tube | bar | |
| ring | ring glow | colour plate | | |
| beam / ring palette | A, B or C | tube tint / plate | base / accent | |
| move lane, pan size, tilt size | movement FX | | | axis movement |
| intensity lane, width | chase | chase | chase | |
| colour lane | palette cycling | palette cycling | palette cycling | |
| spread, offset, direction | chase / movement stagger | stagger | stagger | stagger |
| look | mover FX (16-47) | strobe look (0-5) | bar content (0-15) | FX (16-47), SPIN (48-51) |
| order | chase order | chase order | chase order | chase order |

**Lanes** (`move_lane`, `int_lane`, `color_lane`):

| Value | Lane | Timing |
|---|---|---|
| 0 | OFF | Static |
| 1 | KICK | Rhythm lane 1 |
| 2 | SNARE | Rhythm lane 2 |
| 3 | HI-HAT | Rhythm lane 3 |
| 4 | BUILD | Ramps for `build_beats` (16) from the next beat after an EFFECTS or FULL recall. Pulses double each quarter (1, 2, 4, 8 per beat) and it holds at the top. Movement grows with the ramp. |
| 5 | PHRASE | One cycle per `phrase_beats` (16) |

The rhythm lanes are REPEAT (cycle / rest / offset in beats, computed on the
GPU from the Clock) or STEPS (the SEQUENCE page's step sequencer, written by
the Surface). Everything follows the Conductor tempo.

**Chase:** each fixture's pulse is offset along its lane by `rank x spread`.

- `width` is the decay tail.
- `offset` shifts the whole chase.
- `direction` reverses it.

Rank comes from the REST position, so a chase stays attached to its fixtures
while the truss moves. **ORDER** sets the rank:

| Value | Order |
|---|---|
| 0 | AROUND (azimuth) |
| 1 | MIRROR (front to back on both sides) |
| 2 | OUT (radius) |
| 3 | UP (height) |
| 4 | FRONT |
| 5 | SIDE |
| 6 | SHUFFLE (fixed random) |
| 7 | LEG (by leg, then around) |

**Mover and axis FX** (LOOK 16-47): 16 plus the sum of any of these:

| Add | Meaning |
|---|---|
| 0-3 | Chase repeats x1 / x2 / x4 / x8 per lane pulse |
| +4 RND | Each flash lights a random third |
| +8 JMP | Each move-lane trigger jumps to a random point within pan/tilt size |
| +16 STEP | Each trigger steps to the next of five points and holds |

STEP wins over JMP. **SPIN** (48-51) turns an axis continuously at 1/4, 1/2, 1
or 2 turns per lane cycle; the capsid uses it.

**Strobe looks** (LOOK 0-5 on strobes):

| Value | Look | Tube | Colour plate |
|---|---|---|---|
| 0 | PULSE | follows the chase envelope | follows the chase envelope |
| 1 | STROBE | flashes on the strobe clock inside the envelope | follows the envelope |
| 2 | SPARKLE | random tubes on each clock tick | follows the envelope |
| 3 | BLINDER | warm, decaying across each lane cycle | same as the tube |
| 4 | GLOW | off | plate only |
| 5 | OFF | off | off |

With no intensity lane, the envelope is full. A strobe on PULSE with no lane
therefore holds its tube at full white, which is why fresh rows and FX OFF use
GLOW.

**Pixel-bar content** (LOOK 0-15): SOLID, CHASE, PULSE, SEGMENTS, SCATTER,
COMET, TWIN, FILL, SCANNER, BARCODE, PLASMA, SPARKLE, HEARTBEAT, CLIMB, STROBE,
RIPPLE. Base colour is the beam palette and accent is the ring palette.

**Truss axes** (slots 240-247) read pan and tilt as motion:

| Axis | Pan | Tilt |
|---|---|---|
| Body | yaw in degrees (+-30) | height, x 2.4/90 m (-2.4 to +2.0) |
| Capsid | spin in degrees | sheath contraction, x 2.4/90 m (-1.2 to +2.4) |
| Legs | swing, x 2.5/90 m | foot lift, x 4/90 m (0 to 4.5) |

Every axis is rate- and acceleration-limited (body height 1 m/s, capsid spin
120 deg/s, leg lift 3.8 m/s at speed 1). A look aims for its pose and the truss
travels there physically.

`Phage_Kinetics` **drive** chooses who moves the truss:

- **Programmer:** the looks. The Surface selects it when it takes the rig.
- **Manual:** the node's sliders.
- **Demo:** a self-running walk.
- **Rest.**

## Global keys (every page)

| Button | Action |
|---|---|
| Play (bottom left) | Start / pause the clock; lit while running. Shift+Play stops and returns to beat 0. |
| Tap Tempo | Tap tempo; pulses on each beat. |
| Metronome | SYNC: resync to beat 0. |
| Arrows | Orbit camera (below). |
| Clip | Save the live camera as the current orbit point. |
| Right-side bottom button | Hold blackout. |
| Right-side second button | Hold the all-rig strobe: every fixture flashes white on the current strobe clock. |

- Blackout wins when both holds are pressed.
- Held states never enter presets.
- The desk's BLACKOUT and STROBE pads are the same holds.

## Orbit camera

The arrows jump `Phage_Camera` between 40 authored points, 8 positions by 5
heights, from the camera's point of view:

- **Left / right** step round the hall: F, FL, L, BL, B, BR, R, FR.
- **Up / down** step through UNDER (in the crowd between the feet, looking up
  into the capsid), LOW, MID, HIGH (level with the knees) and TOP (the roof,
  steeply down).
- **Framing:** each point aims at its own part of the rig and fits its own
  lens, so the six-fold symmetric rig still gives 40 different pictures.
- **GLOBAL buttons:** top 2 sets CUT, 0.5, 1, 2 or 4 s moves. Tops 3/4 zoom.
  Top 5 goes home (MID F, the composed program frame).
- **Adjusting a point:** arrow to it, fly the camera by hand in the viewport,
  then press Clip (or GLOBAL top 6). Top 7 restores the authored framing.
  Saved points live in the Surface state and are saved with the project.

The authored points are the `M.ROWS` and `M.COLS` tables in
`scripts/show/camera_orbit.luau`, placed on an ellipse inside the hall.

The project ships MID F as a saved point with the composed 55 deg lens, the
same frame as the `Frame - Program F-MID` node preset on `Phage_Camera`. That
preset recalls the frame without the Surface.

## Persistence

- **Programmer, palettes, sequences, custom groups and page state:**
  `presets/phage_stage_push2.json` ("current") plus the Surface's saved
  snapshot.
- **Look banks:** static, effects, colour, complete and rhythm have separate
  native bank files. Recalls read them from disk each time, so a regenerated
  bank is live on the next recall.
- **FULL recall** keeps BPM and transport. It restores fixture attributes,
  pitch/master, rhythm, palettes, the strobe clock and the GLOBAL render
  controls.
- **Lit pads:** `static_rig.active_text` holds them, and
  `Phage_Surface/state/active_looks` mirrors it for automation.
  - A shape (static 1-12) and a pose (13-16) light separately.
  - A FULL recall lights the parts in its preset's `look_parts` value.
  - A FULL store records the parts lit at that moment, so a re-stored slot
    stays truthful.
  - Any later partial recall unlights the FULL pad.
  - The Surface entry saves the text as `looks`, beside (not inside) the
    push2os `package` in its serialize table, so the lit set survives reloads
    and project saves.
- **Adding durable state:** two traps.
  - Do not add new durable push2os records (`persist` of `snapshot`, `bank`
    or `state`). The push2os restore requires every such record to exist in
    the reload snapshot. A new one makes every older snapshot refuse to
    restore (`SNAPSHOT_RECORD_MISSING`), and the Surface sits on "Restoring
    PHAGE programmer".
  - Plain Surface state (`host.state.register`) is not persistence either: it
    resets to its default whenever it is registered again on reload.
  - Carry new durable values in the entry script's serialize table, as
    `looks` does.
- **Log noise:** the log line `[push2os] bank save failed: false` means the
  host's asynchronous `preset.save` has not finished yet. Bank saves land:
  `bank_writes` increments and the push2 file is rewritten. The vendored
  library is left unmodified.

## Regenerating

Everything the Surface and the banks know about the rig is generated from the
rig itself, so change the source and rerun. With the unchanged inputs, each
generator reproduces the shipped files byte for byte.

1. `python tools/phage_review.py mounts` (only after changing anatomy, stance
   or counts in `Phage_Plan`). It holds `Phage_Kinetics` at Rest, captures its
   248 `Mounts`, writes `tools/mounts_rest.json` and restores the drive.
2. `python tools/phage_rig.py` writes `scripts/show/fixture_catalog.luau`:
   stable slots, families, zones, legs, count gates and names. It also
   self-checks the aim maths, round-tripping direction to pan/tilt to
   direction.
3. `python tools/phage_looks.py` writes every preset bank in `presets/` and
   `scripts/show/preset_titles.luau`. It also reports how many movers each
   shape lights and its tilt range, so a bad aim shows up before a capture
   does.
4. `python tools/phage_desk.py` writes the `Phage_Desk` manifest,
   `modules/Phage_Desk/desk_layout.hlsli` and `scripts/show/desk_layout.luau`
   from one control list, so pad indices always agree. Pad titles come from
   the looks. It then refreshes `modules/Phage_Desk/_ui.generated.hlsli` with
   the workspace's `tools/module-ui.ps1`, the manifest-hash contract the
   example validator checks.
5. `python tools/phage_program.py` (the 17-attribute program module) and
   `python tools/phage_labels.py` (canvas caption tables) regenerate their
   modules.

After a Luau change, reload the Surface with
`/sentinel/pipelines/Phage_Surface/actions/reload`. After a Module change, use
`sentinel_pipeline action=force_reload`. Look changes need no reload.
`tools/phage_review.py` then recalls and captures looks for review (see the
README).

Each look is authored as geometry, not per-fixture numbers:

- **Shapes:** a direction per fixture family (for example "to the apex 36 m up"
  or "tangential and level").
- **Poses:** axis values.
- **Effects:** attribute dicts per role (movers, strobes, bars, body, capsid,
  legs). A mover's `rise` is signed toward the sky per mount, so hanging and
  upright heads rise together.
- **Colours:** a palette plus a routing function per fixture.

## Implementation notes

- **Packed programming:** Sentinel's native programmer catalog is limited in
  targets and paths, so programming is packed into bounded strings: 8
  partitions of 32 slots per bank, each under 4096 characters, with `_` for
  values a look leaves untouched.
- **Commit:** the Surface uploads rows in batches of up to 96 parameters per
  service and commits `commit_revision` only after the whole look is written,
  so a half-uploaded look is never visible. Recall decodes four partitions per
  control tick, and rapid recalls coalesce.
- **Degenerate maths on the GPU:** several shaders guard against it. HLSL
  `atan2(0, 0)` is undefined for fixtures on the body axis, and `pow` of a
  tiny negative base returns NaN.
  - `phRank`, `phAimAngles` and the plan marks use explicit fallbacks.
  - Kinetics restarts an axis at rest if its state ever becomes non-finite.
  - Every data port was scanned clean.
- **Budgets:** the Surface runs within a 2 ms tick budget and a 64 MB heap. It
  measured 0.1-0.9 ms per tick with a 5-6.6 MB heap.
