# formicary

A foraging colony of fire ants on a white studio sweep, transcribed from a macro photograph and
then pushed well past it: a stigmergic colony that lays and follows its own pheromone, six-leg
workers whose feet are genuinely planted on the ground, soft contact shadows, and a macro lens
with a depth of field a few millimetres deep.

**Up to 128 ants at 1.5 mm**, over a 260 x 180 mm arena, driven by placed **stations**:
emitters, attractors, repellers and sinks that you lay out either on the draughtsman's plan or
directly on the program image.

The Program output is `FM_Post`; `FM_Stage` is the same image with the editor over it. Open
`formicary.sentinel`.

The instrument is **off** by default (`FM_Scope / Overlay Mix = 0`) because the reference is a
clean photograph. Raise it to see the machinery, and raise `FM_Scope / Explode` to lift the
lanes of information off the ground plane.

---

## Component map

| Node | Single responsibility |
| --- | --- |
| `FM_Plan` | Plan authority: arena, nest, food, obstacles, the trail network, and the stations. |
| `FM_Colony` | The ants: task state, stigmergic steering, the tripod gait, the pheromone field, the bucket grid and the contact shadows. |
| `FM_Render` | Optics. Procedural ant geometry and the sweep. Owns the internal camera. |
| `FM_Scope` | Exploded instrument overlay; draws nothing of its own. |
| `FM_Post` | The macro lens and the print: bokeh depth of field, bloom, filmic grade. |
| `FM_Stage` | The program image, made editable. Place and drive stations on the ants you are looking at. |

```
FM_Plan ──(Plan)──┬──────────────┬────────────────┬──────────────┐
                  ↓              ↓                ↓              ↓
              FM_Colony ──(Ants, Feet, Field)──► FM_Render ──► FM_Scope ──► FM_Post
                  │                                  │            ▲            ▲
                  └──── control outputs ─────────────┘            │            │
                        (traffic, laden, speed, slip, lane0..3)   └── Depth ───┘
                        driven onto FM_Plan's flow strip
                        by EXPRESSION, not by a link
```

The loop from `FM_Colony` back to `FM_Plan` runs through **control outputs and expressions**, so
there is no cycle in the graph — only a one-cook delay, which for a readout is nothing.
`FM_Stage`'s edits travel back the same way, for the same reason.

## Idle execution

Formicary intentionally runs continuously. `FM_Colony` advances the simulation, `FM_Render`
consumes the changing colony buffers, `FM_Scope` maintains the live trail and instrument state,
and `FM_Post` animates film grain. `FM_Plan` receives live colony readouts and viewport edits,
`FM_Stage` is the interactive program surface, and `FM_Bands` consumes live audio data. Each node
therefore retains the default `EveryFrame` policy.

---

## Stations: what you place, and what it does

A station is one record in the plan buffer with a `kind` discriminator — one role rather than
four, because to the user they are one thing: a point you put down, drag, retune and switch
between behaviours. Four parallel ranges would have needed four sets of pick code, and the first
thing anyone would ask for is to turn an attractor into a repeller without moving it.

| Kind | Modes | What it does |
| --- | --- | --- |
| **Emitter** | Drip · Burst · Ring | Releases ants. Drip at a rate, Burst on `T`, Ring around the rim facing outward. Owns an aim and a release cone; `budget` caps how many it may have out at once. |
| **Attractor** | Steady · Pulse | Pulls ants toward it inside its reach. Pulse beats to zero and back, so a column surges rather than breathes. |
| **Repeller** | Steady · Pulse | The same thing with the sign reversed — which is why it is drawn as the same glyph with the arrows reversed rather than as an invented second concept. |
| **Sink** | Recycle · Consume | Ants that walk in dissolve. Recycle returns the slot to the pool for an emitter to release again; Consume spends it until the colony is reseeded. |

**Verbs, on either surface.** `A` place · click select · drag move · **`D` delete** · `M` kind ·
`E` mode · `T` fire · `F`/`V` stronger/weaker · `G`/`H` wider/tighter · `X` mute · `N` re-roll ·
`C` clear.

**`D` deletes, `X` mutes, and the difference matters.** `X` stops a station acting but keeps its
kind, reach, strength and position, so you can A/B what it was doing. `D` wipes the record and
returns the slot to the pile for the next `A`. There was only `X` at first, and since a muted
station is not drawn it looked exactly like a delete that had left the slot used up — sixteen
presses of `A` later there is no way to clear the board.

**Where the population comes from** is `FM_Colony / Population`. *Steady Trail* is the shipped
behaviour and the reference photograph's state — every ant placed along the routes mid-round-trip.
*Dormant Pool* starts with nothing on the plate and hands the whole population to the emitters,
which is the mode the station system exists for.

**A sink does not belong on the food, and that was a real mistake.** Placed at a cache it
swallows every outbound ant before it can load: measured laden fraction 0.00, with the round
trip — the entire subject — silently gone. Sinks are generated *past* the cache on the same ray,
where they drain the overflow instead of intercepting the traffic.

**Drain is a speed, not a quota.** A sink's strength sets how fast an ant inside it dissolves,
not how many per second it is allowed. The throughput limit falls out of that on its own and is
better than a quota would have been: a slow sink visibly backs up into a queue at its mouth
instead of teleporting a fixed number of arrivals out of existence.

---

## Audio: the colony walks to the beat

```
FM_Audio (Audio In) --Spectrum--> FM_Bands --kick--> [expression] --> FM_Colony / walk_speed
```

`FM_Bands` is **cloth_lab's `cloth_bands`, vendored into this project unmodified apart from its
name**, together with its dependency closure — `_shared/au_hud/au_text.hlsli` and
`_shared/fonts/` including the Scientifica licence. The workspace rule is that a show bundles its
own copy of the analyser rather than linking to Cloth Lab at runtime. It was deliberately *not*
reimplemented: per-lane dB thresholds against a rolling baseline, refractory gating and the ring
catch-up contract against the audio node's generation counter are subtle, and rewriting all of it
to drive one parameter is a way to reintroduce bugs cloth_lab has already fixed.

Tune thresholds by dragging on **FM_Bands' own Canvas panel**, not by guessing numbers.

### The drive

```
walk_speed = speed_base * (1 + speed_audio * kick * min(1, level * 300))
```

Two knobs on `FM_Colony`, so the expression never has to be edited: **Base Speed** is the pace
with no music (16 mm/s — silence is a working colony, not a stopped one), **Beat Speed** is how
much a full hit adds as a multiple of the base (1.10, so a kick nearly doubles the pace). The
*shape* of the surge is FM_Bands' `Output Decay`, raised from 120 ms to 420 ms because a
percussive spike suits a flash and a swell suits locomotion.

**`min(1, level * 300)` is a presence gate and it is not optional.** The kick envelope is driven
by audio hop timestamps, not wall time, so when the source stops the envelope does not decay — it
**freezes at whatever it last was**. Measured: with playback ended, `kick` sat at 0.340 forever
while `kick_count` stayed at 64, which without the gate leaves the colony sprinting at 22 mm/s in
silence with no way to tell why. The audio node's own `level` does drop to 0, so it is the honest
signal for "is anything playing".

### Verified

Driven from `audio/kick_120bpm.wav`, a generated 8-second 120 BPM kick pattern kept in the
project so the chain stays re-testable (File mode, then hold `restart_file`; it does not loop):

| | measured |
| --- | --- |
| hits detected | 16 per pass — exactly 8 s at 120 BPM |
| kick band level | −27.8 dB, peak flux 49.5 dB against an 8 dB threshold |
| `kick` = 0.023 | `walk_speed` = 16.404396 = 16 × (1 + 1.1 × 0.023) |
| `kick` = 0.340 | `walk_speed` = 21.988419 = 16 × (1 + 1.1 × 0.340) |
| silence, gated | `walk_speed` = 16.000000 exactly |

The node ships on **Device / Default loopback**, so anything playing on the machine drives it.

**What is not verified:** the colony was never watched moving to real music end to end — the test
clip is 8 seconds and does not loop, and MCP round trips are slower than the clip, so every
sample is a spot reading rather than a continuous trace. The arithmetic above is exact at both
ends and the gate is exact at silence, but *how it looks* is still unjudged. The snare and hat
lanes are wired and publishing and nothing is driven from them yet.

---

## The master view

`FM_Stage / View = Plan` is the one picture that has both halves of the problem in it: the
arrangement AND the traffic, in the same projection, editable. Straight down on the whole arena,
with the grid, the routes, the obstacles, the nest and food, every station's reach — and the live
colony drawn as oriented ticks on top.

**It has to live here, and that is a graph constraint rather than a preference.** FM_Plan owns
the arrangement but sits UPSTREAM of the ants and cannot read them without making the graph a
cycle. FM_Colony can see the ants but does not own the arrangement and has nothing to edit. This
node is downstream of both, which makes it the only place the diagram and the traffic can be the
same image — and the only place you can drag a station while watching what the drag does to the
column.

`FM_Stage` is a plain 1280x720 node, **not** a Canvas panel. Right-click it in the graph and set
it as the viewport target like anything else. It was `mode: canvas` with `follow_panel`, which
commandeered its dock and made the one node you actually want full-screen the hardest one to put
there.

**All three top-down views now share one projection.** The page orientation travels in the ARENA
RECORD, written by the plan authority, rather than as a parameter each node is trusted to copy —
which is how FM_Colony's live view ended up a mirror image of FM_Plan's diagram after the plan
was corrected and the colony was not.

### The ant layer is baked, not drawn

The plan view samples the colony from the **alpha of FM_Colony's Field output**, where the ants
are rendered as oriented ticks in arena space using the bucket grid.

Drawing them here instead — loop the population, draw each tick — is 1024 record loads for every
pixel of a 1280x720 frame, or **943 million a frame**. That is the identical number the contact
shadows cost before they moved, and it is the third time this project has met the same lesson: a
per-pixel loop over a population is never the answer, the grid exists so that it never has to be.

It rides in the alpha of an output that already exists rather than in a new one, because adding
an output renumbers this node's data pins and silently re-resolves downstream links by index.

---

## The two editing surfaces

`FM_Plan` is the draughtsman's drawing: exact, on a millimetre ruler, with route cost and the
blocked-route alarm. It is the right surface for laying an arrangement out and the wrong one for
reacting to what the colony is doing, because the thing you are reacting to is in a different
picture.

`FM_Stage` is the other half: the finished program image, fitted aspect-correct into its panel,
with the stations drawn **on the ground** where the ants feel them and a click that places one
exactly where you are looking.

It does that **without owning a camera**, which is the part worth keeping. `FM_Render` publishes
a `Ground` lane — the world point every pixel lands on, built from the same `_InvViewProjMatrix`
the frame was drawn with. So `FM_Stage` needs no matrix, no synchronised viewpoint and no second
camera-capable node; it samples a texture, and flying the camera takes the clicks with it.

The same lane removes the other half of the problem. Drawing a marker would normally mean
projecting world to screen; instead every pixel asks *which ground point am I, and is it inside a
station's reach*. A reach therefore draws as a true perspective ellipse lying on the sweep, not
as a flat circle pasted over a receding plane.

Its edits reach `FM_Plan` — which is upstream of everything — through five expressions:

```
FM_Plan/stage_cmd  <- ref("FM_Stage/control_outputs/cmd")
FM_Plan/stage_act  <- ref("FM_Stage/control_outputs/act")
FM_Plan/stage_x    <- ref("FM_Stage/control_outputs/wx")
FM_Plan/stage_z    <- ref("FM_Stage/control_outputs/wz")
FM_Plan/stage_sel  <- ref("FM_Stage/control_outputs/sel")
```

`stage_cmd` is a monotonic counter and `FM_Plan` acts on the **difference**, so a dropped cook
cannot lose an edit and a slow one cannot apply it twice. `FM_Stage` emits at most one command
per cook, because an expression samples a control output once a frame and a second command in
the same cook would be silently overwritten.

---

## Public seed profile and density study

The public example opens at 128 ants and has a hard authored ceiling of 128. Its buffers,
simulation dispatches, and renderer draw count are all sized to that ceiling, so reducing the
parameter also avoids carrying the old 1024-ant fixed allocation.

The table below records the earlier density study that produced the bucket-grid architecture.

| What | Was | Is | Why it had to change |
| --- | ---: | ---: | --- |
| population | 64 | 1024 | |
| body length | 4.2 mm | 1.5 mm | |
| arena | 160 x 110 | 260 x 180 mm | |
| `walk` / `gait` | 1 group of 64 | 16 groups of 64 | groupshared does not span groups, so the exact neighbourhood had to go |
| neighbours | exact O(n²) groupshared | 28 x 20 bucket grid | 1 M tests a cook, and the grid is also what the deposit needs |
| pheromone field | 0.25 scale | 0.5 scale | at 0.25 over a 260 mm arena a whole deposit fell inside one texel: no gradient, no stigmergy, no symptom |
| deposit | every texel asked every ant | 3 x 3 cell query | 252 M tests a cook otherwise |
| contact shadows | per pixel in `FM_Render` | baked field in `FM_Colony` | **943 M iterations a frame** at 1024 ants |
| ant record | 80 B | 96 B | station ownership, age and emergence |

**The bucket grid is built by GATHER, not scatter** — one thread per cell looping the population
and keeping what belongs to it, rather than one thread per ant atomically appending. It costs
more arithmetic and buys three things worth more than the arithmetic: no atomics so the result is
bit-identical run to run, no clear pass for the dependency scheduler to misplace, and a full cell
that truncates in index order rather than by whoever won the race.

It reads `ants`, so it is scheduled *after* `walk` and `walk` reads what it wrote last cook. That
is deliberate and it is the same one-cook feedback the pheromone field has always run on.

**Moving the shadows was the largest single win and it was not an optimisation.** The answer never
depended on the camera: a contact shadow on a flat ground plane is a property of the arena, and it
was being recomputed from scratch for every pixel that happened to look at the same square
millimetre. Computed once, where the grid makes the query local, it is a texture fetch — and it is
now correct for every consumer instead of being something only the beauty pass knew how to do.

---

## Why the pheromone field is not its own node

It was planned as one and it cannot be. Deposit and sense are a closed loop: the field is
written by ants and read by ants. Splitting that across a graph edge is a cycle, and the graph
is a DAG. koi_tank's trick of closing a loop through control outputs carries one float, not a
texture. The chemical memory therefore belongs to the colony that owns it — which is also the
honest reading, since the field is the colony's state and not the arena's.

---

## The scaffold: plan over route diagram

`FM_Plan`'s canvas is a draughtsman's drawing, not a small copy of the render. That distinction
matters more than usual here: the program image is **itself** a top-down view, so a plan strip
alone would have been a grey duplicate of the photograph.

- **Plan** — the arena footprint from above, on a 10 mm grid, with the scale bar drawn as an
  ant. Nest as a punched hole with a spoil hatch, caches as piles of crumbs, obstacles from the
  same signed-distance function the colony steers on, and every route as the curve it actually
  is with direction chevrons.
- **Flow** — one lane per route, laid out by **true walked length** against the same millimetre
  ruler. This is the strip that earns its place: a plan cannot show that two caches which look
  equidistant are not, and the gap between a lane's end and its ghost tick is exactly the cost
  of the detour. It also carries the measured traffic fed back from the colony, and the
  **failure mode** — a route through an obstacle or off the arena draws in alarm red, in the
  plan, in its lane, and in the status row.

Verbs: click select, drag move, drag a route's mid handle to bend it, `M` obstacle kind,
`F`/`V` more/less, `G`/`H` recruitment, `B` auto-route around obstacles, `X` on/off, `N` re-roll
one, `R` reseed, `P` palette, `C` clear.

`FM_Colony` carries the second readout the renderer cannot give: a **Hildebrand footfall chart**
for the focused ant, lanes ordered by tripod rather than by leg number, so a correct alternating
gait is unmistakably three-on/three-off and a broken one is unmistakably not. Measured foot slip
draws in alarm red on the bar it happened on.

---

## What a re-roll means

Ants are not a scatter. Their identity is **relational**: a cache is a bearing and a range *from
the nest*, and an obstacle is only meaningful because it is *in the way* of a route. So
`variation` randomises relationships, never coordinates:

- caches are drawn as stratified **bearings around the nest**, in a radius band;
- obstacles are placed **on a route** at t ∈ [0.24, 0.76], with a lateral offset drawn strictly
  smaller than their own half-width, so they are guaranteed to intersect the line they were
  placed against;
- route bends are **derived** from which obstacles the straight line actually hits, never drawn;
- the topology — who connects to whom — is never re-rolled at all, because that *is* the
  arrangement's identity.

| Guarantee | Without it |
| --- | --- |
| stratified bearing sectors, hash-permuted | all the food lands on one side |
| radius band from the nest | a cache on top of the nest, or off the arena |
| three separation relaxation sweeps | two caches inside a body length read as one |
| descending payload ladder by construction | four equal dots, no hierarchy, nothing to look at |
| obstacle offset below its own half width | obstacles that block nothing; routes stay ruled |
| clearance solve, both sides tried | a route through a stone |
| one uniform centroid-and-scale fit | the network lands wherever the draw put it |
| total recruitment normalised | a seed with no traffic, or with every route saturated |

Every correction is gated on `variation > 0`, so the transcription is never nudged off its own
coordinates. **`variation = 0` is exactly the reference, and that is verifiable rather than
asserted:** read the Plan data port and the nest comes back at footprint `(-0.88, 0.76)` and the
cache at `(0.86, -0.72)`, bit-identical to the tables in `plan.hlsl`.

---

## Exploration axes (shipped as enums, not throwaway variants)

- `FM_Plan / arrangement` — **Trail Crop** (the transcription) · Foraging Fan · Trunk Trail ·
  Raid Front. Trunk Trail is the only one where an edge starts somewhere that is not the nest,
  which is what proves the edge contract is a graph and not a star.
- `FM_Colony / trail_fidelity` — at 0 the colony is purely emergent and must discover its own
  routes; at 1 it hugs the plan's network. The default is a weak attractor.

Diagnostic views ship too, because in a chain that is mostly invisible bookkeeping they are the
only way to tell a dark lane from a dead one: `FM_Render / view_mode` (Beauty, Normals, Depth,
Shadow, Field) and `FM_Post / view_mode` (Program, Depth, Circle of Confusion). The Depth view
found a real bug — see the traps below — and is the reason it exists.

---

## Node presets (project scope)

- **`FM_Render / Frame - Column`** — camera parameters ALONE, the composed pose for the 260 mm
  arena. `Frame - Trail Crop` is kept and is the older overhead framing, composed when the arena
  was 160 mm; it still recalls cleanly but no longer frames the same crop.
- **`FM_Render / D0 Draft · D1 Live (default) · D2 Beauty · D3 Hero (capture only)`** — the ant
  detail rungs ALONE. See the measurement note below, which is more honest than a ratio table.
- **`FM_Plan / Stations - Foraging Demo`** and **`Stations - Off (reference)`** — the station
  parameters ALONE. *Off* is `station_count = 0`, which with `variation = 0` is exactly the
  transcribed photograph. **Note:** an `FM_Plan` preset also carries the 4160-byte plan state
  buffer, so recalling one restores the hand-placed records too — wider than the parameter list
  suggests, and worth knowing before you recall one over work you want to keep.


- **`FM_Render / Frame - Trail Crop`** — camera parameters ALONE. The internal camera is meant
  to be flown, so the composed pose is lost the first time anyone explores and is recoverable
  from nothing else in the project. Recall it before any final capture.
- **`FM_Post / Q0 Draft · Q1 Live (default) · Q2 Beauty · Q3 Hero (capture only)`** — bokeh tap
  count ALONE. The spiral fills a disc evenly at any count, so the bokeh *shape* does not change
  with the rung; only its smoothness does.

Recalling the camera does not disturb the look; recalling a quality rung does not disturb the
framing. That is the point of the narrow scope.

### The detail ladder has four rungs, and Hero raised the ceiling

**A ladder can only ever spend LESS than the declared vertex budget** — it degenerates the
surplus, it cannot invent vertices. So "higher quality" is not a shader tweak: it is a change to
`VERTS_PER_ANT` in `antgeo.hlsli` AND to the pass's `vertex_count`, and if the two disagree the
last ant draws truncated. The budget went 3552 → **6672** an ant, 3.64 M → **6.83 M** for the draw.

The extra is spent lopsidedly on purpose. The ellipsoids were already smooth enough that doubling
them buys little; the **leg tubes at six sides are visibly hexagonal prisms** in any close shot,
and that is what looked cheap. So tubes go to twelve sides and the bodies rise modestly.

The rung counts are now an explicit table rather than a halving of the capacity, specifically so
that raising the ceiling did **not** silently move every rung underneath it — `Full` reproduces
the original mesh bit for bit.

| Rung | gaster | body | nodes | tube sides |
| --- | --- | --- | --- | --- |
| Hero | 24 x 14 | 16 x 10 | 14 x 6 | 12 |
| Full — *the original mesh* | 16 x 10 | 12 x 8 | 12 x 4 | 6 |
| Reduced — **default** | 8 x 5 | 6 x 4 | 6 x 3 | 4 |
| Distant | 6 x 4 | 5 x 4 | 6 x 3 | 3, no mandibles |

Measured, same sitting, all previews open:

| | total_ms | fps |
| --- | ---: | ---: |
| 512 ants, Reduced — the shipped default | 13.5 | 60.0 |
| 1024 ants, Hero, no auto-drop | 21.9 | ~54 |

**The raised ceiling is close to free at the default** — 13.4 → 13.5 ms — because the ladder
trades rasterisation and overdraw, and the extra vertex-shader invocations degenerate almost
immediately. Hero at full population genuinely does not hold 60 Hz, which is what a capture-only
rung is for.

**The enum indices shifted when Hero was inserted at 0, and all four ladder presets were
re-saved.** A preset stores the integer, so without that they would each have quietly come to
mean the rung below.

### What the detail ladder actually trades, and what could not be measured

The vertex COUNT is fixed at compile time — 3552 an ant, 3 637 254 for the pass — so a lower rung
cannot reduce vertex-shader invocations. It reduces what is **rasterised**, by emitting whole
degenerate quads. Emitted, non-degenerate vertices per ant, which is arithmetic rather than a
measurement:

| Rung | gaster | body x2 | nodes x2 | legs | antennae | mandibles | total | vs Full |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Full | 960 | 1152 | 576 | 648 | 144 | 72 | **3552** | 1.00x |
| Reduced | 240 | 288 | 216 | 432 | 96 | 48 | **1320** | 0.37x |
| Distant | 144 | 240 | 216 | 324 | 72 | 0 | **996** | 0.28x |

**The wall-clock cost of the rungs was NOT measured, and I want to be plain about why rather than
publish a ratio table that looks like it was.** The graph holds its 60 Hz vsync cap at every rung
and at every population I tried, so frame time reports the cap and not the work: 1024 ants at
Reduced measured `pipeline_ms` 4.80 and `total_ms` 7.19 against a 16.67 ms budget, while 400 ants
at Full measured 5.14 and 7.26 — the larger population came out *lower*, which is noise, not a
result. Isolating per-node GPU time needs the Stats detailed-profiling toggle, and that is a UI
preference with no StateTree path, so it could not be enabled from here. **Turn it on by hand in
Stats and re-measure before trusting any rung ordering.**

### What population actually costs

Measured in one sitting at 1.5 mm, Reduced detail, 1280x720, **with all six node previews open**,
which the workspace notes is worth a 3–5x swing on its own. `pipeline_ms` is a single-frame
sample and it is noisy, so several were taken:

| Ants | pipeline_ms samples | total_ms | reported fps |
| ---: | --- | ---: | --- |
| 400 | 5.14 | 7.26 | 60.0 |
| 512 | 11.75 | 13.44 | 60.00 |
| 1024 | 4.80 · 9.36 · 15.53 · 13.79 | 7.19 – 17.32 | 50.8 · 57.9 · 62.8 · 71.6 |

The original density study shipped at 512 and measured 1024 as a marginal ceiling. The public
seed now caps the population at 128 to keep the example approachable while preserving the same
stigmergic, gait, station, camera, and macro-lens systems.

The instantaneous fps figure is not trustworthy here: it reports values above the 60 Hz cap,
which means it is a per-frame reciprocal rather than a rolling rate. Treat the table as evidence
that 512 is comfortable and 1024 is marginal, not as four significant figures.

The bokeh ladder below it is unchanged and its earlier finding still stands.

**Measured in one sitting, with all five node previews open**, as pipeline milliseconds:

| Rung | Taps | pipeline_ms | vs Q1 |
| --- | ---: | ---: | ---: |
| Q0 Draft | 8 | 1.567 | 0.97x |
| Q1 Live (default) | 20 | 1.613 | 1.00x |
| Q3 Hero | 56 | 1.919 | 1.19x |

The whole graph held its 60 Hz vsync cap at every rung; total frame time was 2.94–3.43 ms
against a 16.67 ms budget. **The honest finding is that this ladder buys very little**: the
bokeh gather is not the bottleneck at 1280x720, and Hero is labelled capture-only out of
convention rather than necessity. Q2 Beauty was not separately timed. Those numbers predate the
population change and were not re-taken.

---

## Traps found here, worth not rediscovering

**Fixed-length bones are what make a procedural insect read as a spider, not the stance.** The
femur and tibia were authored as fractions of body length — 0.82, 0.93 and 1.05 for the three
pairs — while the stance they had to reach was 0.61, 0.74 and 0.81. Bones 26 to 35% longer than
the hip-to-foot distance have to put the surplus somewhere, and they put it in the knee: a high
angular peak over the back, which is the strongest spider cue there is. The trap is that the
obvious fix makes it WORSE — pull the feet in with the bones left alone and there is *more*
slack to absorb, so the knees jut further. Bones are now derived from the hip-to-ankle distance
with a single `slack` of 1.15, so the two can never desynchronise again, and the rear pair still
comes out longest because its foot is genuinely further away.

The stance was also wider than its own comment claimed: it said "a footprint about one and a
half body lengths across" and then set the middle pair at 0.82 either side, which is 1.64.

**Leg length is a simulation fact; leg thickness is not.** `FM_Colony / Leg Length` moves where
the feet are planted, so the gait, the stride and the measured slip all follow it — which is why
it lives in the colony. `FM_Render / Leg Thickness` changes nothing the colony knows about. The
radii it scales are fractions of BODY length rather than of leg length, deliberately: shortening
the legs then makes them relatively stubbier on their own, and long-and-thin is the spider
silhouette while short-and-substantial is the ant. Both ship at 1.0, with the judged values baked
into the constants, so the sliders read as relative adjustments rather than as corrections you
have to remember to apply.

**A buffer-writing pass cannot be a module output, and the symptom was not black — it was the
gait chart painted across the sweep.** `shad` writes `output: "buffer:shadf"`, so it has no
render target and no SRV; naming it directly in `outputs:` produced a Shadow pin that was
permanently hollow. `FM_Render`'s `_Tex4` then fell through to whatever texture the device had
bound last, which was `FM_Colony`'s own canvas — and the sweep dutifully sampled it through
`fmWorldToFieldUV` and shaded it as a shadow, so the Hildebrand chart appeared lying on the
ground plane in correct perspective. Compile said 11 of 11 passes, health was green, and every
link was correct **by pin name**. It survived a whole session unnoticed because the stale
binding happened to be harmless, and only became visible after a project reload changed what was
bound last. The fix is the blit `field_out` already used for the pheromone field: `shad_out`
reads the buffer and publishes it. **One call finds this** — `capture pipeline slot=<n>` on the
suspect output returns *"no SRV (0x0 or not rendered yet)"*; check that before reading any shader.

**Adding a video output renumbers a node's data pins, and Sentinel re-resolves existing links by
INDEX.** Adding `Shadow` to `FM_Colony` silently turned `Ants -> FM_Render.Ants` into
`Shadow -> FM_Render.Plan`, left `Feet` unconnected, and did the same to two `FM_Scope` links.
Nothing errored: a data input fed a texture and an unconnected structured buffer both read as
garbage, and the symptom was every leg stretching into hundreds of millimetres of tube converging
on a vanishing point — which reads as a vertex-shader bug in whatever you just wrote, not as a
wiring change you did not make. After touching `outputs:` on a wired node, check every downstream
link **by pin name** before debugging anything else.

**The plan was a REFLECTION of the arena, not a rotation of it.** With the colony frozen and the
camera put straight overhead, the twenty-four ant records read back from the data port land on
the captured frame at *screen right = world +x, screen up = world +z*, to within a pixel on every
one. The plan drew +z DOWN the page with +x still to the right, which is not the view from
anywhere — it is that view mirrored. So every route curve, obstacle yaw and chevron had the wrong
handedness on top of the left-right swap that is the part you notice. A plan may be rotated
freely and must never be reflected; `plan_facing` now picks between the two rigid half-turns.

**Sentinel's camera basis is left-handed**, so a camera at +z looking toward −z genuinely puts
world +x on the LEFT of frame: `right = (cos yaw, 0, −sin yaw)`. That is why the default page
orientation is `page right = −x`.

**A released ant drags its old feet, and the gait pass MEASURES it as slip.** An emitter moves a
body across the arena in one cook while its tarsi are still planted where it went dormant; the
stance correction then hauls all six the whole distance and reports it honestly. Measured before
the guard: mean slip 0.48 mm with peaks of 6.58 mm on a 1.5 mm animal, the gait chart solid red.
After it: 0.08 mm mean, 0.66 mm peak. A foot further than six leg-reaches from its neutral point
was not scuffed, it was reseated.

**An alarm threshold in absolute units does not survive a change of scale.** `slip_alarm` was
0.35 mm, which is 8% of a 4.2 mm worker and a quarter of a 1.5 mm one. At the new body length the
old default lit every bar on the chart and the alarm stopped carrying information. It is still
absolute — it is a measured distance and hiding that would be worse — but it has to be re-tuned
when the animal changes size.

**A dynamic index into a LOCAL array inside a parameter-bounded loop makes fxc give up.** The
station allocator kept per-station tallies in `float liveOf[16]` and asked for them by an index
the compiler could not see through, inside a loop bounded by `ant_count`; the result is
`X3511: forced to unroll loop, but unrolling failed`, pointing at a line number offset by the
injected parameter preamble. Tally into the buffer instead — buffer memory has no such problem —
and put `[loop]` on anything the compiler might try to unroll.

**Do not bind a structured buffer as an SRV and a UAV in the same pass.** The station pass reads
and writes its own state through the UAV, the way the clock does. Binding it as an input as well
nulls the SRV and the shader reads zeros with no error anywhere — every accumulator would restart
at zero each cook and the emitters would simply never fire.

**Degenerate a whole QUAD, never a stray vertex.** The detail ladder re-parameterises each body of
revolution with fewer slices and stacks and degenerates the surplus. Degenerating alternate quads
of the *full* parameterisation instead would not make a coarser ant, it would make one with slots
cut through it — and degenerating a single vertex of a live triangle makes the clipper stretch the
other two across the frame.

**A blown-out background hides every shadow you compute.** The plan's light is sized for the
ants, whose chitin has an albedo near 0.15. The sweep's albedo is 0.95, so the same light put
the ground at roughly 2.8 — nearly three times over white. Every contact shadow was being
computed correctly, darkening 2.8 to 1.5, and every one was still above clipping and therefore
invisible. The ants floated on a flat white field and the shadow code looked like it had never
run. One exposure control fixed the shadows *and* dropped the chitin from a clipped orange to
the reference's mahogany, because both faults were the same fault.

**`source: "depth"` declares no dependency on the draw that fills the depth buffer.** Passes are
scheduled by buffer dependency, so the reader is free to run first and sample a buffer still
cleared to 1.0. Measured through a banded diagnostic view, every pixel reported the far plane —
so `FM_Post` saw the whole frame at 600 mm against a 68 mm focus and blurred all of it,
uniformly, at every aperture. That reads exactly like a broken lens and is a scheduling bug.
Adding an explicit `pass:scene` input to force the ordering did **not** fix it either. The fix
is to write eye depth from the pass that already knows the world position: it travels in the
beauty's alpha, and the extract pass reads `pass:scene`, which is a real dependency.

**`asfloat` of a small integer is a denormal, and D3D flushes denormals to zero.** The gait
chart packed its six-leg stance mask that way and every sample came back as "no legs down", so
the chart drew nothing at all — while the speed trace beside it, an ordinary float, worked
perfectly. Store small masks as plain numbers; 0..63 round-trips through float exactly.

**Bump the version when generation code changes.** The signature is built from parameters, and a
shader edit changes none of them, so the persistent buffer kept serving routes built by the old
code and the meander edit looked like it did nothing. Diagnosed by arithmetic: the header's
stored signature was 1625.12 while recomputing it from the live parameters gave 1716.29, and the
difference was exactly `0.1 x 911.7` — one version bump.

**A hot reload does not always take.** After several rapid manifest saves, `plan.hlsl` kept
running an older build while `canvas.hlsl` picked up its edit immediately. `force_reload` is the
cure, and a value read back from the data port is the only way to know you need it.

**Pick the bend side by trying both.** The clearance solve chose its side from the outward normal
at the deepest violation, which is right for a pebble and useless for the obstacle that matters:
a twig lying square across a route has a surface normal parallel to the chord, so the side test
is a coin toss and half the time the solve pushes the curve further *along* the twig. Measured:
three of four routes stayed blocked in a four-route fan; trying both sides and scoring the
outcome took it to one, and the one that remains is genuinely unroutable with a single control
point.

**Stride sets the step frequency, not the other way round.** With `f = v * beta / stride` the
ground covered during one stance phase is exactly the stride, so a planted foot is never
*required* to slide. Author the frequency independently and every foot skates by the difference
— the classic procedural-walk failure, invisible in a still frame. Measured mean slip at the
shipped defaults is **0.00004 mm**, with peaks around 0.27 mm on hard turns where the outer legs
genuinely run out of leg and the tarsus is picked up early. That peak is real and is reported
rather than absorbed.

**Seeding a colony at t = 0 synchronises it.** Twenty-four ants released at the nest together
reach the food together, load together and come home as one lockstep column — measured LADEN =
1.00 with the whole population in a single clump. That is an artefact of the initial condition,
not behaviour, and it takes minutes to disperse. The colony is seeded along the routes in
steady state instead, which is also what the reference photograph shows: a working trail with
ants at every stage of a round trip.

**An instrument palette built for a dark canvas is inverted on a white one.** The shared
`plan_theme` makes `PT_INK` near white because on a near-black ground the brightest mark is the
most present. The scope's overlay sits on a blown-out sweep, where near-white ink is invisible
and mid grey is the loudest thing in frame. `FM_Scope` therefore keeps the palette's *structure*
and roles and inverts its value ladder, darkening the two reserved hues so they still separate
from white.

**Never draw a ring buffer's wrap seam.** Walking back N slots gives N-1 consecutive pairs; the
Nth joins oldest directly to newest and draws a chord across the whole trail. Segments are
validated by **timestamp order**, not ring index, because a same-cook write is not guaranteed
visible to a later pass.

**Two structured buffers cannot be written by one pass**, and two draw passes cannot composite
into one colour target. The gait moved into its own pass ordered by buffer dependency, and the
sweep moved into the ants' vertex range as six leading vertices.

**Include paths resolve from the module project directory**, not from the including file, so a
sibling inside `_shared/` still has to be reached as `../_shared/`.

**`bake_defaults` will bake your live measurements.** Run over `FM_Plan`'s Live group it captured
a snapshot of the running colony — 22 ants walking, lane 0 at 1.00 — as the manifest defaults, so
a freshly opened project would display a confident measurement, in the reserved live colour, of a
colony that had not taken a step. Restored by hand; exclude that group from any future bake.

**A `color` parameter clamps to 0..1 per channel.** The grade's cool shadow tint was authored as
`[0.92, 0.96, 1.04]` and had silently been `1.0` all along. Express a relative tint by pulling
the other channels down.

---

## Honest gaps

- **The gesture paths cannot be machine-proven.** Injected input does not reach Module viewport
  events, so every click, drag and key path in `FM_Plan` and `FM_Stage` was built and reasoned
  through but not exercised over MCP. What *is* verified: the pick maths shares one coordinate
  conversion with the canvas that draws it, the record round-trip through the data port, the
  signature/rebuild behaviour, the blocked-route detection, and the persistence of the plan
  buffer.
  **Exercise by hand:** click a cache and confirm it turns amber; drag it; drag a route's mid
  handle and confirm the curve follows the cursor rather than lagging it by half; press `B` with
  obstacles on and watch the route bend clear; press `M`, `F`/`V`, `G`/`H`, `X`, `N`, `R`, `P`;
  press `A` on the plan and on the stage and confirm a station lands under the cursor in both.
- **`FM_Stage`'s command path IS verified, up to the viewport events.** Driving `stage_cmd`,
  `stage_act`, `stage_x` and `stage_z` by hand with the expressions temporarily cleared, a place
  command put a station in slot 4 at footprint (−0.3077, −0.6111) — which is (−40.0, −55.0) mm,
  bit-for-bit what was sent — and a toggle command switched it off, with the plan's `STA` readout
  following from 05 to 04. What remains unproven is only the half that turns a real click into
  those control outputs.
- **The ground lane's accuracy was not measured against a known point.** The unprojection is
  built from `_InvViewProjMatrix` and looks right — the reach ellipses sit on the sweep and track
  the camera — but nobody has clicked a specific ant and checked the returned millimetres against
  its record. Worth doing once by hand.
- **The internal camera was not flown by hand.** Its parameters were driven over the StateTree
  and the geometry, shadows, depth lane and scope overlay all moved together and stayed
  registered, which proves the injected matrices drive every camera-dependent pass. It does not
  prove the viewport's own RMB/WASD path. **Exercise by hand** in `FM_Render`'s preview, then
  recall `Frame - Trail Crop` to get the composed pose back.
- **Only Trail Crop has been judged against captures.** Foraging Fan was used to prove the
  relational randomiser, the obstacle placement and the blocked-route alarm, but its framing was
  never composed. Trunk Trail and Raid Front are built and reachable and have not been looked at.
- **The colony bunches.** Ants on a shared route with a shared speed distribution drift into
  dense clusters and then apart again. Real trails do this, and the reference shows workers
  nearly touching, so it is left in — but `separation`, `wander` and `trail_fidelity` are the
  three controls that trade it, and the balance was set by eye rather than measured.
- **The pheromone field is anisotropic by 1.3%.** Its texture is 600 x 410 over a 260 x 180 mm
  arena, so a texel is very slightly non-square and diffusion spreads marginally faster along
  one axis. It was 0.6% before the arena grew. Below the threshold of visibility, recorded
  because it is the kind of thing that matters if the arena is made wider again.
- **`FM_Scope` covers the first 64 ants, not all 128, and that is deliberate.** Every mark it
  draws exists to be read. Covering the full colony would make the instrument needlessly dense
  plate, which is not a denser instrument but an opaque one. The first 64 slots are a fair sample
  rather than a special group, since the colony seeds and the emitters deal out of one pool in
  index order.
- **Slip peaks are proportionally larger at 1.5 mm than they were at 4.2 mm.** Mean is 0.08 mm
  against a 0.12 mm alarm, but peaks reach 0.66 mm on hard turns: a smaller animal at the same
  320°/s turn rate turns much more sharply relative to its own body, so the outer legs run out of
  reach more often. It is a real measurement of a real scuff and it is left in rather than damped,
  but `turn_rate` is the control that trades it and it has not been re-tuned for the new scale.
- **The historical high-density captures used the earlier 400 to 1024-ant build.** The public
  128-ant profile still needs a fresh side-by-side review of every detail rung.
- **Q2 Beauty was not separately timed**, and the quality ladder as a whole buys very little at
  this resolution.
