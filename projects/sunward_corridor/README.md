# Sunward Corridor

An endless flight down a checkerboard corridor toward a setting sun, built from a reference
image of a pixel-grid perspective corridor.

Three nodes: **SC_Plan** (authority) → **SC_Corridor** (renderer) → **SC_Grid** (finish).

---

## Component map

| Node | Single responsibility |
| --- | --- |
| `SC_Plan` | Plan authority and editor. Owns the record buffer: bays, masses, sky, palette. |
| `SC_Corridor` | The renderer. Ray-marches the endless corridor from the plan records. |
| `SC_Grid` | The finish pass: pixel-grid quantization and final grade. |

## The route

The reference decomposes into two families that had to share one contract: a **periodic
architectural repeat** (the tiled tunnel, its aperture rhythm, its palette) and an **organic
cast** (the smooth white folds bulging through the grid). They live in one record buffer with a
`role` discriminator — `ROLE_BAY`, `ROLE_MASS`, `ROLE_SKY`, `ROLE_HEADER` — rather than two
parallel lanes, so there is exactly one answer to "where is anything".

## How the infinite zoom actually works

**The camera never moves.** The corridor scrolls through it.

Every field in the renderer is sampled at `world z + travel`, and every one of them is periodic
with `SC_LOOP_Z` (24 units = 12 stations × 2). `travel` wraps at exactly that period, so the
frame at `travel = 0` and the frame at `travel = SC_LOOP_Z` are the same frame down to the bit.
There is no crossfade and no teleport to hide.

Periodicity is **structural, not a constraint anyone has to maintain**: bay stations are
addressed modulo `SC_BAYS` by the Catmull-Rom in `corridor.hlsli`, so any per-station value —
including a random draw or a hand edit — is automatically periodic. The user cannot create a
seam by editing the plan.

Three things needed explicit care to stay seamless:

- **Checker cells along z** divide `SC_LOOP_Z` an *even* number of times (`checker_cells` is
  rounded to even in the shader). An odd count flips every tile's parity at the wrap and turns
  a seamless loop into a strobe once per period.
- **The accent-cell hash is keyed on a WRAPPED cell index.** This one shipped broken and was
  caught by eye, not by the first test. Parity being periodic is not sufficient: the scattered
  vermilion and pale tiles are drawn from a hash of the cell *index*, and at the seam that index
  jumped by `cellsZ`, so every accent tile redrew while the geometry stayed put. The checker
  visibly reshuffled once per period. The fix wraps the longitudinal cell coordinate into one
  loop before it reaches the hash; because `cellsZ` is forced even the wrap preserves parity,
  and because it lands on an integer it falls on a tile boundary and never cuts a tile.
- **The per-station checker scale multiplier drives lateral cell size only.** Modulating the
  *longitudinal* cell size would require the integral of the rate over one loop to land on an
  even integer, which nothing guarantees.

### How to actually test the seam

Worth writing down, because the obvious test is wrong. `phase` is an *offset* added to a frozen
travel accumulator, so comparing `phase = 0.99` against `phase = 0.01` does **not** straddle the
wrap — where the wrap falls depends on the accumulator. Read `travel` off the header record
(`hdr.grp`), compute `phase_wrap = 1 - frac(travel / SC_LOOP_Z)`, and probe a small step either
side of *that*.

Then compare against a control step of the *same size* elsewhere in the loop, and **diff the
images** rather than trusting a scalar. A mean-absolute-difference over one channel hid this bug
completely: magenta and vermilion differ by only ~20/255 in red, so a full tile flipping colour
scored lower than a checker edge moving one pixel. The amplified difference image showed it
instantly — solid blocks at the seam versus hairlines in the control.

Measured, all channels, equal-size steps:

| | mean abs diff | channels changed >25 |
| --- | --- | --- |
| wrap, before fix | 28.07 | 20.17% |
| wrap, after fix | 10.77 | 8.54% |
| control step, mid-loop | 12.72 | 9.35% |

After the fix, crossing the wrap costs slightly *less* than an equivalent step anywhere else.

`travel` integrates against `_DeltaTime` (never rate × absolute time), so changing Flight Speed
mid-flight does not jog the corridor. `phase` rides on top as a sweepable loop coordinate:
0 → 1 is exactly one period, which makes motion proof deterministic.

### Why the sun never arrives

A genuinely endless *straight* tube converges to a vanishing **point**, and a sun at infinity
seen down one would be a dot — you cannot get the reference's big sun that way. So the tube is
cut by a plane a fixed distance ahead of the eye (`Sky Distance`) and the sky is shown through
the hole. You fly forever and the sun never gets closer. That is deliberate dream logic, and it
is the thing the reference is actually about.

The cut is an SDF intersection (`max(dTunnel, p.z - aperture_z)`), not an early-out returning a
large constant — a constant would let a ray just short of the plane take one huge step straight
through the geometry.

---

## Data contract

One buffer, 24 records of 48 bytes, persistent (`state_buffers`), published as `Plan`.

| slot | role | `pos` | `size` | other |
| --- | --- | --- | --- | --- |
| 0–11 | `ROLE_BAY` | centre offset (x, y) | aperture half-extent | `kind` palette set · `grp` roll · `phase` tile scale · `tone` accent density |
| 12–21 | `ROLE_MASS` | (z on the loop, perimeter t) | (radius, elongation) | `kind` mass kind · `grp` squash · `phase` fusion softness · `tone` sheen |
| 22 | `ROLE_SKY` | sun centre, aperture units | (sun radius, small-sun radius) | `kind` stripes · `tone` horizon · `grp`/`phase` small-sun offset |
| 23 | `ROLE_HEADER` | (signature, selection) | (drag strip, grab x) | `grp` travel accumulator · `phase` published travel · `flags` packed tallies |

`SC_Corridor` re-decides none of it. It owns light, surface, the checker material and the
internal camera; that is all.

Two derivations worth keeping:

- A mass's world frame comes from the corridor profile **at its own station** — it is attached
  to the perimeter, never given parallel coordinates that could drift out of registration.
- The small pale sun's offset is derived from `horizon`, so it sits just clear of the sea at
  every horizon setting. It originally had absolute coordinates and drowned silently the moment
  the tide was raised.

---

## The plan authority is an editor

`SC_Plan`'s preview is a draughtsman's **plan over elevation** sharing one z axis — not a copy
of the program image. It answers, without opening the renderer: where the walls go, the aperture
at each station, which stations are hand-edited or switched off, where every mass sits on the
perimeter, where the eye is right now, and whether the flight path stays inside the tunnel.

That last one earns its keep: the **cyan dashed line is world 0**, the axis the eye actually
flies along. It turns red where it leaves the filled band. A corridor bent hard enough to fly
through its own wall is visible in the diagram instead of being discovered as a black frame.

Gestures: click select · drag move (the **plan strip owns lateral drift, the elevation strip
owns rise** — same handle, two projections, which is how you draw a corridor on paper) ·
`Q`/`E` narrow/widen · `K` cycle palette or mass kind · `X` straighten/toggle · `N` re-roll ·
`R` reseed · `C` clear.

Dragging a mass recovers its perimeter angle from the dragged section point: the dragged axis
takes the new value, the other keeps the one that strip cannot see. That is a true
plan/elevation edit rather than two sliders that disagree.

`variation = 0` is exactly the transcribed reference and can never be lost. Raising it re-rolls
station offsets, aperture, roll, tile cadence, palette zoning and mass placement, while
preserving the aperture **rhythm** and the mass **size hierarchy** — a flat random draw per
station turns a corridor into a lumpy gut and loses the one-hero-fold read.

---

## Exploration verdicts

**`tunnel_style` on SC_Corridor** — what the corridor is built from.

| preset | verdict |
| --- | --- |
| **Box** | **Winner, baked as default.** Crisp rectangular opening and hard corners; the closest read to the reference. |
| Rounded | Kept. Genuinely different — a soft tube, more organic, the checker wrapping a continuous curve. Good for a warmer show. |
| Colonnade | **Repaired, not deleted.** First pass was indistinguishable from Box: the pilaster profile was 0.16 deep and gated on nothing, so it read as faint rings. Now cosine piers gated on *sideness*, which is what makes them columns rather than rings. |
| Ribbed | **Repaired, not deleted.** Same failure — relief too shallow to see. Now four courses to the bay at a readable depth. |

Each relief style pays its **own Lipschitz bill** with a local scale factor rather than forcing
Step Scale down for every style. A wall profile of amplitude A and angular frequency f adds A·f
to the field gradient; stepping as if it did not is exactly how relief turns into surface acne.

**`grain_mode` on SC_Grid** — which artifact the image is quantized through. **Column Smear**
baked as default (the reference's per-column vertical runs). Clean Grid, Scanline Drift and
Mosaic Bleed all kept and working.

---

## MK_LENS — the checker-displacing mass kind

Most masses are solid bodies wearing `Mass Tint`. `MK_LENS` instead **wears the checker** and
**drags the checker's coordinates radially in a neighbourhood** — so the grid bends across the
swell *and* across the flat wall beside it. That second half is what sells it: the reference's
grid is distorted, not merely interrupted by an object sitting in front of it.

Two decisions worth keeping:

- **It warps texture coordinates, not the distance field.** Pulling the SDF around would drag
  the silhouette, charge a Lipschitz bill on every march step, and *still* not bend the grid on
  the wall beside the swell. `lensWarp()` runs once per shaded pixel, not per step.
- **The offset scales with the offset vector itself, not a normalized direction.** A normalized
  direction is undefined at the lens centre while the falloff bell is at its maximum there,
  which prints a pinwheel singularity at every lens — it reads as "crazy" right up until the
  angle where it reads as a bug. The current form magnifies uniformly near the centre and
  vanishes cleanly at it. The twist is a deliberate perpendicular term (`Lens Swirl`), added on
  purpose rather than harvested from that artifact.

The warp is periodic (`w` comes through `sc_wrapDZ`), so adding it to `zc` before the seam wrap
cannot reintroduce a loop seam — re-measured after adding it: 11.44 across the wrap vs 13.44 for
an equal control step.

Geometry is broad and shallow on purpose; a tall dome hides the grid behind its own silhouette.
The default cast carries two, and `K` cycles any mass onto it.

## Lighting

One source — the opening — shared by the walls and the masses. Giving the checker its own
private flat treatment is what made the folds look pasted on rather than growing out of the
corridor, so both surfaces go through the same terms.

- **The sun is a position, not a direction.** It sits just past the opening, so light arrives
  *along* the corridor and any surface can be asked whether it can see it. That single fact
  produces the reference's read: bright throat, shaded foreground, folds casting down the tube.
- **Walls are lit by visibility, not by N·L.** They run nearly parallel to the light, so a plain
  lambert term blacks them out. Visibility (occlusion × shadow) carries the shading and N·L only
  leans it. `Shade Floor` keeps the checker graphic instead of muddy.
- **Field occlusion is the primary shadow cue** — it darkens the tunnel corners and lays a soft
  halo wherever a mass meets its wall.
- **Shadows tint warm.** A plain multiply preserves hue but drags white tiles toward *neutral*
  grey; the reference's shaded whites stay warm off-white. The tint gate runs past 1.0 so a
  little of it reaches the mid-tones. That is the difference between "shaded" and "dirty".

### Two lighting states — read this before judging the look

The manifest defaults currently hold the **live slider state as of the last save**, which is
considerably flatter than the tuned lighting described above. If the corridor looks
under-shadowed, these are the values to restore:

| parameter | tuned | currently baked |
| --- | --- | --- |
| `shadow_amt` | **0.75** | 0.131 |
| `shadow_reach` | **3.2** | 0.843 |
| `wall_ao` | **0.72** | 0.34 |
| `ambient_floor` | **0.64** | 0.752 |
| `aa_samples` | **2** | 1 |
| `march_steps` | **110** | 101 |
| `normal_eps` | **0.0035** | 0.008 |

Three artifacts had to be beaten, all of which look like different bugs and are all sampling:

| symptom | cause | fix |
| --- | --- | --- |
| Every wall shadows itself to black | the opening lies almost in the wall's own plane, so a constant normal bias leaves the shadow ray skimming its own surface | normal bias that **grows** with ray distance (`Shadow Bias`) |
| Concentric rings around every caster | naive `h/t` penumbra only samples the field at step points, quantizing the soft edge | closest-approach estimator interpolating between steps |
| Five hard arcs on walls behind a mass | the five AO taps sit at the same depths for every pixel, so a caster near one prints a ring | per-pixel dither of the tap distances, sized under one tap spacing so the quantizer downstream does not amplify it into speckle |

## Traps hit on the way

- **The corridor section had to go portrait.** With a landscape section there is a ceiling plane
  in frame no matter where the eye goes. `SC_BASE_W 0.92 / SC_BASE_H 1.15` plus a high eye is
  what produces two big side walls, a broad floor, and almost no ceiling.
- **Changing those constants did nothing until `PLAN_VERSION` was bumped.** Bay sizes are
  generated *from* them, and the persistent buffer kept serving landscape apertures.
- **The visible aperture is much smaller than the far rect.** It is the intersection of every
  cross-section along the way, so `bend` and `flare` pinch the throat far more than they appear
  to. Opening the sun up was a bend problem, not a sun-radius problem.
- **Contact occlusion drove the white folds to mud.** Every mass is attached to a wall, so the
  raw AO term sees a half-occluded hemisphere *everywhere*. It is floored and on a short leash,
  and it is a contact cue rather than a lighting model.
- **`_CameraFOV` arrives in degrees.** Feeding it straight to `tan()` silently poisons every
  epsilon in the march.
- **The walls are deliberately not tonemapped.** They are flat art-directed paint; running hot
  magenta through a curve turns it to putty. Only the lit masses roll off, and on the max
  channel so the tint survives the highlight.

---

## Control surface

Scene Group **Sunward Corridor** exposes eight controls, all verified end to end through the
group path to the member parameter: Tunnel, Sky Distance, Tile Width, Sun Wash, Grid Artifact,
Pixel Columns, Smear, Colour Steps. No camera rows are exposed.

**Known limitation — SC_Plan could not be added to the Scene Group.** Its graph node reports a
garbage height that climbs in step with its data-output generation counter (observed growing
through ~700k → ~960k over a few minutes), so no sanely-sized annotation can ever contain it.
`place_relative within` briefly reports `contained_by`, but the group re-checks containment at
call time and by then the node has grown past the box again. This looks like a Sentinel bug
affecting any Module with a `data_output`. Consequence: **Flight Speed, Variation, Seed and Bend
live on SC_Plan's own Properties**, not on the group surface. Worth filing.

## Proof

- `proof/` — final still, plan view, `flight_loop.mp4` (two full periods), and
  `scene_group_pushed.png` (all eight group controls driven to extremes, to show the surface has
  real range).
- All three nodes healthy at 1280×720. The app frame is ~16.6 ms of which ~15.1 ms is UI
  present, so the graph is not the bottleneck; no isolated GPU cost was measured for the
  lighting pass (Detailed Profiling was left off).

**Not machine-verified:** injected input does not reach Module viewport events, so the plan
editor's click / drag / key paths could not be exercised over MCP. What *was* verified: buffer
persistence, signature-driven regeneration, the pick maths against known record coordinates, and
that the preview decodes selection and edit state. **The gestures themselves need exercising by
hand** in the SC_Plan preview — select a station, drag it in each strip, and confirm `Q`/`E`,
`K`, `X`, `N`, `R`, `C`.
