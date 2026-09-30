# PHAGE

An arena lighting rig in the shape of a bacteriophage, programmed and running
entirely inside Sentinel. A kinetic truss carries the show: the body rises and
yaws, the capsid cage spins and contracts, and six jointed legs lift and
swing. The rig has 100 beam movers, 41 linear strobes and 47 pixel bars
(196 fixtures at the saved counts) over a crowd in a 72 x 100 m arena. It ships
a complete show:

- 16 STATIC looks: 12 beam shapes and 4 truss poses.
- 16 EFFECTS in four energy tiers: CALM, GROOVE, BUILD and CRAZY.
- 16 COLOR looks.
- 16 FULL LOOKS.

Play it from a mouse desk or an Ableton Push 2.

Under the picture is a complete show system: a Script-node surface, a packed
per-fixture programmer and layered preset banks. The whole graph, renderer and
live node previews included, holds 64 Hz on a laptop RTX 5060. It needs
Sentinel 0.5.87 or later. A Push 2 is optional: `Phage_Desk` plays the
whole show with the mouse.

How the rig was designed, programmed, tuned and optimised is written up in
[PROCESS.md](docs/PROCESS.md). Read it before building a rig of your own.

## First run

1. Open `stagerig_phage.sentinel`. The program image is `Phage_Renderer`. The
   project opens with the clock running at about 200 BPM, seen from the middle
   of the crowd, on the four parts of FULL LOOK 01 GENESIS: STATIC ORIGIN, pose
   REST, EFFECTS DRIFT and COLOR PHAGE (teal, magenta and violet). HOME, or the
   `Frame - Program F-MID` preset, returns to the composed camera.
2. Open the `Phage_Desk` panel (Window toggle in its node header). It is the
   show's desk:
   - **TAP**, **PLAY/PAUSE**, **STOP** and **SYNC**, with live BPM and
     bar/beat readouts.
   - Four banks of 16: **FULL LOOKS**, **STATIC**, **EFFECTS** and **COLOR**.
     - FULL LOOKS and EFFECTS are coloured by tier: CALM blue, GROOVE green,
       BUILD amber, CRAZY red.
     - STATIC 13-16 (blue) are the truss poses.
   - **BLACKOUT** and **STROBE**, which act while held.
   - **CAMERA** arrows, **IN**, **OUT** and **HOME**, which orbit the view
     between 40 authored points.
3. Lit pads show what is live. A FULL look lights its own pad plus the four
   parts it is built from: shape, pose, effect and colour. Recalling any single
   part afterwards moves that part's light and unlights the FULL pad, because
   the rig is no longer that look. The lit set is saved with the project.
4. The `Phage_Surface` control window has the same DESK view. **ADVANCED** in
   its **View** combo gives the programmer and Push 2 tools, described in
   [PROGRAMMING.md](docs/PROGRAMMING.md).
5. To use a real Push 2:
   - Put it in User mode and close any other application that drives its
     display.
   - `Phage_Push2_Display` drives the screen over WinUSB.
   - The Push and the desk drive the same looks and transport, and can be used
     together.

### Playing a set

The four EFFECTS tiers are a dynamic range:

1. **CALM:** slow drift and the phrase-long tide.
2. **GROOVE:** kick, snare and hat.
3. **BUILD:** a 16-beat ramp.
4. **CRAZY:** everything firing.

Recalling a BUILD effect (or a BUILD FULL look) restarts the BUILD lane on the
next beat. Intensity, movement and truss travel then ramp for 16 beats while the
pulse rate doubles each quarter (1, 2, 4 then 8 per beat). The ramp holds at
the top until the next recall. Fire a BUILD look 16 beats before the drop, then
land on a CRAZY look.

The layered banks mix freely. Recall a FULL look, then change the COLOR, the
truss pose or the EFFECTS tier underneath it. Every look is listed in
[LOOKS.md](docs/LOOKS.md).

## Automation (agents, MCP, scripts)

Everything the desk and the Push do can also be done through state:

- **Commands:** write a string to
  `/sentinel/pipelines/Phage_Surface/state/rig_command`, starting with a new id
  of your choice. The Surface answers in `rig_command_ack` as `<id>:accepted`
  or `<id>:<error>`. The desk pads run these same commands.

| Command | Effect |
|---|---|
| `<id>\|tempo\|<tap\|play\|stop\|sync\|start\|pause>` | Transport, as the desk (`play` toggles; `stop` returns to beat 0) |
| `<id>\|tempo\|bpm\|<value>` | Set the tempo |
| `<id>\|preset\|recall\|complete\|<1-16>` | Recall a FULL LOOK (also `static`, `effects`, `color`, `rhythm`) |
| `<id>\|preset\|store\|<bank>\|<1-16>` | Store the programmer into a slot (a FULL store records the lit parts with it) |
| `<id>\|select\|<ids>[\|toggle]` | Select fixtures by comma-separated stable slot |
| `<id>\|encoder\|<attribute>\|<value>\|absolute` | Set an attribute on the selection (omit `absolute` for a relative move) |
| `<id>\|rows\|<static\|effects>\|<bank 0-7>\|<packed>` | Paste one packed 32-slot partition into the live programmer (undoable, not stored) |
| `<id>\|momentary\|<blackout\|strobe>\|<1\|0>` | Hold / release |
| `<id>\|camera\|<left\|right\|up\|down\|in\|out\|home\|time\|save\|reset>` | Orbit camera |
| `<id>\|group\|<1-8>\|<name>` | Store the selection as a custom group |
| `<id>\|<undo\|reset_selected\|release>` | Programmer undo / restore the recalled base for the selection / release |

- `/sentinel/pipelines/Phage_Surface/state/active_looks` reports the lit pads,
  for example
  `static=static 1;pose=static 13;effects=effects 1;color=color 3;complete=complete 1`.
- Send one command at a time and wait for its ack. The Surface handles only
  the latest string.
- Movers slew physically. Allow about 2 seconds after a position change before
  capturing, and longer for truss poses.
- **Frame comparisons:** intensity follows the rhythm lanes, and a paused clock
  darkens every lane-driven fixture. For a steady, repeatable picture, recall a
  STATIC and a COLOR, then run `python tools/phage_review.py steady`. It
  pastes neutral effect rows (no lanes, no motion, strobes on GLOW) into the
  live programmer without storing them.
- `tools/phage_review.py` also recalls looks, writes bank contact sheets and
  timed filmstrips to `captures/looks/`. The other tools regenerate the
  catalog, looks and desk (see
  [PROGRAMMING.md](docs/PROGRAMMING.md#regenerating)).

## Component map

| Component | Role |
|---|---|
| `Phage_Plan` | Construction authority. A plan (top) view and a section through one leg. Drag the feet in plan and the knee in section. `1`-`6` pick a leg, `S` mirrors edits, `R` resets a leg, `Esc` clears. Parameters set the stance (Reference, Spider, Mantis, Crab), anatomy dimensions and fixture counts per family. A leg turns red when it cannot reach its foot, folds below its hip or crowds its neighbour. |
| `Phage_Kinetics` | The moving truss: 8 axes (body height and yaw, capsid spin and sheath contract, and lift and swing for each of the six legs), each with speed and acceleration limits. **Drive** is Programmer (the looks), Manual (sliders), Demo or Rest. Publishes the live fixture mounts, so every fixture rides the truss. |
| `Phage_Assembly` | Truss tubes and solids from the kinetic members, for the renderer. |
| `Phage_Lighting` | Beam movers and linear strobes:<br>- motors: pan 300 deg/s, tilt 220 deg/s<br>- optics: 3 deg beam, 40 m reach, ring glow<br>- strobes: a white tube plus a colour plate<br>- selection canvas: front elevation and plan, with group buttons<br>Publishes Pose, Optics and Selection. |
| `Phage_LED` | The 47 pixel bars on the legs, plate edge, sheath, collar, capsid and booth, with 16 content looks. |
| `Phage_Program` | The per-fixture programmer: 248 rows x 17 attributes. The Surface writes it in batches and commits it as one revision. Its preview is the programmer sheet. |
| `Phage_Show` | Show state:<br>- the five lanes (KICK, SNARE, HI-HAT, BUILD, PHRASE) derived from the Clock<br>- palettes A/B/C<br>- the strobe clock<br>- blackout and strobe holds<br>- the switch that hands the rig to the programmer |
| `Phage_Venue` | The arena: a 72 x 100 x 30 m hall with seating tiers, roof steel, a crowd, room fill and materials. Its preview checks roof clearance at the truss's kinetic maximum. |
| `Phage_Renderer` | HDR program render: beams and ring glows in haze, strobe flashes, pixel-bar glow, floor reflections, bloom, a highlight shoulder and lens streaks. |
| `Phage_Camera` | Shared camera for the renderer. The desk and Push 2 arrows orbit it between 40 authored points, which gives show-level camera switching (the reason it is an external camera). |
| `Phage_Clock` | Conductor: tempo and beat. Three `ref()` expressions feed `Phage_Show`. |
| `Phage_Surface` | Script node that runs the show:<br>- the desk's clicks and feedback<br>- the window DESK view<br>- the Push 2 surface (four pages, fixture programmer, preset banks, transport keys, orbit camera)<br>- the `rig_command` seam<br>Source in `scripts/`. |
| `Phage_Desk` | The mouse desk: a 93-control panel (77 pads). Clicks travel on its `panel` Event cable to the Surface, which runs them and lights the pads through `panel_feedback`. Generated by `tools/phage_desk.py`. |
| `Phage_Push2_Display` | Push 2 display node fed by the Surface's display output. |

- **Scripts:** `scripts/Phage_Surface.luau` is the entry. Show logic lives in
  `scripts/show/` and page factories in `scripts/pages/`.
- **Push 2 OS:** the pinned package is in `scripts/vendor/push2os/` (MIT, see
  its LICENSE). Its hashes are in `scripts/push2os-provenance.json`, and
  `.gitattributes` keeps those bytes exact.
- **Preset banks** in `presets/`:
  - `stagerig_phage_static`, `stagerig_phage_effects`, `stagerig_phage_color`:
    layered partial presets.
  - `stagerig_phage_complete`: FULL LOOKS.
  - `stagerig_phage_rhythm`.
  - `stagerig_phage_push2`: surface state, palettes, sequences and custom
    groups.

## Geometry and fixtures

**Anatomy** (Plan defaults):

- A hexagonal base plate at 6.2 m under a sheath column.
- A collar ring at 11 m.
- A capsid on top: a truncated-octahedron truss cage stretched vertically,
  about 23 m to the tip at rest.
- Six legs, each bending at a knee (11 m out, 11.8 m up) and landing on a
  spiked foot 17 m from the centre.
- A DJ booth on a riser under the plate.

**Kinetic ranges:**

| Axis | Range |
|---|---|
| Body height | -2.4 to +2.0 m |
| Body yaw | +-30 deg |
| Capsid spin | continuous |
| Sheath contract | -1.2 to +2.4 m |
| Leg lift | 0 to 4.5 m |
| Leg swing | +-2.5 m |

**Program slots** are stable, so changing counts never retargets stored
programming:

| Slots | Holds | Saved count | Potential |
|---|---|---|---|
| 0-127 | Movers | 100 | 106: raising the collar count to 12 lights the rest, and every look already programs them |
| 128-175 | Strobes | 41 | |
| 176-239 | Pixel bars | 47 | |
| 240-247 | Kinetic axes: 240 body, 241 capsid, 242-247 legs | 8 | |

**Fixture types** (three, by design):

- **Beam mover:** narrow 3 deg beam with a 24-LED ring glow.
- **Linear strobe:** a white tube plus a wide colour plate. Looks: PULSE,
  STROBE, SPARKLE, BLINDER (warm), GLOW (plate only) and OFF.
- **Pixel bar:** chased along the legs and around the rings with 16 content
  patterns.

Dimensions are an interpretation of a reference image, not a surveyed stage.

## Node presets

These presets are saved in the project (`sentinel_preset`, project scope). Each
one is deliberately narrow: recalling the camera does not disturb the look or
the quality, and a quality rung does not disturb the framing.

**`Phage_Camera`: frame contract.**

- `Frame - Program F-MID` holds the camera parameters alone: position
  `(14, 6, 38)` aimed at `(0, 10, 0)`, 55 deg lens.
- The orbit's HOME point (MID F) ships saved to this same frame. GLOBAL top 7
  resets that point to its authored, wider fitted lens.
- The camera is meant to be flown and orbited, so recall this before any final
  capture.

**`Phage_Renderer`: quality ladder.** Each rung holds output resolution and
volume samples alone. Renderer GPU time is shown relative to Live. It was
measured with every mover lit (SUNBURST), no effects, and the full graph
running with the Venue, Assembly, Plan and Desk previews cooking.

| Preset | Output | Volume samples | Renderer GPU vs Live |
|---|---|---|---|
| `Quality - Draft` | 1280 x 720 | 4 | 0.5x |
| `Quality - Live` (manifest default) | 1920 x 1080 | 8 | 1.0x |
| `Quality - Beauty` | 2560 x 1440 | 16 | 1.7x |
| `Quality - Hero (capture only)` | 3840 x 2160 | 32 | 4.2x; the whole app drops to about 30 fps |

Resolution carries the cost:

- Moving from 8 to 16 volume samples at 1080p was within measurement noise.
- 4 and 32 samples differ by less than 1/255 per pixel on average.

Work on Live. Use Hero only for stills and recordings.

## Performance

Measured on an NVIDIA GeForce RTX 5060 Laptop GPU (8 GB) with the saved graph
running GENESIS:

- **Cadence:** 64 Hz. CPU frame 5.3-6.6 ms.
- **GPU:** about 7 ms per frame in total, with the renderer at 4.3-5.3 ms at
  Live. Its largest passes were venue shading 1.5 ms, the haze volume
  1.2-1.3 ms and the crowd 0.6-0.9 ms.
- **GPU times move with the clock.** 64 Hz leaves the GPU headroom, so a laptop
  driver lowers its clock. Later samples of the same state read 10-13 ms in
  total, with every renderer pass about twice as long, while the GPU ran at
  1.3-1.8 GHz of its 3.1 GHz maximum. Compare numbers measured side by side,
  and quote ratios.
- **Clock:** `Phage_Clock` costs about 2 ms of CPU wall time per frame whether
  or not its window is open. It is the host's own conductor node running three
  drivers with no cue sheet, so there is nothing to tune in the project.
- **Surface:** the Luau tick runs 0.1-0.9 ms against a 2 ms budget. Its heap
  holds at 5-6.6 MB.

## What automation could not verify

Injected pointer input does not reach Module viewport events on this build.
The following gestures are built but were not exercised by automation. Check
them by hand:

- **Phage_Plan:** foot drags in plan and knee drags in section; the `1`-`6`,
  `S`, `R` and `Esc` keys.
- **Phage_Lighting:** click and box selection, Shift/Ctrl modifiers, `A` and
  `Esc`, and the group buttons.
  - Programmer-to-canvas selection was proven through `remote_selection`.
  - The canvas-to-programmer path uses the same selection words, but was not
    driven by real clicks.
- **Phage_Desk pad clicks:** every pad's command (all 64 looks, transport,
  BLACKOUT/STROBE holds and camera) was proven through the same `rig_command`
  path. Only the click-to-Event-cable hop was not.
- **Push 2 hardware:** pads, encoders, arrows, Clip, side buttons and the
  WinUSB display. No Push 2 was connected, so the display node reports
  `winusb device not found`.

Everything else was driven and checked live:

- Every look in all four banks was recalled and captured.
- BUILD ramp timing.
- Pad lighting through FULL and partial recalls, and across Surface reloads.
- Frame and quality preset recalls.
- A 42 s recording of the energy ladder, from calm through a build into the
  CRAZY tier.

## Learn more

- [PROCESS.md](docs/PROCESS.md) is the making-of: the design decisions, the
  build order, the Module rules the build ran into, the optimisation that cut
  GPU time from 41 ms to 5.8 ms per frame, and how the looks were programmed
  and tuned.
- [PROGRAMMING.md](docs/PROGRAMMING.md) covers the programmer, lanes and
  codes, persistence, and how to regenerate the catalog, looks and desk from
  `tools/`.
- The workspace skill `stage-rig-authoring` turns this build into a procedure
  for designing a new rig.
- The Push 2 OS runtime is documented in its own
  `scripts/vendor/push2os/docs/` (runtime, editors, migration).
- The workspace skills `module-authoring`, `module-ui-authoring` and
  `mcp-automation`, and `knowledge/module-pipeline.md`, cover the Module and
  automation techniques used here.
