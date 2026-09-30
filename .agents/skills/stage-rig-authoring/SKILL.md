---
name: stage-rig-authoring
description: Build a concert lighting rig in Sentinel as a playable show - beam movers, strobes, pixel bars and optionally a moving truss, a per-fixture programmer, layered look banks (static, effects, colour, full), energy-tiered effects, a desk panel and a Push 2 surface, rendered live in haze. Use when a user asks for a stage rig, lighting rig, concert/festival/arena stage, light show, fixture programming, "static looks / effects / colour presets", a lighting desk, or a new rig "on the stage rig system".
---

# Stage Rig Authoring

A stage rig is an instrument before it is an image. Someone has to play it, live, from a desk or a
Push 2. So its looks have to layer, its pads have to tell the truth, and the whole graph has to hold
frame rate with hundreds of fixtures in haze.

`projects/stagerig_phage/` (PHAGE) is the reference build. Read these before designing:

- its `README.md`: playing the show, the automation seam, the component map;
- `docs/PROCESS.md`: the making-of, with every decision, trap and optimisation;
- `docs/PROGRAMMING.md`: the programmer, lanes, codes and persistence;
- `docs/LOOKS.md`: how 64 looks are built.

Also read `knowledge/reference-build-method.md` and the `module-authoring`, `module-ui-authoring`
and `mcp-automation` skills.

**What to take and what to design.**

- **Take:** the show system is infrastructure with no creative identity. When the user wants a
  playable rig on the stage-rig system (programmer, banks, desk or Push 2), fork PHAGE's show layer.
  The generic canvas and caption helpers (`_shared/ph_marks.hlsli`, `_shared/ph_textq.hlsli`) may
  be vendored too.
- **Design:** the rig is creative work. Design the anatomy, fixture plan, renderer look, palettes
  and every look fresh for the user's reference. Never copy the phage.

## 1. The fixed contract

1. **One construction model.** One shared header defines the structure and every fixture mount.
   A kinetics or mount node publishes the live mounts, and nothing downstream re-derives a position.
   Offline tools read a capture of those mounts taken from the GPU, never a re-implementation of the
   geometry.
2. **Stable program slots.** Give each fixture family a fixed slot range with headroom. Fixture
   counts switch rows on and off; they never move a fixture to another row. Stored looks then
   survive every rig change.
3. **A packed per-fixture programmer.** Rows x attributes, written in batches and committed as one
   revision, so a half-written look is never visible.
4. **Layered banks with disjoint ownership:**
   - static owns pan, tilt, level and ring;
   - colour owns palettes and routing;
   - effects owns every effect attribute and the strobe clock;
   - full owns everything, plus the render globals.

   Disjoint ownership is what lets banks mix live.
5. **One show surface.** A Script node owns programming and playback behind a `rig_command` state
   seam, with an ack. The desk, the Push 2 and automation all send the same commands.
6. **Pads tell the truth.**
   - A FULL look lights itself plus the parts it was built from.
   - Any later partial recall unlights the FULL pad.
   - The lit set persists across reloads.
7. **Useful before programming.** Every node shows a meaningful result before the programmer
   engages: a reference aim and chase, a reference pixel chase, a demo drive for kinetics.
8. **Proven live.** Every look is recalled and captured on the running rig. Anything that moves is
   judged in filmstrips, not stills.

## 2. Design the rig for the reference

Work this out and write it in the response before creating a node:

- **Inventory the reference.** List every structural and lighting element, then map each to a
  node or a fixture family.
- **Give each fixture type one job.** Three types is a strong constraint. In PHAGE:
  - beam movers draw shapes in haze;
  - linear strobes (a tube plus a colour plate) give impact and colour wash;
  - pixel bars trace the structure.
- **If anything moves, make each axis a programmer row.** Map each row's pan and tilt onto a
  physical axis, with speed and acceleration limits. Lanes, movement FX, chase orders and look banks
  then drive steel exactly as they drive lights. A truss pose becomes a static look, and a gait
  becomes an effect.
- **Build a plan authority** for the construction. Choose relational exploration handles (stance
  presets, symmetric edits) rather than random coordinates. Add alarms for broken states: an
  unreachable foot, or roof clearance at the kinetic maximum.
- **Give it a venue and a crowd.** They give scale, and silhouettes that occlude beams read as depth.
- **Camera.** Use the renderer's internal camera unless the show switches between authored camera
  points from the surface. That show-level orbit switching is the justification for an external
  camera. Save a frame contract either way.

## 3. Graph shape and data budget

PHAGE's graph is one answer, not a template:

```text
Plan -> Kinetics -> Assembly / Venue / Lighting / LED -> Renderer
Program + Show + Clock -> Kinetics / Lighting / LED
Surface <-> Desk (panel events and feedback), Surface -> Push 2 Display
```

- **Budget the data inputs at design time.** A Module takes at most 8 data inputs. List the
  renderer's inputs first, then pack related records into one buffer behind a documented header row.
  PHAGE packs room, emitters, architecture and crowd into one Venue buffer, puts tubes and solids in
  one Structure buffer, and appends strobes to the Optics buffer.
- **Bind each data input once per pass.** Read a second record type through a field-mapping helper.
- **Build one node at a time**, per the workspace manual, and give each node a first proof before
  the next. PHAGE's build order and proofs are in `docs/PROCESS.md`.

## 4. The show layer

- **Vendor the runtime unchanged.** Copy `scripts/vendor/push2os/` exactly, with its
  `push2os-provenance.json` pins, and add a `-text` rule for it in `.gitattributes`. Line-ending
  conversion breaks the pins.
- **Adapt only the rig-specific Surface files.** In PHAGE about 15 carry rig knowledge:
  - the fixture catalog, attributes and groups;
  - `static_rig` (the programmer core);
  - `rig_bridge` (node names and writes into the graph);
  - the look store and `rig_commands`;
  - menus, the selection view and the camera orbit;
  - titles, the desk layout and the entry script.

  Keep the rest.
- **Generate, do not hand-edit:**
  - the fixture catalog, from the mounts capture;
  - the pad titles, from the look definitions;
  - the desk manifest, shader layout and index map, from one control list. Then run
    `tools/module-ui.ps1 generate` for `_ui.generated.hlsli`.
- **Mirror the groups.** Define selection groups identically in Luau (programmer) and HLSL (canvas).
- **Budgets.** Give the Surface a 2 ms tick budget and a 64 MB heap, and measure both.

Script-node traps, each hit in PHAGE:

| Trap | Rule |
|---|---|
| The heap filled while a target node was missing: a failing host call retried every tick | Back off after a failure until the next full refresh. |
| A VM that exhausted its heap cannot reload, relaunch or reset | Recreate the node with its parameters and links. |
| `preset GROUP_ABSENT` on every recall | Save the project to its folder first; preset groups resolve from the project path. |
| push2os bank saves fail | Seed the persistence group's "current" preset. `preset.save` needs an existing preset. |
| `SNAPSHOT_RECORD_MISSING` after adding durable state | Never add push2os `persist` records to a shipped surface. `host.state.register` values reset on reload too. Put durable additions in the entry script's serialize table. |
| A fire-once write (for example the BUILD origin) is sometimes lost | Retry until the write lands. |
| `[push2os] bank save failed: false` in the log | The asynchronous save is still pending. It is harmless. |

## 5. Programming the looks

**Author looks as geometry and compile them.** Write a Python compiler that reads the mounts capture
and aims with exactly the inverse the GPU uses. Round-trip direction to pan/tilt and back as a
self-check. Then:

- A **shape** is a function from a fixture to a direction (or target point), a level and a ring, or
  `None` to leave that fixture untouched.
- A **pose** writes only the axis rows. So shapes and poses layer.
- Sign any "rise" per mount, so hanging and upright heads rise together.
- Have the compiler report how many fixtures each shape lights and its tilt range. A bad aim then
  shows up before any capture.

**Effects are roles x lanes x FX x chase orders**, per fixture role (movers, strobes, bars, each
kinetic axis group).

Treat the effects bank as a **dynamic range** of energy tiers, each with its own rules:

| Tier | Clock | Motion | Strobes |
|---|---|---|---|
| Calm | A long phrase lane | Slow drift | Glow or off |
| Groove | Kick, snare and hat lanes | Contained sweeps | Accents on the kick or snare |
| Build | A ramp lane that restarts on recall | Amplitude and travel grow; pulse rate doubles each quarter | Strobes ride the ramp |
| Crazy | Mostly kick | Jumps and fast spin | Strobe, sparkle and blinder |

The build ramp must restart on the beat after its look is recalled, and hold at the top until the
next recall. A build fired 16 beats before the drop then peaks on the drop.

**A fixture with no lane is fully on.** Default fresh strobe rows to a colour glow, not a steady
white tube. Give every element of a look a timing story.

**Colour** is a palette library (A, B and C colours) times routing functions: mono, zones,
height, sides, alternating.

**A full look** is a shape, a pose, an effect and a colour, plus a few global overrides such as
haze or bloom. Store the parts with the preset so the pads can light them.

## 6. Tuning loop

Build a review tool that drives the live rig through the same seam as the desk:

- **Recall** a look.
- **Sheet:** a labelled contact sheet of a whole bank. Capture build looks deeper into their ramp.
- **Strip:** filmstrips at fixed times after each recall, one row per look.
- **Steady:** neutral effect rows pasted without storing, for repeatable A/B. A paused clock
  darkens every lane-driven fixture, so it cannot be used for comparisons.

Judge effects over one fixed base (shape, pose and colour), so only the effect changes. The fixes
PHAGE needed are the ones to look for first:

- Beams too faint: sweep beam gain and falloff on the render. More haze only adds murk.
- Grey-white whiteouts: strobe plates with no lane stay fully on. Put them on a lane, and lower the
  strobe haze scatter.
- Beams gone half of every beat: the hat lane rests half of each beat. Use the kick lane for beams.
- A warm murk from blinders: put them on the snare.

## 7. Performance

Profile per node and per pass with `sentinel_graph action=profile`, sorted by `gpu_ms`, before
changing anything. Node previews cook every frame even when their panel is hidden, so each must be
cheap by construction. GPU timestamps move with the clock, and a laptop driver lowers the clock
when the frame cap leaves headroom, so measure every before/after side by side and publish ratios.
PHAGE cut its GPU time from 41 ms to 5.8 ms per frame with 196 fixtures, on a laptop GPU:

- **Surfaces: a world-space light grid.** Each cell lists up to 8 lights and the near emitters, and
  carries an L1 probe for everything else. A window fades near emitters into the probe so the
  handover is invisible. Overflowing cells fall back to the full loop.
- **Haze: tile-culled, closed-form.** Each 8 x 8 tile culls lights against its view cone into
  groupshared memory, and wide glows use closed-form integrals. If culling drops a long-range term,
  give it back as a parameter (PHAGE's `glow_range`), not as a silent loss.
- **Canvases: marks plus tile bins.** A small pass writes screen-space primitives in draw order. A
  bins pass sorts them into tiles with a survivor bitmask that preserves order. The pixel shader
  draws only its own tile. Captions go through one queue.
- **Compile time: FXC inlines every call.** Give each heavy routine one call site, precompute
  geometry in a one-thread pass, and mark loops `[loop]`.
- **Prove parity.** Capture before and after every optimisation and diff them.

## 8. Presets, proof and hygiene

- **Frame contract.** A camera-only node preset for the composed view.
- **Quality ladder.** Resolution and volume samples only, Draft/Live/Beauty/Hero. Default to Live,
  mark Hero capture-only, and publish measured ratios.
- **Push 2 Display.** Set `record_png_every` to 0. Its default writes a PNG every second into the
  project. Gitignore `**/.sentinel/display-records/` and `**/presets/.sentinel-*.lock`.
- **Shipping in this repository.**
  - Register the project in `tools/official-examples.config.psd1`, which drives the validator, the
    audit and the workspace manifest.
  - Add a review record under `.release/reviews/`.
  - Run `tools/validate-official-examples.ps1 -Projects <name>` and
    `tools/module-ui.ps1 validate` on the desk.
- **Report what automation cannot prove.** Injected input does not reach Module viewport events, so
  canvas drags, canvas clicks, the desk's click hop and Push 2 hardware need a hand test.

## 9. Module traps

| Symptom | Rule |
|---|---|
| Data input slot out of range | At most 8 data inputs: pack them. |
| X3003 redefinition of `_DataType_N` | Bind each data input once per pass. |
| X1507 cannot open include | Includes resolve from the including file: `../_shared/x.hlsli`. |
| X3504 out-of-bounds index in a literal loop | Ternaries evaluate both sides: clamp the index first. |
| X3020 ternary type mismatch | No ternaries on structs. |
| X3005 identifier is a variable | A parameter shadows an intrinsic (`length`); rename it. |
| A canvas forgets its edits | `state_buffers` is top level in the manifest, not under `viewport`. |
| The renderer goes dark after a scripted manifest edit | The edit dropped an `output:` line. Diff every scripted manifest change. |
| Black 8 x 8 tiles | NaN in a data port: `atan2(0, 0)` or `pow` of a negative base. Guard it and scan every port. |
| A node shows the wrong data | `_DataN_Count` is numbered by manifest data-input order, not the pass slot. |
