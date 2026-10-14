# Example Map

The projects in the table below are the example collection shipped with this
build, and the only projects in a workspace that are references for technique
and quality. Every install replaces this file and refreshes these projects, so
the table is always the current collection. Anything else under `projects/` is
not a reference unless the user asks you to work from it: an example retired
from an earlier build (see *Retired examples* at the end), a project made with
an older version of Sentinel or an earlier model, or the user's own work.

Use this map to choose a teaching reference, not a ready-made solution. Read the
selected project's README, inspect its saved graph, and reimplement the relevant
architecture for the current problem. Project-specific Modules are copied only
for an explicit fork or remix. See `example-authoring.md`.

The collection is the floor, not the ceiling: match its standards, then push past
them wherever the work calls for it.

## Collection at a glance

| Project | Saved graphs | Live/AI dependencies | Core route | Reviewed output | Study it for |
| --- | ---: | --- | --- | --- | --- |
| `breathing_room` | 1 | none | shell/finish/furnishing/light/trip/rug authorities (64-byte records, one role range each) → SDF ray-march renderer (HDR + scene) → lens | `BR_Lens` | a realistic room whose every editor is a plan authority over persistent records, signature-driven regeneration that keeps hand edits, Lipschitz-safe SDF warps, and a replication-trip lens |
| `camera_reference` | 1 | none | camera-capable grid renderer | `Native_Camera_Reference` | the native internal camera contract |
| `cloth_lab` | 1 | Audio In | loopback audio → band analysis → XPBD cloth | `cloth_engine` | audio data ports, simulation, grabbing, tearing |
| `formicary` | 1 | Audio In (optional) | plan authority/editor (stations) → colony (pheromone field, gait, bucket grid) → macro renderer → exploded scope → macro-lens post; Audio In → band analysis → walk speed | `FM_Post` | a shared field that lives with the agents that write and read it, a loop closed through control outputs and expressions, editing on the program image |
| `interaction_lab` | 1 | none (sound through MIDI Out) | fourteen station Scene Groups on one UI foundation; Scripts, GPU event ports, MIDI Out | station previews; `Program` | host controls, events and durable state, 3D picking, editors, patching, multi-view sequencers |
| `kuka_cell` | 1 | none | cell plan authority/editor → ball/rally authority → four-channel choreographer + FK → SDF arm renderer | `KA_Robot` Program | a lattice randomizer that keeps an array an array, choreography whose phase is derived from floor position, a shared-object authority a crowd of agents responds to, per-tile instance culling |
| `laser_mapping_lab` | 1 | none (a laser optional) | looks (Laser Look bundles) → Mux → Bundle Split → Mapping_Editor calibration → Adaptive_Mapping → Laser Out (simulate) → Sent Stream → simulated galvo laser → previs | `Laser_Previs` | mapping a laser to a surface, zoning masks, laser/projector sync, Scan Signal content and joint flags, previewing what a laser really draws |
| `phage_stage` | 1 | none (Push 2 optional) | plan authority → kinetic truss → assembly/venue; Fixture Rig (MVR + GDTFs) → console (fixture table, looks, DMX through the GDTFs) → renderer that decodes the DMX in haze, played by a Script-node surface (desk panel, Push 2, layered per-fixture programmer, layered look banks) | `Phage_Renderer` | a complete playable show: a moving truss programmed as fixtures, 561 GDTF fixtures from an MVR whose render is its DMX, looks compiled from geometry, an energy-tier effects ladder, and a documented 41 → 5.8 ms GPU optimisation |
| `simple_stage` | 1 | none (Push 2 optional) | static stage authority → Fixture Rig (MVR + GDTFs) → console (fixture table, looks, DMX through the GDTFs) → renderer that decodes the DMX in haze, played by PHAGE's show system (desk panel, Push 2, layered programmer, layered look banks) | `SS_Renderer` | a club-scale rig sized like a real club: two rows of hung beams, a 12-run pixel wall and strobes in 7 universes, symmetric looks with held formations, and a mirrored-content LED wall |
| `soft_vitrine` | 1 | none | plan authority → stage/growth → volumes + strokes + plates → composite → post | `VT_Post` | hybrid 2D/3D record contracts, coverage lanes, seeded arrangement randomization |
| `spectral_bench` | 1 | none | bench authority/editor → spectral path trace → tile-binned field → lens print | `LT_Lens` | a scaffold tailored to the subject's real axis (wavelength), failure modes drawn in the diagram, one thread per ray, wavelength and branch |
| `streamdiff_canvas` | 1 | StreamDiff, Depth, Background Removal | paint/pattern fields → depth controls → StreamDiff → cutout | `Collage_Cutout` | direct manipulation of generative conditioning |
| `streamdiff_workflows` | 6 | StreamDiff; Depth and Background Removal in study 05 | one focused routing pattern per graph | named StreamDiff/Mux/composite preview | small, isolated StreamDiff techniques |

## Dependency and portability notes

- Every active Module is under its owning `projects/<project>/modules/` tree.
- No project links to a root Module catalog or another project's files.
- StreamDiff graphs require a compatible StreamDiff engine pack.
- Depth Estimation requires the compatible auxiliary depth pack.
- Background Removal requires its matting engine.
- Features, Audio In, and authored Modules need no engine pack. MediaPipe needs
  `auxiliary-mediapipe-face` and/or `auxiliary-mediapipe-hands`. Availability
  still comes from the live `list_types` and `engine_status` responses.
- `projects/streamdiff_workflows/assets/dancer_vert.mp4` is the only bundled
  runtime media asset taken from outside; `projects/formicary/audio/kick_120bpm.wav`
  is generated.
- PHAGE and SIMPLE STAGE carry their own GDTF fixture types (Sentinel's, written by
  their tools, not manufacturer files) and the MVR their Fixture Rig imports.
- The IBM Plex type atlas in each project's `modules/_shared/type/` folder carries
  `IBM_PLEX_OFL.txt` beside it.

## Project routes

### Breathing Room

A realistic SDF parlour that trips. `BR_Shell` owns the room and its openings, `BR_Finish` 24
material slots, `BR_Furnish` every piece and its host, `BR_Light` the sun (from time, date,
latitude and the building's bearing), lamps and fire, `BR_Trip` where and how the hallucination
runs, and `BR_Rug` what is woven into the rug. Each publishes 64-byte records in its own role
range (`projects/breathing_room/modules/_shared/br_records.hlsli`); `BR_Render` ray-marches them with the internal camera
and hands HDR plus a Scene buffer to `BR_Lens`, which owns everything between radiance and the
picture. A Scene Group ("Breathing Room") exposes eight controls, Dose first.

Study it for **plan authorities over persistent records**: parameters generate a complete room,
canvas edits are stored as deltas on top, and regeneration is signature-driven and versioned
(`PLAN_VERSION`), so a hand-placed lamp stays on its table when the room is resized. Also for
**per-object SDF warps divided by their Lipschitz bound** so the march never steps through a
breathing surface, **editors drawn as the draughtsman would** (an unfolded room, a sun-path
chart, the rug laid flat), and a **narrow quality ladder** measured as ratios.

Remix seam: take the records contract, the delta-over-generation editors and the warp
discipline. Design your own room, materials and effect; the trip's look is this project's own.

### Camera Reference

`Native_Camera_Reference` is a single camera-capable Module with a black field,
thin antialiased ground grid, optional colored origin axes, and color/depth
outputs. It owns Sentinel's internal Fly/Orbit camera and keeps `camera_ref`
empty.

Remix seam: use the camera contract, not the grid's visual design.

### Cloth Lab

`cloth_audio` captures the current default loopback device. Its Spectrum data
feeds `cloth_bands`, which publishes musical envelopes and counters to
`cloth_engine`. The engine owns XPBD simulation, grabbing, cutting, rendering,
and the internal camera.

Remix seam: keep Audio In's chronological ring discipline and design a new
analysis/visual mapping for the user's material.

### Formicary

`FM_Plan` is the plan authority: arena, nest, food, obstacles, the trail network, and the
stations (emitters, attractors, repellers and sinks) placed on its plan. `FM_Colony` owns the
ants: task state, stigmergic steering, a tripod gait with planted feet, the pheromone field, a
bucket grid and contact shadows. `FM_Render` draws the procedural ants and the studio sweep
through the internal camera, `FM_Scope` is an exploded instrument overlay that draws nothing of
its own, and `FM_Post` is the macro lens and print. `FM_Stage` is the program image made
editable: place and drive stations on the ants you are looking at. `FM_Audio` and `FM_Bands`
drive walk speed from the kick through an expression.

Study it for **a shared field that belongs to the agents that write and read it**: deposit and
sense are a closed loop, so the pheromone lives inside the colony rather than across a graph
edge. Also for **closing the colony-to-plan loop through control outputs and expressions**
rather than a link, and for **editing on the program image itself**. Its README records why a
sink placed on the food silently deletes the subject, and why an audio drive needs a presence
gate.

Remix seam: take the station contract, the field-inside-the-colony decision and the
stage-as-editor pattern. Do not take the ants or the white sweep.

### Interaction Lab

Fourteen numbered stations, each its own Scene Group, built on one shared UI
foundation (`modules/_shared/ui/`: draw list, SDF type, widgets, panes, events).
Basic: `Kit` (host-owned controls and the XY round trip), `Touch` (ordered
events into a `state_buffer`), `Handles` (drag and turn over parameters),
`Still_Life` (host-owned selection and picking through the internal camera),
`Pulse` (GPU impact events → `Pulse_Bus` → `MIDI_Merge` → `Synth`, echoed to
`Resonance`), `Atoms` → `Scope` (a Script as a control source, read through
`ref()`), `Desk` → `Cue_Brain` → `Stage` (a panel driving a cue stack).
Instruments: `Curve_Desk`, `Path_Desk` → `Plotter`, `Ramp_Desk` → `Relief`,
`Patch_Bay` → `Bloom`. Sequencers with several interactive views in one canvas:
`Timeline` → `Sting`, `Pattern` → `Pattern_Bus` → the same MIDI Out, and
`Score` → `Program`, whose internal camera the Score flies by expression.

Remix seam: copy interaction architecture only at the level of ideas—manifest
hit contracts, durable state, selection ownership, event ports, and responsive
layout.

### Robot Cell

`KA_Cell` is the plan authority for a floor of six-axis industrial arms: a plan
strip over an elevation strip sharing one metres-per-pixel scale, with an
inspector column, click-select and drag-move, and the Point At target held as a
record so it is dragged on the floor rather than typed. `KA_Pose` reads those
records and runs four independent pattern channels through joint limits and
forward kinematics. `KA_Robot` marches the arms with the native internal camera
and publishes a clean Program plus an annotated Scope from one solve.

Study it for three things it does differently from the other plan-authority
projects. Its randomizer perturbs **lattice parameters** rather than record
coordinates, because an array's identity is its regularity and a free draw per
element reads as debris. Its choreography derives each element's phase from
**where that element actually stands**, so moving one arm changes when it moves
as well as where it is, and the channel split is computed from the layout rather
than stored as a routing table. Its renderer makes forty-eight instances
affordable with **per-tile cooperative culling**: each thread group tests every
instance against its own view cone and compacts the survivors into a groupshared
list.

`KA_Rally` is the fourth node and the reason to read this project even if robots
are irrelevant to you. It keeps a beach ball up between the arms, and it exists
as its own authority because a ball is **one shared object with its own state**
that a crowd of agents responds to — which is a different shape of problem from
a per-agent function of phase, and cannot be expressed as another entry in a
pattern enum. Participation is a channel mode decided in that one place, so half
a cell can play while the other half keeps running its patterns.

Read the README for two failure catalogues: the phantom-bound shading trap,
which will recur in any instanced SDF scene, and the four bugs between "245
serves and zero completed hits" and a 78-touch rally — the last of which was
found only by measuring, because the obvious suspect turned out to change
nothing.

Remix seam: the relational-randomizer question ("what relationships make this the
thing it is?"), the derive-phase-from-placement contract, and the shared-object
authority — not the arm geometry.

### Laser Mapping Lab

Three looks (`Alignment_Grid`, `Laser_Test_Shapes`, and the traced `Trace_Canvas` → `Trace` →
`Trace_Look`) each publish a **Laser Look** bundle (projector video plus `laser.a.scan`) from their
own Scene Group. `Look_Select`, a Groups-mode Mux, picks one; `Laser_Split` hands its scan to the
mapper and its video to the projector. `Mapping_Editor` is the editable calibration: a 5 × 5
handle lattice, corner-anchored Scanner Correction (Bow, Spacing, Centre) and zoning masks, all
compiled into one Calibration buffer. `Adaptive_Mapping` warps the scan through it, subdividing
only where lines bend and cutting at masks and the field edge. `Laser_Sim` is a real Laser Out on
the simulate protocol; its **Sent Stream** feeds `Laser_Fixture`, a raw scanner with galvo
distortion and lag, and `Laser_Previs` renders the room, the beams in haze and the mapped video
projector.

Study it for the **on-site mapping workflow** (corners, Bow, Spacing until the offsets match,
Centre, then handles), a **calibration that is editable, not solved**, **zoning that fails
closed**, the **Sync Sweep** that reads laser-to-projector latency in milliseconds, **Scan Signal
joint flags** that let one scanner profile draw both crisp corners and seamless loops, and a
preview that simulates **what the DAC was told**, not the idealised path. `knowledge/laser-mapping.md`
is the companion reference.

Remix seam: author new looks against the Laser Look contract (a Module with `bundle_outputs`, or
Laser Trace plus Bundle Pack), and reuse the mapping chain as infrastructure. Replace the room in
`site.hlsli` and the fixture pose with your own venue rather than copying the warehouse.

### Stage Rig: PHAGE

`Phage_Plan` is the construction authority: stance presets, symmetric leg edits, and a plan
over a radial leg section that turns a leg red when it cannot reach its foot. `Phage_Kinetics`
moves the truss on eight speed- and acceleration-limited axes and publishes the live fixture
mounts, so every fixture rides the truss. `Phage_Assembly` builds the truss tubes and
`Phage_Venue` packs the arena and crowd into one buffer. `Phage_Rig`, a Fixture Rig node, imports
the rig from `projects/phage_stage/assets/phage_rig.mvr`: 561 fixtures of PHAGE's own three GDTF types in 57
universes. `Phage_Lighting`, the console, builds the show's fixture table from it every frame,
plays the looks and encodes every fixture's DMX through its GDTF; `Phage_Renderer` decodes that
DMX and draws it in haze, so the picture is what a real rig would receive. The `Phage_Surface`
Script node writes `Phage_Program` (a row per layer of every fixture) and `Phage_Show` (lanes,
palettes, strobe clock); `Phage_Desk` and a Push 2 play it.

Study it for a **moving truss programmed as fixtures**: the eight axes are programmer rows, so
lanes, movement FX and look banks drive steel exactly as they drive lights. Also for **a rig
from MVR and GDTF whose render is its DMX**, **looks authored as geometry** and compiled per
fixture against mounts captured from the live data port, **fixtures programmed as layers**
(a beam's movement, beam and halo apart, a bank per layer), the **energy-tier effects ladder**
with a BUILD lane that restarts on recall, and the optimisation recorded in `docs/PROCESS.md`:
a world-space light grid, tile-culled haze with closed-form glows, and marks-plus-tile-bins
canvases.

Remix seam: take the show system (surface, packed programmer, layered banks, `rig_command`
seam), the look-compiler method and the optimisation patterns, through the
`stage-rig-authoring` skill. Design a new anatomy, fixture plan, renderer look and look
vocabulary for your own reference; do not copy the phage, its palettes or its looks.

### Stage Rig: SIMPLE STAGE

PHAGE's show system on a stage sized like a real club. `SS_Stage` is a static construction
authority: three flown truss lines of stock F34 parts, solved and audited by
`projects/simple_stage/tools/ss_stage.py`, which also writes the MVR. `SS_Rig` imports it: 76 fixtures in 7
universes (two rows of eight hung Halo Beams, twelve Linear Strobes, a wall of twelve pixel
runs). `SS_Lighting` is the console and `SS_Renderer` decodes its DMX, as in PHAGE;
`SS_Venue` is a club with a crowd. `SS_Surface`, `SS_Desk` and a Push 2 play 64 looks, 15
sequences and a programmer that stores to any pad.

Study it for **a rig the size of a real club** (what a venue owner would actually patch), for
**looks designed as rules**: every shape, chase, colour routing and move is its own mirror
image, checked field by field when `projects/simple_stage/tools/ss_looks.py` compiles them, and most effects hold
the heads still while formation looks glide to a new symmetric position on a downbeat. Also
for **a pixel wall whose content is symmetric by construction** (chevrons, a mirrored
equaliser, rain seeded per mirrored pair of runs) and for **review tooling** that recalls
looks through the desk's own command seam and writes contact sheets and filmstrips
(`projects/simple_stage/tools/ss_review.py`).

Remix seam: take the show system and the look compiler as PHAGE's seam describes. Design your
own stage, plot, looks and palettes; the GDTF types are Sentinel's own and may be reused.

### Soft Vitrine

`VT_Plan` is the plan authority: it owns stage space and the horizon, generates the
whole composition procedurally, and holds click/drag/key overrides in one 64-record
`Plan` buffer where `role` separates flat plates from stroke anchors, mass anchors and
a global stage record. `VT_Stage` draws the cyclorama and reflective floor.
`VT_Growth` expands the anchors into a single `Limbs` buffer — world-space capsule
chains for the sculpted masses, stage-space polylines for the drawn marks — and
publishes a bounding sphere per group so the renderer can cull. `VT_Volumes`
ray-marches the masses across clay/chrome/frost/gloss and owns the internal camera,
`VT_Strokes` draws the marks as lit tubes, and `VT_Plates` renders the flat graphic
family split into back and front layers. `VT_Composite` stacks the four layers and
derives the drop shadow and floor reflection from total coverage; `VT_Post` finishes.

Remix seam: take the hybrid record contract — one buffer, `role` discriminated, with
2D and 3D families living side by side — and the `Variation`/`Seed` randomizer whose
stratified placement and preserved size hierarchy keep a random draw composed. Do not
take the electric-blue toy-plastic palette.

### Spectral Bench

`LT_Bench` is the bench authority and editor: every source and element (prisms, mirrors, slabs,
lenses, beam splitters, screens, blockers), where it is, what it is and what glass, in one
77-record buffer. `LT_Trace` is the physics alone (Cauchy dispersion, Fresnel, total internal
reflection), one thread per ray, wavelength and branch, publishing up to 32,256 path segments.
`LT_Field` tile-bins the paths and draws the room, the glass and the light in HDR above 1.0.
`LT_Lens` is the camera: halation, anamorphic streak, aberration, ACES and grain.

Study it for **a scaffold tailored to the axis the subject is organised along**: a bench plan
over a spectral rail, with an event ladder (wavelength by interaction) and a deviation profile
whose width is the dispersion. Also for **failure modes drawn in the diagram** (an unlit
element, a wavelength lost to total internal reflection and a ray that runs out of interaction
budget all read red), and for the rule that the rail reads one beam, because an average across
sources would print a number no beam produces.

Remix seam: take the plan-over-reading scaffold, the drawn failure modes and the
physics/picture split. Do not take the prism composition.

### StreamDiff Canvas

`Paint_Canvas` and `Pattern_Canvas` capture persistent authored input.
`Radial_Gradient` and three instances of `Pattern_Depth_SDF` shape spatial depth
fields. `depthestimation_0` supplies image depth, `Generation_Controller`
coordinates generation, `Collage_Diffusion` renders the photographic collage,
and `Collage_Cutout` supplies the reviewed isolated result.

Remix seam: invent new direct-manipulation fields and prompt semantics while
preserving the separation between editable control images and generation.

### StreamDiff Workflows

The folder contains six independent graphs:

1. `01_2d_feedback_zoom.sentinel`: one StreamDiff node using 2D feedback.
2. `02_depth_parallax_zoom.sentinel`: one StreamDiff node using depth-parallax
   motion.
3. `03_backrooms_flythrough.sentinel`: one StreamDiff flythrough setup.
4. `04_direct_variant_mux.sentinel`: three StreamDiff variants selected by
   `Direct Variant Mux`, with `Variant Switcher UI` demonstrating automatic
   selection.
5. `05_video_depth_control.sentinel`: bundled dancer video → Depth Estimation →
   `Depth Threshold` → StreamDiff control; the original-video matte masks the
   generated dancer before `Generated Over Original` composites it.
6. `06_procedural_warp_map.sentinel`: `Procedural Flow Map` drives a StreamDiff
   warp input.

Open one at a time to avoid unnecessary engine-memory pressure.

## Retired examples

Earlier builds shipped these. In the default workspace an install retires them:
an unchanged copy is removed, and a changed one moves to
`.sentinel/workspace-backups/upgrade-to-<version>/projects/`. A custom workspace,
or one that predates that tracking, may still hold them. They are not references: they were built to older standards,
or a current example supersedes them.

| Project | Last shipped | Study instead |
| --- | --- | --- |
| `living_room_sdf` | 0.6.3 | `breathing_room`; the blueprints and the Modules they feed are the template in `tools/templates/blueprints/living_room` |
| `autopsia`, `axon_press`, `face_collage`, `industrial_lattice`, `koi_tank`, `matik_plate`, `reactor_shaft`, `scientific_organism`, `strata`, `sunward_corridor`, `touchdesigner_new_project`, `vitreous_cross` | 0.6.2 | the collection above |
