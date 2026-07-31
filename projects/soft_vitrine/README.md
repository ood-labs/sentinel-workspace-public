# SOFT VITRINE

A surreal sculpture vitrine on an electric-blue cyclorama: matte clay masses, liquid
black-and-white chrome, a translucent frosted body, glossy tube strokes and flat graphic plates,
all standing in one lit room with a reflective floor.

Reviewed output: **`VT_Post`** (1080 x 1080).
Saved graph: `soft_vitrine.sentinel`. Scene Group: **SOFT VITRINE** (`annotation_54`).

## Route

```
VT_Plan ──Plan──┬──────────────────────────► VT_Stage ────────────┐
(plan authority)│                                                  │
                ├──► VT_Growth ──Limbs──┬──► VT_Volumes ──────────┤
                │                        └──► VT_Strokes ──────────┼─► VT_Composite ─► VT_Post
                ├──────────────────────────► VT_Plates ───────────┘        ▲
                └───────────────────────────────────────────────────────────┘
                                                              Plan (horizon)
```

| Node | Responsibility |
| --- | --- |
| `VT_Plan` | The plan authority. Owns stage space and the horizon, generates the whole composition, holds hand edits. Interactive editor. |
| `VT_Stage` | Cyclorama wall gradient, sprayed-plaster relief, horizon seam, receding reflective floor. |
| `VT_Growth` | Expands mass anchors into world-space capsule chains and stroke anchors into stage-space polylines. Publishes bounding spheres for culling. |
| `VT_Volumes` | Ray-marches the masses. Clay / chrome / frost / gloss. Owns the internal camera. |
| `VT_Strokes` | Draws the stroke limbs as lit tubes with a cylindrical fake normal. |
| `VT_Plates` | The flat graphic family, split into back and front layers. |
| `VT_Composite` | Stacks the layers, derives the drop shadow and the floor reflection from total coverage. |
| `VT_Post` | Bloom, filmic curve, grade, lens separation, grain. Nothing structural. |

## Contracts

**STAGE SPACE** (`modules/_shared/vitrine.hlsli`) is the single layout transform: `[0,1]²`,
origin top-left, +y down. It is identical to a square generator pass's `uv` and to normalized
viewport pointer coordinates, so render, pick and drag cannot drift apart. `VT_Plan` is the only
node that decides placement; every consumer reads stage space straight off `uv`.

**The show leaves 2D exactly once**, in `vt_toWorld`. The canonical camera sits at
`(0, 0, -1.732)` with a 60° vertical FOV, so `z = 0` has a half-height of exactly 1.0 and world
XY in `[-1,1]` fills the square frame. `vt_toWorld` **pre-divides by the depth**, so a record
projects to its planned stage position at any `z` — depth changes apparent size, shading and
overlap, never planned placement.

**One `Plan` buffer, 64 records of 48 bytes**, discriminated by `role`: records 0–23 are flat
plates, 24–39 stroke anchors, 40–55 mass anchors, 62 the global stage record (horizon, room
depth), 63 the console header. It is `persistent` and a `state_buffer`, so hand edits survive
saves, presets and undo.

**One `Limbs` buffer, 768 records**, also `role` discriminated: 0–31 are group headers carrying a
bounding sphere plus `[first, count)`, 32–415 mass nodes, 416–767 stroke points. The fixed
partition is deliberate — a heavy mass cast must not be able to starve the strokes of points.
`material` is role-discriminated: a mass node stores `MAT_*`, a stroke point stores its accent
tone, which is how one bundle runs a full rainbow across its strands.

**Magnitudes derive from the reserve.** `size.x` on a mass anchor is its footprint and the only
size input to the grower; `size.y` is a node-budget share and deliberately does not enter the
geometry. Folding both in made every magnitude depend on two numbers and shrank the small
archetypes to dots.

**Coverage is a real lane, not alpha.** The near-black vein network and the starfield panel are
undecidable from colour against a dark stage, so `VT_Volumes`, `VT_Strokes` and `VT_Plates` each
publish coverage separately. Layer order comes from the plan's `F_FRONT` flag, so the compositor
re-derives it rather than deciding it a second time.

## Things that will bite the next person

- **`PLAN_VERSION` in `VT_Plan/plan.hlsl`.** The plan buffer is persistent and only rebuilds when
  its signature changes. Parameters feed that signature; **shader edits do not**. Bump it when you
  change the layout algorithm or a recompile will silently keep serving the previous plan.
- **A record-generator loop needs a single exit.** The mass grower originally had per-archetype
  branches that each wrote their record and `continue`d. Above roughly 30 iterations fxc dropped
  every iteration of those branches and only the root record survived — but at 6 iterations the
  same shader was correct, so it looked like a budget bug. Every archetype now assigns `pt`/`rr`
  and falls through to one `writeLimb` at the bottom of the loop. `[loop]` did **not** fix it.
- **The growth preview's per-group tally is load-bearing.** Outline = the node count the header
  declares, fill = nodes actually found active in that range, short fills in red. That turned
  three capture-and-deduce cycles into one look. Do not delete it.
- **Radius-to-bond ratio decides articulation.** At 0.83 every pair of nodes overlapped almost
  completely and the melt came out a smooth horseshoe. ~0.31 keeps the tube continuous while the
  lobes stay legible.
- **Node count matters as much as direction.** Fifty nodes inside one containment disc packs into
  a ball no matter how the directions are chosen. The reference's figures are ~15-node trees.
- **Stroke thickness must be absolute, not a fraction of the extent.** Scaling it by the wander
  extent turned the wide black vein network into a solid blob while leaving tight hairlines
  sub-pixel.
- **Within one stroke, the closest segment must win.** Taking the first covering segment left a
  dark rib at every joint, because the shading read the cross-section parameter of the wrong
  segment.
- **The stage's plaster needs a uv-space epsilon and a real frequency.** Scaling the gradient
  epsilon by the noise frequency sampled several screens away and flattened the relief to nothing;
  `grain_scale` multiplies a base of 150–320 cycles/uv, which is a few pixels per cell at 1080.
- **`force_reload` preserves live parameter values.** Editing a manifest default and reloading does
  not change a running node — set the value or re-create. Two look changes were judged against the
  old values before this was noticed.

## Camera

`VT_Volumes` owns Sentinel's internal camera (`features: [camera]`,
`viewport.interactions: [camera]`, `camera_ref` empty, Fly mode). Its saved pose is the canonical
one above, so the marched masses register with the flat layers. Flying it is an intentional
creative move. RMB look, WASD move, wheel adjusts speed. No camera parameter is exposed on the
Scene Group.

## Plan interaction

Click to select a record, drag to move it. `K` cycles kind, `M` cycles material, `X` toggles
active, `N` re-rolls that record, `R` reseeds the layout, `C` clears the selection. Edits set
`F_EDITED` and survive until the layout signature changes.

**Not machine-verified.** Injected input does not reach Module viewport events, so the
click/drag/key path could not be proven from this session. The plan generates a complete
composition procedurally before anything is touched, and the edit code path is the same one
`matik_plate` uses, but a human needs to exercise the console preview to confirm it.

## Exploration record

Four axes were built as shipped `enum` presets, swept, and the losers repaired rather than
deleted.

- **Layout preset** (`VT_Plan`) — *Vitrine* won: the transcribed reference arrangement. Column
  Rack is a strong second. Salon Wall and Diagonal Drift both originally bunched a short cast into
  the top rows; both were reworked to spread (coprime slot shuffle, deterministic diagonal march).
- **Growth mode** (`VT_Growth`) — ***Bundle* won decisively.** It is the only mode that produces
  the reference's raised-arm branching hand. Branching is a good, more even second. Tendril is a
  strong distinct direction (coiling intestinal tubes). Coral lost badly — short bonds plus heavy
  jitter packed every cluster into a featureless potato; repaired to radiate outward from the root
  with near-full bonds, which gives the knobbly head the preset was named for.
- **Stroke style** (`VT_Strokes`) — *Round Tube* won (the reference's glossy extruded marks).
  Ribbon is an attractive flat-strap alternative. Flat Marker is a genuinely useful graphic mode.
  Beaded lost — at 22 cycles the bead period was shorter than the spacing between published
  points, so the swell aliased away on every hairline; repaired to 7 cycles with a deeper pinch.
- **Clay finish** (`VT_Volumes`) — *Plaster* won. Sand is a strong, very distinct gritty look. Wax
  carries light further round the form. Smooth is the clean option.

## The arrangement randomizer

`Variation` (0–1) on `VT_Plan` blends the transcribed reference arrangement into a free draw from
the same vocabulary: positions, kinds, materials, palette and layer membership all re-roll.
`Seed` picks which draw you get — scrub it to shuffle. **`Variation = 0` reproduces the reference
arrangement exactly**, so the default cannot be lost by exploring.

Three things keep a random draw looking composed rather than looking like a bug:

1. **Stratified placement.** Each record takes a distinct cell of a 4×4 grid and jitters inside
   it. A uniform random draw reliably piles three masses into one corner and leaves a third of the
   stage bare; stratification guarantees coverage while staying random. The per-role strides
   (7 / 11 / 5) are all coprime with 16, so each is a bijection and the roles interleave instead
   of stacking in the same cells.
2. **Size hierarchy is preserved.** Only the *magnitude* around each slot's rank is randomized, not
   the rank itself. The tables already encode one hero mass, two supports and the rest incidental;
   a flat random size draw destroys that and reads as noise.
3. **Stroke weight stays bimodal.** A ~20% chance of a heavy mark, otherwise a hairline. Drawing
   weight uniformly makes every seed read as flat spaghetti.

`Anchor Spacing` then relaxes any residual mass overlaps using the reserve radii the records
already carry. Relaxation runs **only** when `Variation > 0`, so the reference positions are never
nudged off their transcribed values.

## Scene Group presets

- **Vitrine (Reference)** — the default: `Variation = 0`, the reference-matched arrangement.
  Verified recallable in one call; `recall_scene_group_preset` restores it exactly.
- **Diagonal Tendril** — Diagonal Drift layout, Tendril growth, Flat Marker strokes, Sand clay.
  Found while proving the exposed controls and kept because it is a good look in its own right.
- **Scatter 42** — `Variation = 0.75`, seed 42. A worked example of the randomizer.

All three store all nine exposed controls including `Variation`, so recalling any one of them
fully defines the arrangement.

**One-time shift, recorded honestly:** adding `variation` and `spacing` changed the plan's
signature, which forces a rebuild. Layout, palette and every element family were unaffected, but
the procedural *growth* draw for the melt and the coral resolved differently than in the captures
taken before the parameter existed. The result is deterministic and is now pinned in the saved
project and in the preset.

## Performance

Eight nodes. Frame total ~2.3 ms at 61 fps with all nodes healthy and frames advancing. Detailed
per-node GPU/CPU profiling was left disabled, so per-node timings were not measured — the figure
above is the graph frame total from `sentinel_graph profile`. The ray-marcher is the expensive
node by construction; it stays cheap because each pixel tests 16 bounding spheres before touching
any of the 295 mass nodes.
