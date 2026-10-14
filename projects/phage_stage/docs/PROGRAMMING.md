# PHAGE performance controls and programming

The show is native to Sentinel:

- `Phage_Clock` owns tempo.
- `Phage_Surface` owns the desk, the four-page Push 2 surface and the
  programmer.
- `Phage_Program` publishes the program to Lighting and Kinetics: one row per
  layer of every fixture (see [Layers](#layers)), 616 rows.

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

The desk draws only what the host reports for each control: its state, lit
flag and label. A preset pad is lit while its state is ACTIVE, TAP's lamp
while it is LIT, and the tempo, bar and beat readouts are read back out of the
label text. Amber is reserved for what is live and red for BLACKOUT; the banks
carry identity colours and the energy tiers a step mark. The drawing is
`modules/Phage_Desk/layout.hlsl` on the shared UI kit in
`modules/_shared/ui/`: a layout pass records a draw list, each control drawing
into its own run of slots in parallel, and the kit's rasterizer draws it.

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
| RIG | Edit the selected fixtures with seven attribute banks (below). Encoders 7/8 are overall pitch and rig master. Relative editing keeps differences; absolute gives every selected fixture the same value. The pads hold the preset banks: the four look banks, and with Octave Up / Down a page of layer banks per fixture type. |
| COLOR | A/B/C HSV palette editor, eight palettes, copy/paste and a movable pad window. |

RIG attribute banks:

| Bank | Attributes |
|---|---|
| POSITION | pan, tilt, HEADING (truss axes: FRONT holds the axis's pan at 0) |
| LEVELS | each layer's dimmer: BEAM, HALO, TUBE, PLATES, BAR LEVEL, CHASE DEPTH |
| COLOR | beam palette, ring palette, colour lane |
| MOVE FX | move lane, pan size, tilt size, spread, offset, GLIDE (how long a GLIDE move takes) |
| CHASE / COLOR FX | intensity lane, width, spread, offset, direction, colour lane |
| LOOK / ORDER | each layer's own LOOK knob (MOVE FX, BEAM FX, HALO FX, TUBE FX, PLATES FX, PIXEL FX, CHASE FX), order |
| STROBE CLOCK | rate per beat (1-24), duty, and the chase knobs. Shown with a layer selected that runs on the clock (TUBE, PIXELS, CHASE; the plates never flash on it); sets the show-wide clock. |

A bank shows only the knobs the selection carries, packed from the left: with
the Halo Beams selected LEVELS reads BEAM and HALO, with the strobes TUBE and
PLATES. A LOOK knob steps through its own layer's looks in a musical order.

The RIG pads hold presets. Octave Up / Down pages them:

| Pad page | Upper left | Upper right | Lower left | Lower right |
|---|---|---|---|---|
| 1 Looks | STATIC | EFFECTS | COLOR | FULL LOOKS |
| 2 Halo Beam | MOVE FX | BEAM FX | HALO FX | HALO BEAMS |
| 3 Linear Strobe | TUBE FX | PLATES FX | | STROBES |
| 4 Pixel Batten | PIXEL FX | CHASE FX | | BATTENS |
| 5 Sequences | RIG SEQUENCES | BEAMS SEQ | STROBES SEQ | BATTENS SEQ |

- Every bank has 16 slots, a 4 x 4 window. A fixture bank's window opens one
  row of four and grows a row whenever its last row fills. Empty slots
  show the bank's dim colour, stored ones its bright colour, the live one white.
- The bottom-right pad of pages 2-4 (slot 16 of the whole-fixture bank) is
  BLACKOUT for that fixture type: red, white while it is up (docs/LOOKS.md).
- STATIC's bottom row (13-16) is the truss poses, a switcher of its own: green
  pads and a green row on the display, the pose that is up white. A beam shape
  and a pose are both lit at once.
- A layer bank (MOVE FX, BEAM FX...) stores and recalls only that layer of its
  fixture type, whatever is selected, so layer pads stack: RIOT's movement
  under BREATHE's beams. A whole-fixture bank (HALO BEAMS, STROBES, BATTENS)
  holds every layer of the type with its aim and levels; palettes stay with
  COLOR. A layer that runs on the strobe clock (TUBE, PIXELS, CHASE) stores the
  clock with it; PLATES does not, so a plates pad never changes the tubes' rate.
- Tap a populated pad to recall it.
- STORE then a pad stores into that bank.
- UPDATE merges the selected attributes into the last stored or recalled look.
- UNDO EDITS reverses a programmer edit.
- RESET SEL restores the recalled base for the selection.
- FX OFF releases movement, chase and colour modulation on the selection. It
  puts strobes on GLOW and everything else on its plain look.

Every look is described in [LOOKS.md](LOOKS.md).

## Layers

Each fixture type is programmed as layers, one program row each, so the parts of
a fixture that do different things are programmed, stored and recalled apart:

| Fixture type | Layers | Program rows |
|---|---|---|
| Halo Beam (movers) | MOVE: where the head points and how it moves. BEAM: the beam. HALO: the 24-cell ring. | slot, slot + 248, slot + 376 |
| Linear Strobe | TUBE: the white tube. PLATES: the two colour plates. | slot, slot + 376 |
| Pixel Batten (bars) | PIXELS: the content. CHASE: a dip on a lane over the content. | slot, slot + 376 |
| Truss axes | one row each | slot |

- **Selecting** a fixture (a canvas pick, `select|<slot>`, a group such as
  MOVERS or CAPSID) selects all its layers. The layer groups `move`, `beam`,
  `halo`, `tube`, `plates`, `pixels` and `chase` (`rig_command`
  `select|beam`) select one layer of every fixture of its type; a row id from
  248 up selects one layer of one fixture.
- **Editing** a knob changes the layers that carry it: BEAM only the BEAM rows,
  SPREAD every selected layer that has a spread.
- **Storing** writes each row's own fields only, so a layer's look never
  writes another layer's values.
- **Looks stored before the layers** recall unchanged: each layer row starts as
  a copy of its fixture's row (CHASE with no lane), and every layer then reads
  what that row read. `Phage_Program`'s hidden `layered` switch reads every
  layer from the base row instead; `python tools/phage_baseline.py ab <name>`
  recalls all 64 looks with it off and on and compares the DMX channel for
  channel.

## Attributes

Every program row has 17 attributes. Each layer reads the ones that mean
something to it:

| Attribute | MOVE | BEAM / HALO | TUBE / PLATES | PIXELS | CHASE | Truss axes |
|---|---|---|---|---|---|---|
| pan, tilt | aim (deg) | | | | | axis values (below) |
| level / ring | | BEAM level / HALO ring | TUBE level / PLATES ring | bar level | depth (level) | |
| beam / ring palette | | BEAM beam / HALO ring palette | PLATES colour (beam palette) | base / accent | | |
| move lane, pan size, tilt size | movement FX | | | | | axis movement |
| intensity lane, width | | chase | chase | chase | chase | |
| colour lane | | palette cycling | PLATES palette cycling | palette cycling | | |
| spread, offset, direction | movement stagger | chase stagger | chase stagger | stagger | stagger | stagger |
| look | MOVE FX (16-51) | BEAM / HALO FX | TUBE / PLATES FX (0-5) | content (0-15) | CHASE FX | FX (16-47), SPIN (48-51) |
| order | stagger order | chase order | chase order | chase order | chase order | stagger order |

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

**GLIDE** (52-63) eases a head from one position to the next instead of
snapping, and lets a move run through a group:

- 52 + repeats (0-3): a new position every lane cycle x1, x2, x4 or x8.
- +0: the next point of the five-point figure. +4 RND: a random position of the
  head's own. +8 GROUP: one random position for the head's whole group, so the
  group moves as a formation.
- Each head sets off rank x spread + offset of a step late, so a move ripples
  through a group in its ORDER and groups with different offsets set off one
  after another.
- GLIDE (the MOVE row's width) is the share of a step the move takes: 0.2
  snaps, 0.9 drifts.
- On a Halo Beam the pan size leans the beam across the stage (world X) and the
  tilt size raises it in the head's own frame. Every head of a group leans the
  same way, so a formation moves as one body; equal pan offsets in each head's
  own frame would twist a ring of heads round like a pinwheel. A head aimed
  close to its own pan axis leans less rather than whirling its yoke (pan is
  damped near the axis, at most 1.25 x the lean). With ORDER MIRROR the
  stage's two halves lean opposite ways, so the group fans open and closed
  about the centre line. On a truss axis GLIDE keeps its plain pan and tilt.

With one size at 0 the plain circle is a sweep (tilt size 0) or a nod (pan size
0); the MOVE FX pads use nods and GLIDE, and nothing circles. A pan sweep turns
every head of a ring the same way in its own frame, so the ring twists; the
pads sweep with a GLIDE lean instead.

**BEAM FX and HALO FX** read the mover codes' repeats and RND gate (x1-x8, RND
a random third): the beam or the halo pulses on its intensity lane, each layer
on its own lane, width and spread. The JMP and STEP bits move heads and never
touched light, so on a light layer 24-27 is **HOLD** (below).

**TUBE FX and PLATES FX** (LOOK 0-5): the TUBE row's look drives the tube, the
PLATES row's look the plates.

| Value | Look | TUBE | PLATES |
|---|---|---|---|
| 0 | PULSE | follows the chase envelope | follows the chase envelope |
| 1 | STROBE | flashes on the strobe clock inside the envelope | follows the envelope |
| 2 | SPARKLE | random tubes on each clock tick | follows the envelope |
| 3 | BLINDER | warm, decaying across each lane cycle | decaying across each lane cycle |
| 4 | GLOW | off | follows the envelope |
| 5 | OFF | off | off |

With no intensity lane, the envelope is full. A TUBE on PULSE with no lane
therefore holds the tube at full white, which is why fresh rows and FX OFF use
GLOW.

**CHASE FX** dips a batten's content on the CHASE row's intensity lane, as deep
as its LEVEL: PULSE (x1-x8 and RND as above), STROBE (flashes at the strobe
clock while the pulse is up) or BLINDER (a hit decaying over the lane cycle). A
CHASE row with no lane leaves the content as it is.

**HOLD** (24-27, x1-x8, on every light layer: BEAM, HALO, TUBE, PLATES and
CHASE): the light shows for WIDTH of each lane cycle (repeated x1-x8), opening
OFFSET into it and rippling through the group by rank x SPREAD, and is dark the
rest of the time. HOLD at its narrowest WIDTH (0.01) never opens. Windows on
different groups hand the light from one to the next, which is how the HALO FX
and CHASE FX sequences run through the rig. Keep a group's stagger (rank range x
SPREAD) inside its window, or its last fixtures open after the next group's.

**Pixel-bar content** (PIXEL FX 0-15): SOLID, CHASE, PULSE, SEGMENTS, SCATTER,
COMET, TWIN, FILL, SCANNER, BARCODE, PLASMA, SPARKLE, HEARTBEAT, CLIMB, STROBE,
RIPPLE. Base colour is the beam palette and accent is the ring palette. 16-31
run the same contents twice per lane cycle, 32-47 four times and 48-63 eight
times, so a pass along a leg can take two beats of a 16-beat phrase.

**Truss axes** (slots 240-247) read pan and tilt as motion:

| Axis | Pan | Tilt |
|---|---|---|
| Body | yaw in degrees (+-30) | height, x 2.4/90 m (-2.4 to +2.0) |
| Capsid | spin in degrees | sheath contraction, x 2.4/90 m (-1.2 to +2.4) |
| Legs | swing, x 2.5/90 m | foot lift, x 4/90 m (0 to 4.5) |

An axis row's level is its **HEADING**: FREE (1) turns it as its pan, pose and
effects say; FRONT (0) holds its pan at 0 (body yaw, capsid spin, leg swing)
while its tilt still plays. The beam shapes that only read with the capsid
facing front set it on the capsid (docs/LOOKS.md).

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
  native bank files, and so does each fixture bank (`phage_stage_move`,
  `_beam`, `_halo`, `_heads`, `_tube`, `_plates`, `_strobes`, `_pixels`,
  `_chase`, `_battens`). Recalls read them from disk each time, so a
  regenerated bank is live on the next recall.
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
  - A fixture pad unlights EFFECTS and any other fixture pad sharing a layer
    with it (HALO BEAMS holds MOVE, BEAM and HALO); a whole-fixture pad also
    unlights the STATIC shape. An EFFECTS recall unlights every fixture pad, a
    shape every whole-fixture pad.
  - Stored fixture pads are named from their looks; the names travel beside
    `looks` as `fx_names`, mirrored to `Phage_Surface/state/fx_names`.
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
  - A durable record's `min`/`max` is a restore contract: a saved value
    outside it makes every reload refuse (`RECORD_VALUE_INVALID`, the Surface
    stuck on "Restoring"). Widen it in the same change that widens what is
    written to it. The last pad pressed (`static_slot`) runs 1-64: fixture
    banks once had 64 slots, and narrowing it again would refuse snapshots
    saved then.
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
   does. `python tools/phage_looks.py fixtures` writes only the fixture banks
   (pad pages 2-4) and the pad names, leaving the shipped look banks alone.
4. `python tools/phage_desk.py` writes the `Phage_Desk` manifest,
   `modules/Phage_Desk/desk_layout.hlsli` and `scripts/show/desk_layout.luau`
   from one control list, so pad indices always agree. Pad titles come from
   the looks. A layout change moves rects only: the control order, ids, kinds,
   labels and actions are the Surface's contract, so `desk_layout.luau` stays
   byte-identical. It then runs `tools/il_type.py labels Phage_Desk`, which
   sets the desk's own words (`modules/Phage_Desk/labels.txt`) as kerned label
   tables and refreshes `_ui.generated.hlsli`, the manifest-hash contract the
   example validator checks. `il_type.py` needs numpy and Pillow.
5. `python tools/phage_program.py` regenerates the program module: 616 rows
   of 17 attributes (each slot's base row, the movers' BEAM rows, every
   fixture's second layer), kit passes included. A new row count needs the
   node recreated and its two links remade: a reload keeps the old persistent
   buffer. Every canvas draws its words with the shared
   UI kit (`modules/_shared/ui/`, IBM Plex): after changing a module's
   `labels.txt`, run `python tools/il_type.py labels <Module>` to rebuild its
   kerned label tables.

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
  partitions per bank, each under 4096 characters, with `_` for values a look
  leaves untouched. Partition k holds slots 32k-32k+31's base rows, then their
  BEAM rows, then their second-layer rows, each row only the fields its layer
  owns (`scripts/show/rig_codec.luau`). A partition stored before the layers is
  exactly the first lines of one stored after, so it upgrades by appending each
  layer row as a copy of its fixture's line.
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
- **Budgets:** the Surface runs within a 2 ms tick budget and a 64 MB heap. With
  616 rows it measured 0.2-0.4 ms per tick idle, a p99 near 1.1 ms while
  recalling, and a 13-15 MB heap.
  - The host interrupts a tick that overruns, wherever it is. So every step of
    a recall resumes: one partition decoded per tick, its cursor moved only
    once it is fully decoded; the row swap in a tick of its own; the upload
    built and sent row by row. Each step also yields once the tick has spent
    about 0.8 ms (`static_rig.busy`). A recall still overruns one tick, the one
    in which the host hands over the preset's values; nothing is lost there.
  - Decoding a partition that the host had cut short, then moving on, left
    part of a recalled look on the previous look's values about once in 30
    recalls. `tools/phage_baseline.py ab` found it by comparing the program
    rows with a recorded baseline.
