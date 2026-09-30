# How PHAGE was made

This is the working record of the build: what was decided before any code,
the order the graph went up in, the rules the build ran into, how the graph's
GPU time went from 41 ms to 5.8 ms per frame, and how 64 looks were programmed
and tuned on the live rig. The [README](../README.md) says how to play the show,
[PROGRAMMING.md](PROGRAMMING.md) documents the programmer and
[LOOKS.md](LOOKS.md) lists every look. This file explains why they are the
way they are.

Read it before building a rig of your own. Most sections end with the rule
worth carrying forward. All timings are from an NVIDIA GeForce RTX 5060 Laptop
GPU running Sentinel 0.5.90.

## The brief

The brief was a reference image and a spoken paragraph:

- Build a stage like the image on the existing stage-rig show system.
- The truss should move.
- Use at most three fixture types: strobes, moving heads, and a linear
  fixture that can chase along the legs.
- Program plenty of static looks, a full colour bank, and effects that climb
  in energy: calm, then grooving, then a build, then "absolutely crazy".
- Take it to the next level.

"Next level" was read as two things. First, the truss is a performer, not
scenery. Second, the looks program the steel as well as the lights, with the
same tools.

## Reading the reference

Before any design, every visual element in the image was listed. The rig was
then built from that list:

| In the image | In PHAGE |
|---|---|
| A cage-like head | A truss capsid with 24 nodes, riding a spinning, contracting sheath |
| A collar with a ring of pixels | A collar ring of movers, strobes and pixel bars |
| A stacked-ring tail | A sheath column of ring bars |
| A hexagonal base plate with movers under its edge | Plate outer and inner mover rings, and plate-edge bars |
| Six jointed legs with light lines | Six IK legs, each with two bar lines per segment |
| Spiked feet | Spike cones with upward movers |
| A DJ riser inside a ring of movers | A booth ring of 16 movers around the riser |
| Haze, a crowd, a dark hall | A 72 x 100 x 30 m arena with seating tiers, roof steel and 1,264 people |

The three fixture types were chosen for three jobs:

- **Beam movers** draw shapes in the haze.
- **Linear strobes** (a white tube plus a colour plate) give impact and a
  colour wash.
- **Pixel bars** trace the structure and chase along it.

Every look was later designed around those jobs.

## Decisions made before any code

### One construction model

`modules/_shared/phage_anatomy.hlsli` is the only place the phage's geometry
is defined:

- the hip, knee, ankle and foot of each leg, with two-bone IK;
- the capsid vertices and edges;
- the collar, sheath and plate;
- every fixture mount.

`Phage_Plan`, `Phage_Kinetics` and the Venue's silhouette pass all include
it. Nothing downstream re-derives a position; it reads the mounts that
Kinetics publishes.

The Python look compiler does not re-implement the anatomy either.
`tools/phage_review.py mounts` captures the 248 live `Mounts` records from the
GPU at the Rest pose, and every tool reads that capture
(`tools/mounts_rest.json`). There is one model and one measured copy of it, so
the two cannot drift apart.

### Stable program slots

The programmer has 248 fixed rows:

| Slots | Holds |
|---|---|
| 0-127 | Movers |
| 128-175 | Strobes |
| 176-239 | Pixel bars |
| 240-247 | Kinetic axes |

Each family has headroom. Changing a fixture count in the Plan switches rows
on and off; it never moves a fixture to a different row. So stored looks stay
correct when the rig changes, and every look already programs the spare
movers.

### The truss is a fixture

Each kinetic axis is a programmer row with pan and tilt:

- the body (height and yaw);
- the capsid (spin and sheath contraction);
- the six legs (swing and lift).

`Phage_Kinetics` maps each row onto its axis and moves it under speed and
acceleration limits:

| Axis | Limit |
|---|---|
| Body height | 1 m/s |
| Capsid spin | 120 deg/s |
| Leg lift | 3.8 m/s |

This one decision made the moving truss cheap to program. Lanes, movement FX,
chase orders, look banks and the desk all drive steel exactly as they drive
lights:

- A truss pose is a static look.
- A walking gait is an effect on the leg rows.
- A build that raises the body is the BUILD lane on the body row.

### A plan authority, with relational re-rolls

`Phage_Plan` owns the construction. Its canvas is a plan over a radial section
through the selected leg:

- The plan shows where the feet land.
- The section shows how high the knee rides.
- Both are drawn from the same handles.

Legs turn red when they cannot reach their foot, fold below their hip, or
crowd a neighbour.

A phage is relational: six legs spaced around a hub. Random coordinates would
destroy it, so the exploration axis is a **stance** enum instead (Reference,
Spider, Mantis, Crab). Each stance offsets all six legs together, and
symmetric editing mirrors one leg's edit onto its partner.

### Useful before it is programmed

Every node shows a meaningful result before the programmer engages:

- Lighting has a reference aim and chase.
- The LED node has a reference gradient chase.
- Kinetics has a Demo drive.

So each node could be checked visually the moment it was created, long before
the show layer existed.

### An external camera, justified

The renderer's internal camera is the default for authored 3D. PHAGE uses an
external `Phage_Camera` for one reason: the show orbits the view between 40
authored points from the desk and the Push, and that is show-level camera
switching.

## Building the graph

The graph went up one node at a time. Each node was created, placed, wired and
checked live before the next:

| Order | Node | First proof |
|---|---|---|
| 1 | `Phage_Plan` | Design records matched the spec; plan and section drawn |
| 2 | `Phage_Kinetics` | Demo motion with planted feet; the motion-control monitor |
| 3 | `Phage_Assembly` | 5,504 truss tubes and 51 solids drawn from the real members |
| 4 | `Phage_Venue` | 1,264 people parted around the feet; 1.9 m roof clearance at kinetic maximum |
| 5 | `Phage_Camera`, `Phage_Renderer` | First worklight render of the phage in the hall |
| 6 | `Phage_Program` | 248 rows written and committed as one revision |
| 7 | `Phage_Show`, `Phage_Clock` | Five lanes animating at 126 BPM from three `ref()` drivers |
| 8 | `Phage_Lighting` | Beams in haze; 24 fixtures selected through the remote path |
| 9 | `Phage_LED` | 47 bars running the reference chase on the render |
| 10 | Optimisation pass | See below |
| 11 | `Phage_Surface` | Push 2 OS runtime RUNNING; looks recalled through `rig_command` |
| 12 | `Phage_Desk`, `Phage_Push2_Display` | Every pad's command proven; pads lit by feedback |
| 13 | Look banks | All 64 looks recalled and captured on the live rig |

## Module rules the build ran into

Each of these cost time once. Most are Sentinel or HLSL rules that apply to
any Module:

| Symptom | Cause | Rule |
|---|---|---|
| The renderer manifest was refused: data input slot 8 is out of range | At most 8 data inputs per Module | Pack related records into one buffer with a documented layout. The Venue packs room settings, emitters, architecture and crowd behind a header row. The Assembly packs tubes then solids. Lighting appends strobe records to its optics. |
| X3003, redefinition of `_DataType_1` | One data input bound twice in a pass | Bind each input once. Read a second record type through a field-mapping helper (`phStrobeOf`). |
| X1507, cannot open an include | Include paths resolve from the including file | Shared headers include each other as `../_shared/x.hlsli`. |
| X3504, out-of-bounds index in a literal loop | HLSL ternaries evaluate both sides | Clamp the index before the select. |
| X3020, type mismatch in a conditional | Ternary on structs | Use if/else. |
| X3005, `length` is a variable | A parameter named after an intrinsic | Rename it (`hall_length`). `out` is reserved as well. |
| The Program preview lagged one edit behind | An `on_dirty` preview of its own persistent buffer | Run a node that displays its own persistent state every frame. |
| The selection canvas forgot its state | `state_buffers` nested under `viewport` | `state_buffers` is top level in the manifest. |
| The renderer went dark: no beams | A scripted manifest rewrite dropped `output: buffer:sources` | Diff every scripted manifest edit before reloading. |
| The canvas said WAITING FOR MOUNTS | `_DataN_Count` is numbered by manifest data-input order | Check the index against the manifest, not the pass slot. |
| A 43 s compile (Venue preview) and a 16 s compile (Plan marks) | FXC inlines every call: per-pixel leg IK and about 25 text call sites | Precompute geometry in a one-thread pass. Give each heavy routine one call site. Queue text and draw it in one loop. Mark loops `[loop]`. Both compiles dropped under a second. |
| Black 8 x 8 tiles in the render | NaN in a data port, spread by tile-shared light staging | Guard degenerate maths: `atan2(0, 0)` for a mount on the body axis, and `pow` of a tiny negative base. Scan every data port for non-finite values. Let integrators restart an axis whose state goes non-finite. |
| Injected clicks did nothing on the canvases | Injected input does not reach Module viewport events | Prove selection through a remote parameter path, and list the gestures that need a hand test. |

## Optimising: 41 ms to 5.8 ms

### Measure first

The profiler reports per-node and per-pass GPU time (`sentinel_graph
action=profile`, sort by `gpu_ms`). At its worst the graph cost 41 ms of GPU
per frame:

| Where | GPU per frame |
|---|---|
| Renderer venue shading | 13.8 ms |
| Renderer crowd | 7.0 ms |
| Rest of the renderer | 3.7 ms |
| Eight node previews | about 16 ms |

Two facts shaped the fix:

- **Shading cost scaled with lights times pixels.** Every lit surface pixel
  looped over all 352 light sources and 96 bar emitters.
- **Previews cook every frame, whether or not their panel is open.** A
  closed preview is a standing cost, so each one had to be cheap by
  construction.

GPU timestamps also move with the GPU clock. When the frame cap leaves
headroom, a laptop driver lowers the clock and every pass reads longer. The
same finished state later measured about twice its first numbers at 1.3-1.8
GHz of the GPU's 3.1 GHz. So every before/after here was measured side by
side, minutes apart, and the ratios are what carry over to other machines.

### The renderer: a light grid and tile-culled haze

**Light grid.** A compute pass (`lightgrid.hlsl`) divides the hall into
24 x 10 x 32 world cells. Each cell stores:

- up to 8 lights whose cones reach it;
- the pixel-bar emitters within 4 m;
- an L1 probe (ambient plus a direction) for everything else.

Surface shading reads only its own cell. A window, `(1 - d^2/16)^2`, fades a
near emitter into the probe, so near and far always sum to the same light and
the handover is invisible. A cell that overflows falls back to the full loop.

Venue shading went from 13.8 ms to about 1.5 ms, and the crowd from 7.0 ms to
under 1 ms.

**Haze.** The volume pass runs at half resolution. It now works in 8 x 8
pixel tiles:

- Each tile culls the lights against its own view cone into groupshared
  memory. Order does not matter, because in-scatter is a sum.
- Ring glows and strobes use closed-form integrals instead of samples.

The haze pass went from 3.3 ms to 1.1 ms.

The A/B caught the one regression. The capture came out half as bright,
because culling had also removed the long, faint pixel-bar glow that lit the
whole haze. That glow is now windowed by a `glow_range` parameter: the default
of 10 m keeps the cost down, and 60 m restores the full wash.

The renderer went from 24.5 ms to 4.45 ms.

### The canvases: marks and tile bins

Every canvas had drawn itself by looping over every fixture, member or
segment for every pixel. They now share one pattern (`_shared/ph_marks.hlsli`):

1. **Marks.** A small compute pass writes the canvas's primitives in draw
   order: lines, discs, tubes, diamonds, dots, rings, rectangles, frames and
   dashed rings, in screen space.
2. **Bins.** A bins pass sorts them into 8 x 8 blocks of 16 px tiles. The
   survivors are kept as a bitmask and walked lowest bit first, so draw order
   is preserved without a sort.
3. **Draw.** The pixel shader draws only the marks in its own tile. An
   overflow flag falls back to the full loop.

Captions go through a queue (`_shared/ph_textq.hlsli`) that each tile filters
by bounding box. The glyph routine then has a single call site, which also
fixed the compile times.

Two refinements followed from profiling:

- Lighting's marks pass had one warp loop over 248 slots x 16 groups; a
  separate parallel `groups` pass replaced it.
- The survivor bitmask cut the bins pass from 0.62 ms to under 0.05 ms.

| Canvas | Before | After |
|---|---|---|
| `Phage_Plan` | 2.7 ms | 0.25 ms |
| `Phage_Venue` | 1.5 ms | 0.4 ms |
| `Phage_Assembly` | 1.4 ms | 0.24 ms |
| All eight previews | about 16 ms | about 1.4 ms |

### Proving parity

Every rewrite was checked against the old version by capturing both and
diffing them:

- The Plan canvas differed in 1,207 of 1.23 million pixels, all antialiasing.
- The Kinetics canvas turned out to have drawn its plan and elevation views
  empty all along. The rewrite fixed a bug nobody had seen.

### The result

The graph went from 41 ms to 5.8 ms of GPU per frame, a factor of seven. The
finished show, with the Surface, desk and every preview running, holds 64 Hz;
it first measured about 7 ms of GPU per frame, and 10-13 ms when the driver
later held the GPU at a lower clock.

The remaining CPU hotspot is `Phage_Clock` at about 2 ms per frame. That is
the host's conductor node running its own control clock (about 440 Hz ticks),
so there is nothing to tune in the project.

## The show layer

### Forking the surface

The show runs in one Script node, `Phage_Surface`. It carries:

- the Push 2 OS runtime;
- a registry of show modules;
- the programmer, look store and rhythm lanes;
- the desk and Push surfaces;
- the `rig_command` automation seam.

Most of that code is generic show control. Only about 15 files carry
rig-specific knowledge, and only those were adapted:

- the fixture catalog, attributes and groups;
- the programmer core (`static_rig`);
- the graph bridge (`rig_bridge`);
- the look store and commands;
- menus, the selection view and the camera orbit;
- titles and the desk layout;
- the entry script.

The runtime is vendored unchanged in `scripts/vendor/push2os/`. Its file
hashes are pinned in `scripts/push2os-provenance.json`, and `.gitattributes`
marks it `-text`, because line-ending conversion breaks the pins.

Three of the adapted files are generated from the rig, never hand-edited:

| File | Generated from |
|---|---|
| `fixture_catalog.luau` | The captured mounts |
| `preset_titles.luau` | The look definitions |
| `desk_layout.luau` | The desk's control list |

Groups exist twice, once in Luau for the programmer and once in HLSL for the
canvas, and the two definitions mirror each other.

### Traps in the Script node

- **Heap exhaustion.** While the Desk node was missing, the desk label writer
  retried every tick, and each failed host call kept memory. The 64 MB heap
  filled in 37 s. The writer now backs off until a full refresh, and the heap
  holds at 5-6.6 MB even with the Desk removed.
- **A wedged VM.** A Script node that has exhausted its heap cannot reload,
  relaunch or reset, because each of those serializes first. Recreate the node
  with its parameters and links.
- **Preset groups need a saved project.** Until the project had a path, every
  recall failed with `preset GROUP_ABSENT`.
- **The Push 2 OS persistence group needs a seed.** `preset.save` updates an
  existing preset, so `stagerig_phage_push2` ships with its "current" preset.
- **New durable records break old snapshots.** Adding a push2os `persist`
  record makes every older reload snapshot refuse to restore
  (`SNAPSHOT_RECORD_MISSING`). Plain `host.state.register` values reset on
  reload. Durable additions go in the entry script's serialize table, as the
  lit-pad set does.
- **Fire-once writes can be dropped under load.** The BUILD origin write was
  lost on some recalls, so it is now retried until the write lands.
- **`[push2os] bank save failed: false`** in the log means the asynchronous
  save has not finished. The saves land.

## Programming the lights

### Looks are geometry, compiled per fixture

No pan or tilt value was typed by hand. `tools/phage_looks.py` states each
look as intent and compiles it against the captured mounts. It aims with the same
inverse the GPU uses (`phAimAngles`), which round-trips direction to pan/tilt
and back to within 3e-5.

A shape is a function from a fixture to a direction, a level and a ring glow,
or `None` to leave that fixture alone:

```python
def shape_crown(f):
    fam = f["family"]
    if fam in (2, 3, 4, 6): return to(f, APEX), 1, .9           # every beam meets 36 m above the rig
    return None if fam == 5 else (mul(UPW, -1), 0, .15)         # plate beams off; booth untouched
```

Intent stays readable in the code:

- CAGE laces each knee beam across to the next leg's foot.
- FRONT fans every beam onto the front of the crowd.
- HALO sets every beam tangential and level, so each tier becomes a ring.

A mover's `rise` in an effect is signed per mount, so hanging and upright
heads rise toward the sky together.

The compiler also reports how many movers each shape lights and its tilt
range, so a bad aim shows up before any capture.

### Static shapes and truss poses

STATIC 1-12 are beam shapes. They write only mover and bar rows.

STATIC 13-16 are truss poses: REST, RISE, INJECT and BLOOM. They write only
the eight axis rows. For example, INJECT drops the body and contracts the
sheath, as a real phage does when it injects.

Because shapes and poses write disjoint rows, they layer: any shape can sit on
any pose.

### Effects: an energy ladder

An effect is a set of attribute dictionaries per role: movers, strobes, bars,
body, capsid and legs. Each role picks from:

- **Lanes:** KICK, SNARE, HI-HAT, BUILD or PHRASE.
- **Movement FX:** repeats, a random gate, jumps, steps or continuous spin.
- **Chase orders:** AROUND, MIRROR, OUT, UP, FRONT, SIDE, SHUFFLE or LEG.
- **Strobe looks:** PULSE, STROBE, SPARKLE, BLINDER, GLOW or OFF.
- **Bar looks:** 16 content patterns.

The four tiers are a dynamic range, and each has its own rules:

| Tier | Clock | Motion | Strobes |
|---|---|---|---|
| CALM | Mostly the 16-beat PHRASE lane | Slow drift and tide; capsid spin at 1/4 | Tubes dark: GLOW or OFF |
| GROOVE | KICK, SNARE and HI-HAT | Contained sweeps; legs walk and sway on the beat | Colour plates on the kick or hat; BLINDER on the snare |
| BUILD | The BUILD lane: 16 beats from the recall | Amplitude, tilt and truss travel grow with the ramp; pulses double each quarter | STROBE, SPARKLE and PULSE riding the ramp |
| CRAZY | Mostly KICK | Jumps, fast spin, legs thrown | STROBE, SPARKLE and BLINDER |

The BUILD tier needed a rule in the show layer, not just in the looks.
Recalling a BUILD effect or full look restarts the ramp on the next beat, so a
build fired 16 beats before the drop peaks on the drop. The ramp then holds at
the top until the next recall.

### Colour

Colour is an 8-palette library, each palette with A, B and C colours, plus a
routing function per fixture. Examples:

- mono: A on beams, B on rings;
- zones: capsid, legs and body in different slots;
- low/up: split by height;
- sides: house left against house right;
- alternating fixtures.

The 16 colour looks are palette and routing pairs. So SPLIT and UV SPLIT are
one routing function on two palettes.

### Full looks

A FULL look is a composition of four parts plus a few global overrides:

- a shape;
- a pose;
- an effect;
- a colour;
- overrides such as haze or bloom.

The banks own disjoint attributes, so they mix freely:

| Bank | Owns |
|---|---|
| Static | Pan, tilt, level and ring |
| Colour | Palettes and routing |
| Effects | Every effect attribute, plus the strobe clock |
| Full | Everything, plus the render globals, rhythm, pitch and master |

The FULL bank climbs the same energy ladder as the effects:

- GENESIS and LULL open the set.
- ASCENT, PRESSURE, IGNITION and ZERO build.
- RIOT, STORM, SHATTER and SUPERNOVA are the drops.

## The tuning loop

### Tools

`tools/phage_review.py` drives the live rig exactly as the desk does:

- **`sheet`** recalls every look in a bank and writes a labelled contact
  sheet. BUILD looks are captured further into their ramp.
- **`strip`** writes filmstrips: frames at fixed times after each recall, one
  row per look. Motion and pulses can only be judged in a strip; a single
  still of a kick-driven look catches a random moment.
- **`steady`** pastes neutral effect rows into the live programmer without
  storing them, for repeatable frames. A paused clock darkens every
  lane-driven fixture, so it cannot be used for A/B.

Effects were judged over a fixed base: static SUNBURST, pose REST and colour
PHAGE. That way only the effect changed between frames.

### What the loop caught

Every look was recalled and captured, and several changed as a result:

| Look | Problem seen | Fix |
|---|---|---|
| All | Beams barely registered in the haze; more haze only added murk | Swept beam gain at 6, 18 and 40. Baked `beam_gain` 10, `beam_falloff` 0.45, `ring_haze` 0.35 and a lighting master of 1.0. |
| Fresh programmer rows | Strobes sat as steady white tubes: PULSE with no lane is fully on | Fresh rows and FX OFF now put strobes on GLOW. |
| CAGE, FRONT | Weak, illegible shapes | Reworked: lacing between legs, and a fan onto the front crowd. |
| ICE, ROSE, DUSK, CORAL, GLACIER | Colours that did not read | A new ICE palette, a new SUNSET palette and a GLACIER route. |
| EMBER | Dark beats | Moved to the kick lane. |
| ORBIT | A white-out on every snare | Plates GLOW on the kick. |
| BUILD tier | The ramp did not restart on later recalls | The BUILD origin write retries, rounded up to the next beat. |
| RIOT | Fully black between kicks | Wider pulse, so it decays across the beat. |
| STORM, SUPERNOVA | A grey-white wash and faint beams | Colour plates had no lane and so stayed fully on. They now ride the kick, and the renderer's `strobe_haze` dropped from 1.0 to 0.5. |
| STORM, SUPERNOVA | Beams gone half of every beat | They rode the HI-HAT lane, which rests half of each beat. Movers moved to KICK. |
| SHATTER | A warm murk | Blinders moved to the snare: beats 2 and 4. |
| EMBERS, STORM (full) | Reworked after the FULL contact sheet | EMBERS rebuilt on FRONT; STORM became cold ICE lightning on PINPOINT. |
| SUPERNOVA (full) | Grey-white | A teal and magenta SPLIT on SUNBURST. |
| IGNITION (full) | A brown wash | Accelerating white pulses on X-FIRE. |

The rule behind most of these: **a fixture with no lane is fully on.**
Lanes are what give a look its shape in time.

## Desk, pads and persistence

`tools/phage_desk.py` generates the desk from one control list, so the four
consumers can never disagree:

- the Module manifest;
- the shader layout;
- the Surface's index map;
- the `_ui.generated.hlsli` contract that `tools/module-ui.ps1` validates.

Pad titles come from the look definitions, so renaming a look renames its pad.

Lit pads have to tell the truth:

- A FULL look lights its own pad plus the four parts it was built from. The
  parts are stored with the FULL preset as `look_parts`.
- Recalling any single part afterwards unlights the FULL pad, because the rig
  is no longer that look.
- The lit set is carried in the Surface's serialize table, so it survives
  reloads and project saves.

The orbit camera had an authored-angle bug: every authored point landed up to
about 4 m off. It is fixed, and HOME (MID F) ships as a saved point equal to
the frame contract.

## Presets, proof and repository hygiene

**Frame contract.** `Frame - Program F-MID` on `Phage_Camera` holds only the
camera parameters. Recall it before any final capture.

**Quality ladder.** Four rungs on `Phage_Renderer` hold only output resolution
and volume samples:

| Rung | Renderer GPU vs Live |
|---|---|
| Draft | 0.5x |
| Live (the default) | 1.0x |
| Beauty | 1.7x |
| Hero (capture only) | 4.2x; the whole app drops to about 30 fps |

The ratios were measured with every mover lit. Absolute numbers depend on what
else is cooking, so publish ratios.

**Proof.**

- Every look in all four banks was recalled and captured.
- A 42 s recording runs calm, then a build, then CRAZY.
- The pad lighting, BUILD timing, preset recalls and every desk command were
  checked through the live state.

**Hygiene.**

- The Push 2 Display node's default wrote a PNG every second into the project
  (about 200 MB by the time it was noticed). The project ships
  `record_png_every` 0.
- The display's per-frame journal still grows about 9 KB/s while the app
  runs, so it is gitignored with the preset lock files the open app creates.
- The vendored runtime is marked `-text` in `.gitattributes`.

**Not verified by automation.** Plan drags, Lighting clicks and box selection,
the Desk's click-to-Event hop, and Push 2 hardware. The README lists them for
a hand test.

## Lessons for the next rig

1. Inventory the reference and give each fixture type one job before you
   design any node.
2. Put the anatomy in one header. Capture the mounts from the GPU for every
   offline tool instead of re-implementing the geometry.
3. Fix the program slots per family, with headroom. Counts should gate rows,
   never retarget them.
4. If the truss moves, make each axis a programmer row. Everything written
   for lights then drives steel.
5. Make every node useful before the programmer exists: a reference chase, a
   demo drive.
6. Budget the 8 data inputs per Module at design time, and pack related
   records behind a documented header.
7. Keep compiles fast: one call site per heavy routine, geometry precomputed
   in a one-thread pass, text through a queue.
8. Profile per pass before optimising. Use a light grid for surfaces,
   tile-culled closed-form haze, and marks plus tile bins for every canvas.
   Previews cook even when hidden.
9. Prove every optimisation with a before/after capture diff, and hand any
   visible loss back to the user as a parameter.
10. Guard degenerate maths on the GPU and scan the data ports for NaN.
11. Author looks as geometry and compile them. Judge them on the live render,
    with filmstrips for anything that moves.
12. Treat the energy tiers as a dynamic range, and restart the BUILD ramp on
    recall.
13. Generate the desk, titles and catalog from single sources, and make the
    pads tell the truth.
14. Ship the frame contract and a measured quality ladder. Switch off anything
    that writes files per frame.
15. Report exactly what automation could not prove.
