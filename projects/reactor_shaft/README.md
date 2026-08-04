# Reactor Shaft

An endless flight down a triangular machine shaft toward a burning core, built from a reference
image of a greebled cyberpunk tunnel seen end-on.

Three nodes: **RS_Plan** (authority) → **RS_Shaft** (renderer) → **RS_Lens** (finish).

---

## Component map

| Node | Single responsibility |
| --- | --- |
| `RS_Plan` | Plan authority and editor. Owns the record buffer: stations, fixtures, lights, the core. |
| `RS_Shaft` | The renderer. Ray-marches the endless shaft from the plan records. |
| `RS_Lens` | The lens finish: bloom, flare, grade. |

## The route

The reference decomposes into three families that share one contract: a **periodic architectural
repeat** (the shaft, its bays, its wall panelling), a **discrete cast of machinery** bolted to
those walls (heatsink combs, grille panels, girders, tanks, stacked blocks), and an **emissive
cast** mounted on that machinery (neon runs, cross-face bars, beacons, corner flood lamps). Plus
one hero focal object, the core. They live in one record buffer with a `role` discriminator —
`ROLE_STATION`, `ROLE_FIX`, `ROLE_LIGHT`, `ROLE_CORE`, `ROLE_HEADER` — rather than parallel
lanes, so there is exactly one answer to "where is anything".

## How the infinite zoom actually works

**The camera never moves.** The shaft scrolls through it.

Every field in the renderer is sampled at `world z + travel`, and every one of them is periodic
with `RS_LOOP_Z` (30 units = 12 stations × 2.5). `travel` wraps at exactly that period, so the
frame at `travel = 0` and the frame at `travel = RS_LOOP_Z` are the same frame. There is no
crossfade and no teleport to hide.

Periodicity is **structural, not a constraint anyone has to maintain**. Two rules do it:

- Stations are addressed modulo `RS_STATIONS`, so any per-station value — a random draw or a
  hand edit — is automatically periodic.
- **Every fixture and light lives entirely inside its own station's half-slice** (`RS_SLICE_H`).
  This is what makes the renderer's ±1-station march window *provably* sufficient — a point is
  at most `RS_SLICE_H` from its nearest station and nothing reaches further than `RS_SLICE_H`
  out of its own — and it also means two stations can never overlap, whatever the user drags.

### Twist is a swing, not a ramp

A monotonic 120°-per-loop spiral would leave the **bore** seamless, because every section style
here is 3-fold symmetric. It would still break the shaft: at the wrap every fixture would land on
its neighbour's face, and the three fixture slots at a station do not have interchangeable
geometry. So `roll` is a per-station value interpolated on a closed Catmull-Rom — a periodic
swing. Near and far sections are always rolled differently, which gives the reference's rotating
read, and the loop is exact.

### The seam bug this shipped with, and how it was caught

The geometry was periodic from the first frame. The **wall texture was not.** Panel cells and
micro-relief cells were hashed on `floor(z / cellSize)` using **unwrapped** z, so at the wrap the
cell index jumped by a non-integer number of cells and the entire wall re-hashed while the
geometry stayed put — a full-frame reshuffle once per period.

Measured, all channels, equal-size steps either side of the wrap versus an equal-size control
step elsewhere in the loop:

| | mean abs diff | channels changed >25 |
| --- | --- | --- |
| wrap, before fix | 27.98 | 37.67% |
| **wrap, after fix** | **23.92** | **32.00%** |
| control step, mid-loop | 26.48 | 34.12% |

After the fix, crossing the wrap costs slightly *less* than an equivalent step anywhere else.

Two things were needed together, and either alone is insufficient:

1. **Wrap the longitudinal coordinate** into one loop before it reaches the hash.
2. **Make the cell count per loop an exact integer** (`RS_PANEL_CELLS = 96`), so the wrap lands
   on a cell boundary instead of slicing a cell in half.

The consequence is that the per-station panel scale may drive **lateral** cell size only.
Modulating the longitudinal size would require the integral of the rate over one loop to land on
an integer, which nothing guarantees.

### Finding the seam is not obvious

`phase` is an *offset* added to a frozen travel accumulator, so comparing `phase = 0.99` against
`phase = 0.01` does **not** straddle the wrap — where the wrap falls depends on the accumulator.
Read `travel` off the header record (`hdr.grp`), compute `phase_wrap = 1 - frac(travel / RS_LOOP_Z)`,
and probe a small step either side of *that*. Then compare against a control step of the **same
size** elsewhere. Freeze `grain` and `core_spin` first — both ride `_Time` and will swamp the
measurement.

`travel` integrates against `_DeltaTime` (never rate × absolute time), so changing Flight Speed
mid-flight does not jog the shaft.

### Why the core never arrives

A genuinely endless straight tube converges to a vanishing **point**, and anything at infinity
down one would be a dot — you cannot get the reference's big glowing core that way. So the tube
is cut by a plane a fixed distance ahead of the eye (`Core Distance`) and the core plate is shown
through the hole. You fly forever and it never gets closer.

The cut is an SDF intersection (`max(dWall, p.z - core_z)`), not an early-out returning a large
constant — a constant would let a ray just short of the plane take one huge step through the
geometry.

---

## Data contract

One buffer, 74 records of 48 bytes, persistent (`state_buffers`), published as `Shaft`.

| slot | role | `pos` | `size` | other |
| --- | --- | --- | --- | --- |
| 0–11 | `ROLE_STATION` | section centre offset (x, y) | (bore inradius, corner rounding) | `kind` palette · `grp` roll · `phase` panel scale · `tone` density |
| 12–47 | `ROLE_FIX` | (z offset in slice, u along face) | (half-width, protrusion) as **fractions of the inradius** | `kind` fixture kind · `grp` face 0–2 · `phase` z half-length |
| 48–71 | `ROLE_LIGHT` | (z offset in slice, u along face) | (half-length, tube radius) | `kind` light kind · `grp` face 0–2 or corner 3–5 · `phase` hue · `tone` intensity |
| 72 | `ROLE_CORE` | centre, bore units | (outer radius, hot radius) | `kind` spokes · `grp` ring depth · `phase` spin · `tone` gain |
| 73 | `ROLE_HEADER` | (signature, selection) | (drag strip, grab x) | `grp` travel accumulator · `phase` published travel · `flags` packed tallies + section style |

`RS_Shaft` re-decides none of it. It owns light, surface, volume and the internal camera.

Three derivations worth keeping:

- **Every fixture magnitude is a fraction of its own station's inradius**, not an absolute size.
  One `Bore` control therefore moves the shaft, the blocks and the tubes coherently, and a block
  cannot drift out of registration with the wall it is bolted to.
- **Lights derive their face and along-face position from a host fixture.** A neon run belongs
  beside the block it lights. Drawing free coordinates for them is what turns a lit machine into
  fireflies. The light radii were originally absolute constants — they looked right at exactly
  one `Bore` setting and like wire or like plumbing at every other. That is now derived too.
- The header's `flags` carries the section style, so the **plan** owns section shape (a placement
  decision) and the renderer reads it rather than keeping a second copy that could disagree.

---

## The plan authority is an editor

### Why this scaffold, and not an elevation

The subject is organised **along its axis**. The program image looks straight down that axis,
which is precisely the one projection that cannot show it — so a front elevation would have been
a copy of the render that hides the render's own subject. `RS_Plan` draws what a draughtsman
draws for a shaft:

- **A longitudinal clearance section** — z across, *distance from the flight axis* up. Three
  face-plane curves with the wall solid filled outward from each; every block drawn as a bar
  reaching inward from its own face curve down to its exact clearance.
- **A cross-section rosette** at the scrubbed station — the true twisted section with every
  fixture on its actual wall. One section cannot show *which of three faces* carries what; the
  rosette cannot show *runs along z*. Both are needed and both are cheap.
- **A core inset** drawing the real plate, not a schematic of one.

The rosette **follows the selection** when there is one — click a block in the clearance section
and the cross-section snaps to the station that owns it — and rides the playhead otherwise.

### The failure mode is in the diagram

The cyan dashed line is the **flight tube**: the radius the eye needs kept clear. Anything
intruding into it turns solid red, in both projections, and is counted in the alarm row. A shaft
you cannot fly down is visible in the diagram instead of being discovered as a black frame.

The clearance number is the **exact box-to-axis distance**, not the face-plane distance. A block
sitting out toward a corner really is further from the axis than its own face plane, and a
conservative measure would condemn arrangements that are fine.

### Gestures

**`SPACE` plays and pauses the flight.**

Click select · drag — **the clearance section owns the axial edits** (where along the shaft a
thing sits, and how far it reaches into the bore), **the rosette owns the section edits** (which
wall carries it, where along that wall, and the bore's 2D centre drift). Same handle, two
projections. Dragging a block round a corner onto the next wall is one continuous gesture,
because the drag recovers the face from the nearest face plane rather than from a separate
control.

`Q`/`E` narrow/widen · `A`/`D` shorten/lengthen the run · `K` cycle kind · `F` cycle wall or
corner · `X` on/off · `N` re-roll this record · `R` reseed · `C` clear selection.

### Why transport is a flag and not the speed parameter

A shader cannot write a host parameter from a key press, so `SPACE` cannot set Flight Speed. It
does not want to. **Pause is transport state, not a speed value**: it lives in the persistent
header and gates the travel integration, which means Flight Speed still reads correctly while
paused and resuming does not have to remember and restore a number. `Phase` still scrubs while
paused, so Space-then-scrub is the natural way to stop on a station and edit it.

The playhead carries the state — solid amber running, dashed cyan paused — plus a play/pause
glyph above the strip, because a stopped playhead that looks identical to a moving one is a
readout that lies about why nothing is happening.

The state is stored as `2 = paused, 3 = running` in the header's init flag. It must NOT be
`1 = paused`, because `1.0` is what that field held before transport existed and every
already-saved project would then open frozen with no visible cause.

### What a re-roll means

This subject's identity is **relational**, not positional: a fixture is a thing bolted to a wall
at a station, and a light is a thing mounted on a fixture. Drawing free coordinates per record
scatters machinery into open air. `variation` re-rolls the *relationships* instead — which wall
carries which rank of block, where in its own slice it sits, what kind it is — with four
guarantees that are the difference between a seed and debris:

| Guarantee | Without it |
| --- | --- |
| Faces are drawn as a **permutation** of {0,1,2}, never three free draws | two blocks fuse into one lump at the same z; this removes the whole class without a rejection loop |
| A block stays **on** its face, allowing for the **rounded** corners (`rs_faceLimit`) | blocks poke through the rounded corner and hang in space outside the shaft — this shipped, and the plan view caught it |
| Protrusion capped against the **flight tube** | you fly into a heatsink |
| Every record stays inside its own **station slice** | stations overlap and the ±1 march window stops being sufficient |
| Sizes randomise **around each rank's own value** | the one-big-block / medium-panel / small-detail hierarchy dies and a machined wall becomes gravel |

`variation = 0` is exactly the transcribed reference and can never be lost.

---

## Records versus texture

Records own the **readable structure**: three editable blocks and two editable lights per
station. The wall's **density** — the hundreds of small units the reference's walls are actually
made of — is procedural micro-relief, so there is no record per rivet and the editor stays
usable. Continuous features (the conduit rails running the full length, with clamp collars) live
in the wall field rather than in records, because anything continuous along z is automatically
periodic and needs no record at all.

The relief is a real **box repetition**, not a per-cell offset added to the bore field: adding a
per-cell constant makes the field discontinuous at every cell wall and the marcher walks straight
through the cliff. A **coarse gate** leaves patches of wall flat, because a uniformly bumpy
surface reads as noise — the reference works because big smooth slabs sit next to dense clusters.

---

## The cost trick

Evaluating nine fixture boxes and six lamps at every march step would be unaffordable. But every
rail, block and lamp lives within `shell` of the wall, and the bore field is 1-Lipschitz, so a
point further out than that is provably at least `(dw - shell)` from all of them. Steps down the
middle of the tube therefore cost **one bore evaluation**, and the boxes are only paid for in the
thin skin where they can actually be hit.

Compile time needed the same discipline: `[loop]` on the fixture, light, AA and volume loops, and
the per-ray render extracted into a function. Left to unroll, `fxc` inlined nine copies of the
distance field into a function the marcher calls per step and took minutes without finishing.

---

## Traps hit on the way

| Symptom | Cause | Fix |
| --- | --- | --- |
| Whole frame a flat pink fog bank | volume integrated with **no transmittance**, so haze added to everything equally instead of progressively hiding it | proper `T *= exp(-sigma dt)` accumulation |
| An entire flat wall painted one saturated magenta sheet | unnormalised Blinn specular + roughness reaching 0.26, so a nearby tube's lobe covered the whole wall — a **lighting** bug that looks exactly like a grading mistake | `(shininess+8)/128` normalisation and a matte roughness floor |
| Dark machined walls turn to flat mid-grey sheets | the panel grid at a grazing angle aliases into a uniform average of base and edge colour | analytic line widening by the **pixel footprint**, plus a hash fade where filtering is impossible |
| The machinery flattens into one pale mass | a plain fresnel rim fires over a tunnel wall's *entire* area, because a tunnel wall is grazing everywhere | rim gated on real **convexity** (one map probe along the normal), with a threshold — with micro-relief on, *some* convexity exists at nearly every pixel |
| Distant walls boil and shimmer | centimetre-scale relief boxes smaller than a pixel | distance LOD on the relief height |
| The wall reads as a light-up toy | a fifth of all panel cells were emissive, and each telltale filled its whole cell | small marks *inside* a panel, ~6% of cells |
| Panels read as a checkerboard | per-cell brightness variation far too wide | narrow it; the wide range is what most obviously says "procedural" |

Two more worth stating plainly:

- **`_CameraFOV` arrives in degrees.** It is used for the pixel-footprint estimate; feeding it
  straight to `tan()` poisons every antialiasing decision downstream.
- **Bloom and flare need different thresholds.** Sharing one lets a merely bright wall throw
  anamorphic arms, and a wall with arms is smear rather than a lens.

---

## Exploration verdicts

**`section_style` on RS_Plan** — what the bore is cut as. Every style is 3-fold symmetric on
purpose, so the three attachment faces stay put and not one fixture record is invalidated by
changing it.

| preset | verdict |
| --- | --- |
| **Triangle** | **Winner, baked as default.** The reference's read: three big flat walls and hard corners. |
| Chamfered | Kept. Truncated corners give a heavier, more armoured shaft; good when the corner lamps need somewhere to sit. |
| Hex Bore | Kept. Opens the corners into a six-sided tube — reads as pressure vessel rather than structure. |
| Trefoil | Kept. Large corner rounding; a soft organic tube, the furthest from the reference and the most useful for a warmer show. |

**`greeble_set` on RS_Plan** — what the shaft is built from. **Heat Exchange** baked as default
(the reference's fin combs). Cargo Deck, Sensor Array and Bare Structure all kept and working.

**`flare_style` on RS_Lens** — what lens it was shot on. **Anamorphic** baked as default (the
reference's long cold horizontal arms). Star, Halo and Off all kept.

---

## Node presets

- **`Frame — Down The Shaft`** — the camera parameters *alone*. The internal camera is meant to
  be flown, so the composed pose is lost the first time anyone explores and is recoverable from
  nothing else in the project. Recall it before any final capture.
- **`Quality 1–4`** — Draft / Live / Beauty / Hero, quality parameters *alone*. **Live** is the
  manifest default. **Hero is capture-only.**

Recalling the camera does not disturb the look; recalling a quality rung does not disturb the
framing.

### Measured, and an honest result

Program throughput (RS_Lens cooks) over an 8-second window per rung, all three node previews
open, 1280×720, single sitting:

| rung | rays/px | march | volume | frames / 8 s | ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| Draft | 1 | 64 | 8 | 804 | 1.00 |
| Live *(default)* | 4 | 120 | 18 | 933 | 1.16 |
| Beauty | 9 | 180 | 30 | 852 | 1.06 |
| Hero | 9 | 320 | 64 | 882 | 1.10 |

**These numbers do not separate, and the ordering is not even monotonic.** On this machine the
graph's cook rate is capped by the host scheduler at ~100–120 Hz end to end and is not bound by
the renderer at *any* rung — nine rays per pixel and 320 march steps cost no measurable
throughput. The spread above is noise.

What that means honestly: `frames_processed` counts submitted cooks, not completed GPU work, so
this measurement bounds the scheduler rather than the shader. **Isolated GPU cost was not
measured** — Detailed Profiling was left off, so `gpu_ms` and `cook_hz` were null throughout. The
ladder is still worth shipping: it exists for weaker GPUs and higher output resolutions, where
the analytic work ratios (Hero does ~9× the rays and ~2.7× the steps of Live) will bite. Anyone
needing real per-node GPU numbers should enable Detailed Profiling in Stats and re-measure.

---

## Control surface

Scene Group **Reactor Shaft** exposes nine controls, every one verified end to end through the
group path to the member parameter: Flight Speed, Variation, Seed, Machinery, Palette, Core
Distance, Haze, Flare, Glare. No camera rows are exposed.

`proof/group_pushed.png` shows all nine driven to extremes at once. It is also the clearest
evidence that the relational randomiser works: at `Variation = 0.62` with a different seed,
palette and machinery set, the shaft is still a shaft — blocks flush on walls, lights on blocks,
nothing floating.

---

## Proof

- `proof/final_hero.png` — final still at the Hero rung.
- `proof/plan_view.png` — the clearance section over the cross-section rosette.
- `proof/flight_loop.mp4` — 17 s of real-time flight at the default speed, slightly over two full
  periods (one period = `RS_LOOP_Z / Flight Speed` = 30 / 3.6 = 8.33 s).
- `proof/group_pushed.png` — all nine Scene Group controls at extremes.

All three nodes healthy at their declared resolutions, frames advancing, app frame ~1.0–1.6 ms of
which the great majority is UI present, so the graph is not the bottleneck.

**Not machine-verified:** injected input does not reach Module viewport events, so the plan
editor's click / drag / key paths could not be exercised over MCP. What *was* verified: buffer
persistence, signature-driven regeneration, the record values against the transcription tables,
the packed header tallies (36 live fixtures, 24 live lights, **0 clearance violations**), and that
the preview decodes selection, edit state and transport state. **The gestures themselves need
exercising by hand** in the RS_Plan preview — press `SPACE` and confirm the playhead stops and the
glyph flips, select a fixture, drag it in each strip, drag one round a corner onto the next wall,
and confirm `Q`/`E`, `A`/`D`, `K`, `F`, `X`, `N`, `R`, `C`.

Note that `SPACE` is a *focused authored binding*, which the host router ranks above global
shortcuts — but the preview must be focused, and a click on the preview focuses it.
