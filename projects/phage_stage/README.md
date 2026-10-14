# PHAGE

An arena lighting rig in the shape of a bacteriophage, programmed and running
entirely inside Sentinel. A kinetic truss carries the show: the body rises and
yaws, the capsid cage spins and contracts, and six jointed legs lift and
swing. The rig has 100 beam movers, 41 linear strobes and 47 pixel runs of
420 one-metre battens (561 GDTF fixtures in 57 DMX universes) over a crowd in a
72 x 100 m arena. What you see is what its DMX says, and any fixture you drop
onto the rig draws too. It ships a complete show:

- 16 STATIC looks: 12 beam shapes and 4 truss poses.
- 16 EFFECTS in four energy tiers: CALM, GROOVE, BUILD and CRAZY.
- 16 COLOR looks.
- 16 FULL LOOKS.

Play it from a mouse desk or an Ableton Push 2.

Under the picture is a complete show system: a Script-node surface, a packed
programmer that runs each fixture type as layers (a Halo Beam's movement, beam
and halo apart) and layered preset banks. The whole graph, renderer and
live node previews included, holds 64 Hz on a laptop RTX 5060. It needs
Sentinel 0.6.4 or later (its Fixture Rig node). A Push 2 is optional: `Phage_Desk` plays the
whole show with the mouse.

How the rig was designed, programmed, tuned and optimised is written up in
[PROCESS.md](docs/PROCESS.md). Read it before building a rig of your own.

## First run

1. Open `phage_stage.sentinel`. The program image is `Phage_Renderer`. The
   project opens with the clock running at about 200 BPM, seen from the middle
   of the crowd, on the four parts of FULL LOOK 01 GENESIS: STATIC ORIGIN, pose
   REST, EFFECTS AWAKEN and COLOR PHAGE (teal, magenta and violet). HOME, or the
   `Frame - Program F-MID` preset, returns to the composed camera.
2. Open the `Phage_Desk` panel (Window toggle in its node header). It is the
   show's desk:
   - **TAP**, **PLAY/PAUSE**, **STOP** and **SYNC**, with the tempo, bar and
     beat from the clock. TAP's lamp flashes on the beat.
   - Four banks of 16: **FULL LOOKS**, **STATIC**, **EFFECTS** and **COLOR**.
     - Each bank has its own colour, on a tab across the top of its pads:
       FULL LOOKS slate, STATIC sage, EFFECTS violet, COLOR sand.
     - FULL LOOKS and EFFECTS carry their energy tier as a step mark of one to
       four bars: CALM 1, GROOVE 2, BUILD 3, CRAZY 4. The tier legends light
       with the effect that is up.
     - STATIC 13-16, marked POSE, are the truss poses (green on the Push), lit
       alongside the beam shape.
   - **BLACKOUT** and **STROBE**, which act while held.
   - **CAMERA** arrows, **IN**, **OUT** and **HOME**, which orbit the view
     between 40 authored points.
   - **LIVE** spells out what is up, as FULL LOOK = STATIC + TRUSS POSE +
     EFFECTS + COLOR, each part named from the lit pad of its bank.
   - **PROGRAMMER** shows the Surface's last message.
3. Amber means live, and nothing else: a lit pad, the beat, a running clock. A
   FULL look lights its own pad plus the four parts it is built from: shape,
   pose, effect and colour. Recalling any single part afterwards moves that
   part's light and unlights the FULL pad, because the rig is no longer that
   look. The lit set is saved with the project. Red is only ever BLACKOUT: its
   pad fills red while held, as STROBE's fills white.
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
truss pose or the EFFECTS tier underneath it. Octave Up / Down on the Push pages
the pads to each fixture type's layer banks: one look's movement under
another's beams, or a chase over the battens' content. Pad page 5 is SEQUENCES:
fifteen whole-rig sequences (IGNITION, INJECT, SCAN, SHOCKWAVE...) on every
fixture type at once, or each type's part of them. Every look is listed in
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
| `Phage_Lighting` | The console. It reads the Fixture Rig and builds the show's fixture table every frame (which slot or pixel run each rig fixture plays, where the truss carries it, its pan and tilt limits from its GDTF), plays the looks on those fixtures and turns them into DMX through every fixture's GDTF:<br>- motors: pan 300 deg/s, tilt 220 deg/s<br>- optics: 3 deg beam, 40 m reach, ring glow<br>- strobes: a white tube plus a colour plate<br>- pixel bars: the 47 runs' content, 16 content looks (LED Pixels)<br>- DMX: every fixture encoded through its GDTF, with the live proof (`dmx_*` control outputs)<br>- selection canvas: front elevation and plan, with group buttons<br>Publishes LED Pixels, DMX, the fixture table (Rig Fixtures, Rig Mounts, Rig Slots) and Selection. |
| `Phage_Program` | The programmer: 616 rows x 17 attributes, one row per layer of every fixture (each slot's base row: a Halo Beam's MOVE, a strobe's TUBE, a batten's PIXELS, an axis; then the Halo Beams' BEAM and every fixture's second layer: HALO, PLATES, CHASE). The Surface writes it in batches and commits it as one revision. Its preview is the programmer sheet. |
| `Phage_Show` | Show state:<br>- the five lanes (KICK, SNARE, HI-HAT, BUILD, PHRASE) derived from the Clock<br>- palettes A/B/C<br>- the strobe clock<br>- blackout and strobe holds<br>- the switch that hands the rig to the programmer |
| `Phage_Venue` | The arena: a 72 x 100 x 30 m hall with seating tiers, roof steel, a crowd, room fill and materials. Its preview checks roof clearance at the truss's kinetic maximum. |
| `Phage_Renderer` | HDR program render of what the DMX says: it decodes every rig fixture's DMX through its GDTF (the `vis_*` passes) and draws beams and ring glows in haze, strobe flashes, pixel-bar glow, floor reflections, bloom, a highlight shoulder and lens streaks. Fixtures of any other GDTF type draw from their types: bodies, lit cells, and a beam or wash in the haze. Link a DMX In to its DMX input and a console on the network plays the picture. Temporal anti-aliasing (`taa`, on by default): every raster pass and the haze draw a different sub-pixel position each frame, and one resolve averages 8 frames along the camera, clipped to what each frame shows so nothing trails; thin battens and truss tubes stop stair-stepping for about 0.05 ms of GPU. |
| `Phage_Camera` | Shared camera for the renderer. The desk and Push 2 arrows orbit it between 40 authored points, which gives show-level camera switching (the reason it is an external camera). |
| `Phage_Clock` | Conductor: tempo and beat. Three `ref()` expressions feed `Phage_Show`. |
| `Phage_Surface` | Script node that runs the show:<br>- the desk's clicks and feedback<br>- the window DESK view<br>- the Push 2 surface (four pages, the layered fixture programmer, look banks and four pages of pads with each fixture type's layer banks, transport keys, orbit camera)<br>- the `rig_command` seam<br>Source in `scripts/`. |
| `Phage_Desk` | The mouse desk: a 93-control panel (77 pads). Clicks travel on its `panel` Event cable to the Surface, which runs them and lights the pads through `panel_feedback`. Generated by `tools/phage_desk.py` and drawn with the Interaction Lab UI kit (`modules/_shared/ui/il_*.hlsli`): a layout pass records a draw list, the kit's rasterizer draws it. About 0.6 ms of GPU a frame. |
| `Phage_Push2_Display` | Push 2 display node fed by the Surface's display output. |
| `Phage_Rig` | Fixture Rig: the show's fixtures, the one authority every node follows. It imports `assets/phage_rig.mvr` (561 fixtures of PHAGE's three GDTF types, patched in 57 universes) against the `assets/gdtf/` library and owns the types, the placement and the patch from then on. Add, delete, move or re-patch a fixture on its plan and the programmer, the DMX and the render follow. |

| `Phage_ArtNet` | DMX Out of Lighting's DMX: 57 universes of Art-Net, unicast to 127.0.0.1 until you point it at a node or a visualiser. It ships **disabled**: PHAGE plays fully as previz with no DMX going out. |

### Instrument canvases

Every node canvas except the renderer's image and the Push 2 display is drawn
with the Interaction Lab kit, fills its panel and answers the pointer. Nothing
is stored: point and read.

| Canvas | Point at | You get |
|---|---|---|
| Plan | a foot, a leg, or the knee in section | The handle a press would take lifts, with a card: the leg, what a drag or click does there, its reach and its hand edits (live while dragging). The legs are numbered at their feet. |
| Motion Control (Kinetics) | an axis row, or a leg, the capsid or the body in either view | The same axis lights in the plan, the elevation and the meters, and the row shows its travel limits. An axis still travelling shows a dashed run to its target and the target's value. |
| Truss Axonometric (Assembly) | a truss member | Its real tubes light; the card gives the part, length, truss width, bays and tube count. |
| Fixtures (Lighting) | a fixture, or a group button | A card for the fixture, ringed in both views; or the group's members ringed before you press. |
| Programmer Sheet (Program) | a cell | The fixture and its layer (one column per program row, grouped MOVE, BEAM, HALO, TUBE, PLATES, PIXELS, CHASE, AXES), the attribute, and what its value means in physical units and the layer's own look names. |
| Show Monitor (Show) | a lane | Where its timing comes from, the timing and its last hit. A tape shows every lane's hits over the last 8 beats. |
| Arena (Venue) | the plan or the section | One cursor line through both views at the same z, and the hall read at the pointer. |

The canvases, the desk included, cost about 3.6 ms of GPU a frame together with their panels around 1400 x 900
(measured when the pixel bars still had a canvas of their own); the renderer alone is about 8 ms.

- **Scripts:** `scripts/Phage_Surface.luau` is the entry. Show logic lives in
  `scripts/show/` and page factories in `scripts/pages/`.
- **Push 2 OS:** the pinned package is in `scripts/vendor/push2os/` (MIT, see
  its LICENSE). Its hashes are in `scripts/push2os-provenance.json`, and
  `.gitattributes` keeps those bytes exact.
- **Preset banks** in `presets/`:
  - `phage_stage_static`, `phage_stage_effects`, `phage_stage_color`:
    layered partial presets.
  - `phage_stage_complete`: FULL LOOKS.
  - `phage_stage_rhythm`.
  - Fixture banks, pad pages 2-4: `phage_stage_move`, `_beam`, `_halo`,
    `_heads` (Halo Beams); `_tube`, `_plates`, `_strobes` (Linear Strobes);
    `_pixels`, `_chase`, `_battens` (Pixel Battens).
  - `phage_stage_push2`: surface state, palettes, sequences and custom
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

Dimensions are an interpretation of my concept image, not a surveyed stage.

## Fixtures, plot and DMX

**The fixtures are GDTF types of Sentinel's own.** `tools/phage_gdtf.py` writes them from the constants the
renderer draws them with (the head's lathe profile, the yoke outline, the mover scale, the strobe and bar
sections), so the GDTF and the drawn fixture cannot disagree. Each carries glTF meshes for other visualisers, a
rendered thumbnail and two modes. The spec sheet with every channel chart is
[`assets/gdtf/FIXTURES.md`](assets/gdtf/FIXTURES.md).

| Type | Is | Modes |
|---|---|---|
| Halo Beam | LED beam mover, 1-20 deg zoom, frost, a 24-cell RGB halo | Standard 15ch (the halo as one colour), Pixel 83ch |
| Linear Strobe | 1 m tunable-white tube (6500-2200 K) between two RGB plates | Standard 7ch, Pixel 10ch |
| Pixel Batten 1000 | 1 m RGB batten, 20 pixels at 50 mm | Pixel 60ch, Bar 4ch |

All three read **Verified** in the Fixture Rig: the refinements in `assets/gdtf/refinements/` confirm the halo's
pan and tilt sense and every type's cell order, and name the evidence (the beam check and loopback below).

**The plot** is `assets/phage_rig.mvr`, written by `tools/phage_mvr.py` from the creature at rest: 100 Halo
Beams, 41 Linear Strobes and 420 Pixel Battens. Each pixel run is one-metre bars butted along every straight piece,
as many as fit, centred; 420 m of the 458 m of runs carry light. The sheath and collar rings are sized so each side
takes two bars with corner clearance. [`assets/PATCH.md`](assets/PATCH.md) is the patch: movers on universes 1-3
(Standard 15ch), strobes on 4 (Standard 7ch), battens on 5-57 (Pixel 60ch). Identity, for anything that maps a
fixture back to PHAGE: FixtureID is the PHAGE slot + 1 for movers and strobes, and 10000 + run x 100 + unit for
battens, whose UnitNumber is the unit and whose CustomId is where the bar starts along its run in millimetres. The
rig numbers a fixture added later after the highest FixtureID, inside the battens' range, so the UnitNumber is what
tells a batten from a guest.

To re-plot after changing the anatomy: set `Phage_Kinetics` **Drive** to Rest, capture its `Mounts` and
`Bar Pieces` ports into `tools/mounts_rest.json` and `tools/pieces_rest.json`, run `python tools/phage_rig.py`
and `python tools/phage_mvr.py`, then **Re-import** in `Phage_Rig`'s Properties.

**The rig is the authority.** `Phage_Lighting` reads `Phage_Rig` and rebuilds the show's fixture table every
frame (`modules/Phage_Lighting/rig_*.hlsl`, contract in `modules/_shared/phage_rig.hlsli`):

- **Which slot each fixture plays.** A fixture the plot names plays its own slot or pixel run. Any other fixture (one
  dropped onto the rig's plan, of any GDTF type) takes a free slot of its role. A type that pans and tilts plays a
  mover slot. A line of eight or more cells within 0.6 m of a pixel run joins that run where it sits. Anything else
  plays a strobe slot. A free slot the anatomy has no mount for goes first; then one whose plotted fixture the rig no
  longer has, inheriting that fixture's programming.
- **Where it is.** Its placement on the rig, carried by the truss: read in the rest frame of the mount it hangs from
  (its own slot's, the run piece under its middle, or the nearest mount within 2.5 m) and set in that mount's live
  frame from Kinetics.
- **What it can do.** Pan and tilt limits from the channel ranges of its GDTF mode.

Every Lighting pass plays that table, and the Surface's programmer takes its fixtures from it (Lighting's `rig_word*`
presence outputs): a deleted fixture leaves the groups, an added one joins them. With the plot unchanged nothing moves:
the table's mounts match Kinetics within 1e-5 m on all 196 slots, and every DMX channel and the render are unchanged.

**DMX.** Lighting writes every fixture's state from what the looks play and encodes it through that fixture's GDTF
ranges (`dmx_*.hlsl`, the fixture engine's codec, vendored in `modules/_shared/`):

- **Halo Beam:** pan and tilt from the motors, beam and halo levels as the desk sets them (no render gain), their
  palette colours, zoom from the beam angle.
- **Linear Strobe:** tube and plate levels, the tube's warmth as colour temperature, the plates' colour.
- **Pixel Batten:** each pixel from the pixel-bar content where it sits on its run, less the pixel-bar peak.
- **Any other type:** a head is aimed through its own GDTF (`modules/_shared/phage_aim.hlsli`: the pan and tilt that
  throw its beam where its slot's beam goes, inside its ranges), its main beam or wash carries the slot's beam and any
  other emitter its halo; on a strobe slot its colour carries the plates' and its white the tube's.

`Phage_ArtNet` ships disabled, so the project plays as pure previz. To drive real fixtures or a visualiser, point its
`destination_host` at your Art-Net node or visualiser (Art-Net port address = universe - 1) and enable the node. It
sends from `source_port` `any`, so it never takes UDP 6454 from a visualiser on the same machine. A trial license sends
1 universe and holds the rest (the node's `trial_gated_universes` counts them); all 57 need a license.

**Proof, live.** `dmx_beam_error_deg` decodes every mover's pan and tilt back out of the DMX, rebuilds the beam with
its GDTF's convention in its live mount frame, and reads the worst angle to the beam the looks play: 0.034 deg over
100 movers (16-bit quantisation). **Loopback:** add a DMX In (Art-Net, `universe_start` 0, `universe_count` 57), link
its DMX to Lighting's `Loopback` input and freeze Lighting: `dmx_loopback_differ` reads 0 held still (it read 57
universes back and 0 channels different). Remove the DMX In afterwards; it also holds UDP 6454.

**The render is the DMX.** `Phage_Renderer` draws what the DMX says, not what Lighting computes: every fixture's DMX
goes back through its GDTF to a canonical state (the fixture engine's decoder), each fixture sits where the fixture
table has it, and the decoded state becomes the movers' pose and optics, the strobes and the pixel-bar texture.
Against Lighting on a frozen frame: pan within 0.004 deg, tilt within 0.002 deg, beam and ring levels and colours
exact, strobe plates within one DMX step, pixel bars within 1 % mean (5 cm pixels, and the slack between the 1 m bars
dark, as on the real rig). Link a DMX In to the renderer's DMX input instead of Lighting's and a console on the
network plays the same picture.

**Any GDTF draws.** A fixture of another type renders from its GDTF with no code: bodies (the type's boxes and
cylinders, turned by pan and tilt), lit faces (cells, discs, rings, LED or lens) as the fixture engine draws them, and
its main emitter as one source in the haze and on the surfaces. Tested by adding two Martin MAC Aura XIPs to the rig
and deleting one Halo Beam: the Auras took free mover slots, hung from the nearest mounts and rode the truss, joined
`select movers` (101 heads), aimed from the encoders, encoded within 0.044 deg and drew their washes; the deleted
Halo Beam left the groups, the DMX and the render. Those GDTFs are manufacturers' files and are not in the project.

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

The following gestures are built but were not exercised by automation. Check
them by hand:

- **Phage_Plan:** foot drags in plan and knee drags in section; the `1`-`6`,
  `S`, `R` and `Esc` keys.
- **Phage_Lighting:** click and box selection, Shift/Ctrl modifiers, `A` and
  `Esc`, and the group buttons.
  - Programmer-to-canvas selection was proven through `remote_selection`.
  - The canvas-to-programmer path uses the same selection words, but was not
    driven by real clicks.
- **Push 2 hardware:** pads, encoders, arrows, Clip, side buttons and the
  WinUSB display. No Push 2 was connected, so the display node reports
  `winusb device not found`.
- **DMX beyond this machine:** the Art-Net was proven by loopback on 127.0.0.1
  only. No external node, console or visualiser received it, and no physical
  Halo Beam, Linear Strobe or Pixel Batten exists to check: they are designs.
- **The plot elsewhere:** `assets/phage_rig.mvr` and the GDTFs were read back
  by Sentinel, not yet by another visualiser or console.
- **External DMX into the render:** the renderer decodes whatever is linked to
  its DMX input, but no external console has played it yet.
- **Guests by drag:** guests were added through `sentinel_fixture`, which is
  the same rig edit a Library drag makes; a real drag was not done here.

Everything else was driven and checked live:

- Every look in all four banks was recalled and captured.
- BUILD ramp timing.
- Pad lighting through FULL and partial recalls, and across Surface reloads.
- Frame and quality preset recalls.
- A 42 s recording of the energy ladder, from calm through a build into the
  CRAZY tier.
- Desk clicks end to end. A real click on the PHAGE pad, and presses of
  GENESIS, ORIGIN, REST, BLACKOUT and STROBE through the host's control path
  (`sentinel_ui viewport_control_drag`), left press and release records on the
  `panel` cable. The Surface lit GENESIS with its four parts, the LIVE line
  followed, and the holds filled red and white while held. Every pad's command
  (all 64 looks, transport, holds and camera) was also proven through
  `rig_command`. The transport and camera pads were not pressed on the panel,
  so the tempo and the composed camera stayed put; they use the same hop.

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
