# axon_press

An axonometric print collage you fall into forever.

Built from `RefImages/AIRefs/abstract/b004f03b48c207f4c682deb7dd71ca8a.jpg` — a dense collage
painting of interlocking isometric volumes faced with newsprint, houndstooth, checkerboard,
stripes and flat saturated planes, cut with hard triangles, routed with bright hairlines and
run with dripping paint.

The brief added one thing the reference does not have: **make it so we can fly into it
endlessly.**

---

## Component map

| Node | Single responsibility |
| --- | --- |
| `AX_Plan` | Plan authority and editor: lattice placement, extents, form, paper, colour, focus, travel. |
| `AX_Press` | The renderer: octave composite, facet materials, ink, traces. |
| `AX_Ink` | The screen-fixed print surface: misregistration, dot gain, screen, paper, tone. |

## The route

```
AX_Plan  ──Plate──▶  AX_Press  ──video──▶  AX_Ink
(authority)          (renderer)            (surface)
```

Three nodes, one record buffer, one direction of authority.

| Node | Owns | Never touches |
| --- | --- | --- |
| `AX_Plan` | lattice placement, extents, form, paper, colour, the focus, the fitted lattice unit, travel | pixels |
| `AX_Press` | the octave composite, facet materials, ink, traces | where anything is |
| `AX_Ink` | misregistration, dot gain, screen, paper, tone | what the image is |

---

## Why there is no camera

The reference's identity is that it is **axonometric**: parallel edges never converge. Flying a
perspective camera through a scene destroys exactly that, and what you get is an isometric city,
not a collage. So the flight is a **uniform scale of the drawing about a focus point** instead.

That choice is also the only version of "fly into it endlessly" that can actually be endless.
A self-similar zoom closes on itself once per octave, so the loop is exact rather than
approximately hidden.

`AX_Press` declares no `features: [camera]` and no `viewport.interactions: [camera]`. This is a
deliberate departure from the internal-camera default, on the grounds above.

---

## How the endless fall works

One record set is drawn at `levels` scales at once about the focus and composited far to near.

```
s_j = ratio ^ ( frac(travel) + j - (levels - 1 - OUTER) )      // layer scale
slot = ((floor(travel) - j) mod period)                        // layer IDENTITY
```

**A layer is identified by its birth index `floor(travel) - j`, not by its screen slot `j`.**
This is the single subtlest thing in the project and it is worth stating plainly:

- Index anything per-octave by the screen slot and **every layer changes its paper at once**
  each time `travel` crosses an integer. That is a hard, full-frame pop.
- Index by birth and a layer keeps its identity for its whole life. Layers simply renumber as
  one dies at the near end and one is born at the deep end, and the frame at `travel = t` and
  `travel = t + period` is identical.

Proven both ways. Analytically: `slot(j, it+1) == slot(j-1, it)`, and `s_j(ft→0⁺) == s_{j-1}(ft→1⁻)`,
so the (scale, identity) set is continuous across the boundary. Visually: `seam_a.png` /
`seam_b.png` bracket `travelOut = 1` at ±0.01 and show the same composition one step deeper — no
paper flip, no mirror flip, no jump.

`frac(travel)` drives the scale for the same reason. Anything that varies per octave routes
through `axSlotMod(int, int)` — an **integer** reduced mod an integer. A float hashed off travel
strobes at the wrap; that trap has been hit before in this workspace and it is why the contract
is written the way it is.

### What varies octave to octave

Geometry is identical at every octave, or the zoom is not self-similar. Variation comes from:

- **Material rotation** by `slot`, stepping by **one**. `AX_M_*` is ordered printed / patterned /
  flat, so a step of one keeps a paper record papery. A larger step (3 was tried) throws the
  whole printed-versus-flat balance the `paper` control was set to, and the frame fills with
  stripes.
- **Palette rotation** by `slot`.
- **Mirror on odd slots.** Reflecting the plate point about the focus maps the isometric lattice
  onto itself, preserves every radius exactly — so the ladder, the aperture and the fit all stay
  true — and visibly changes the composition. It is free variation.

### Why there is a hole in the middle

Records ring a clear aperture around the focus, so the fall goes **down a funnel of collage**
rather than into a wall. `AX_VK_FRAME` volumes draw only their edge bands, which is where the
reference's open cube outlines come from and also what lets you see all the way down.

---

## The data contract

One buffer, `role` discriminates, 20 floats per record.

```
pos   float3   lattice base corner        (TRC: start point)
ext   float3   lattice extents            (PAN/WDG: exactly one component 0; TRC: signed delta)
role           VOL / PAN / WDG / TRC / HEADER
kind           form within the role
mat, col       paper and palette index          (appearance — refreshed every cook)
host           parent / host record index + 1
rmin, rmax     DERIVED: plate radius band from the focus, cell = 1 units
phase, flags, active, pad0..2
```

**One primitive.** A volume, a sheet, a wedge and a trace are all a lattice-aligned box; a sheet
is one with a zero extent, a wedge is a sheet cut on its diagonal, a trace is the degenerate
segment. `axBoxHit` returns false on a zero-area face, so the same three-face solve collapses
correctly for all four without a branch.

The header carries the projection, the octave ratio and the loop period downstream. `AX_Press`
does **not** declare its own copies — a second copy of any of them is a second authority, and
the two disagree at every setting nobody personally tested.

---

## The scaffold: the plate over the octave ladder

This subject is organised two ways at once, and one view cannot show both.

- **The plate** — the axonometric arrangement of one period, with the **octave rings drawn round
  the focus**. Shows composition. Cannot show periodicity.
- **The octave ladder** — every record's radial extent unrolled onto a log axis, one row per
  record index, with the wrap seam marked. Shows periodicity. Cannot show composition.

They share the radius axis, and the rings on the plate are what couple them: you can see which
records straddle an octave boundary in the picture and read exactly how far in the diagram.

**Two failure modes are drawn rather than left to be discovered as a bad frame:**

1. A record straddling more than **1.8 octaves** turns `PT_ALARM`. Layers overlapping by about an
   octave is what a self-similar zoom *is*, so that is not the failure; the failure is a record
   visible at three scales along one bearing at once, where the eye reads the repeat instead of
   the fall. **Traces are exempt** — a hairline crossing its own copy reads as more line work,
   and long spans across scales are the reference's most characteristic mark.
2. A log-radius column that **no record covers** flags `PT_ALARM` in the coverage strip. That is
   a hole the fall drops through into empty field, and it is invisible in every other view.

Styled from the shared instrument palette (`_shared/plan_theme.hlsli`). Mostly monochrome: face
value carries the axonometric read, `ptSampleFill` carries each record's own chosen colour pulled
toward grey, amber is reserved for selection and the live reading, red for broken.

### Direct manipulation

| Gesture | Effect |
| --- | --- |
| click | select record, or the focus reticle |
| drag **in the plate** | move on the ground plane, **snapped to the lattice** |
| drag **in the ladder** | push the record in or out along its own bearing from the focus |
| drag the reticle / `F` | move the focus (constrained to the ground plane — a well-posed 2×2 solve) |
| `W` / `S` | raise / lower |
| `Q` / `E` | shrink / grow (`sign()` keeps a sheet's zero extent at zero) |
| `K` `M` `P` | cycle form / paper / colour |
| `X` `N` `R` `C` | on-off / re-roll record / reseed / clear selection |
| `Z` | **revert** — zero the salt, release the focus, regenerate (see "Getting back to the original arrangement") |

Two strips, two different edits, one handle. The plate cannot express radius precisely — one
octave is a long way there and a few millimetres on the ladder — and the ladder cannot express
placement at all.

**Not machine-proven.** Injected input does not reach Module viewport events, so the click, drag
and key paths cannot be exercised over MCP. What *was* verified: buffer persistence across
reloads, signature-driven regeneration, the pick maths sharing `axBoxHit`/`axPlateToUv` with the
canvas so a handle is drawn exactly where it is grabbed, and the selection/edit readout. **The
user needs to exercise the gestures by hand.**

---

## What a re-roll means

This subject's identity is **relational**, not positional — interlocking, hosting, spanning. So:

- **The lattice is the relationship.** Volumes snap to integer lattice coordinates, so any two
  share face planes automatically and a randomized draw still interlocks. Off-lattice
  coordinates give detached debris no matter how well stratified the draw is.
- Volumes **attach to a parent** (`weave` decides how), drawing lateral offsets strictly below
  the parent's extent so they share solid rather than touching at a corner.
- Sheets and wedges are **hosted on a volume face**, extent derived from that face.
- Traces span to a **nearest neighbour**, never a free line.

Guarantees, each added because a seed looked broken without it:

| Guarantee | Without it |
| --- | --- |
| Extent drawn **proportional to plate radius** | the arrangement stops being self-similar and the fall reads as things getting bigger |
| Stratified ring, angle and radius on **different** index permutations | records walk a spiral |
| Parent draw **biased toward early records** | a straggling procession walks off the ring |
| **Both-way** radial clamp | inward-only lets a record sit on the focus and swallow the aperture; outward-only lets one stray record drag the fit down and shrink everything to a speck |
| Size hierarchy randomized **around each slot's own rank** | two heroes and a supporting cast become a flat field |
| Child capped against its container (`Nested`) | the mass swallows the box it is inside |
| **Fit pass on the lattice unit** | any seed frames itself: `cell` is chosen so the nearest record edge lands exactly on the requested aperture. One uniform similarity, so no proportion anywhere changes |

`variation = 0` is the transcription and is recoverable at any time.

**Honest note on the transcription.** The reference is a dense collage of well over a hundred
scraps. What is transcribed here is its *vocabulary and statistics* — the element families, the
size hierarchy, the printed-to-flat balance, the palette, the way volumes interlock and wedges
cut facets — placed by a seeded generator, not a hand-read table of a hundred coordinates. A
coordinate table would not have been more faithful and could not have been re-rolled. This is
stated plainly because "variation = 0 is exactly the reference" means something weaker here than
it does for a project with a dozen transcribable landmarks.

---

## Why the plates are fractal

Every plate is a **sum of nested levels at a fixed base size in lattice units**, each weighted by
whether it is currently resolvable (`axLevelW`). Flying in makes the next level fade up inside
the one above it — the newsprint is made of newsprint, the checker of checkers — and the fall
keeps yielding new detail forever instead of bottoming out in flat colour.

**The approach this replaces, and why.** The obvious thing is to pick the finest resolvable level
and cross-blend to the next coarser one. Do not. It was built that way first and it failed twice:

- Blending two scales of a **hard** pattern superposes them, and a checker over a 4× checker is
  not a checker — it is a moiré rosette. The houndstooth panels came out as purple and pink
  flowers.
- It pops, because the chosen level steps by a whole factor whenever the texel size crosses a
  power, and the blend was two levels wide at the crossing.

A weighted nest has neither problem: nothing ever switches, coarse levels persist and fine ones
fade up, and every weight is a continuous function of the texel size — hence a function of the
octave scale alone, hence periodic, hence free.

Four or five levels covers the whole fall: a facet enters sub-pixel and leaves the frame a few
screen-heights across, which is under 300× of range.

---

## The flicker, and where it actually came from

Reported live as "z-fighting and flickering of small lines". It was three separate things, all
fixed at the source in `AX_Press` rather than smeared over in post:

1. **Coplanar depth ties.** Volumes attach *by sharing a face plane*, so coplanar facets are the
   normal case here, not an edge case — and two exactly equal depths let float noise pick a
   different winner each frame. Fixed with a `+ i * 2e-5` bias by record index. Lattice
   coordinates are integers, so real depth differences are of order 1 and this can never reorder
   anything that genuinely differs.
2. **Sub-pixel facets at full opacity.** Deep in the funnel a layer is made of facets about a
   pixel across; drawn opaque they scintillate as the fall resizes them and the centre boils.
   Now faded out as they approach a pixel (`smoothstep(1.1, 3.4, facetPx)`), handing those pixels
   to the octave behind. Depends only on the record's extent and the octave scale — both constant
   per octave — so the loop stays bit-exact.
3. **Hairlines thinner than a pixel.** Traces snapped on and off crossing pixel centres. Now
   analytically filtered: drawn width floored at ~⅔ of a pixel with **opacity scaled down** by how
   much thinner the true line is. Facet ink is faded out on facets under ~9px so the ink band can
   never swallow the facet it outlines.

`AX_Ink`'s `soften` is a fourth, deliberate line of defence — a real press property, since a sheet
does not resolve infinitely, and something has to band-limit a scene that is fractal by
construction. Keep it small; the collage lives on hard cut edges.

---

## Traces: the one thing that had to be rebuilt twice

Traces were first drawn at constant **pixel** weight between **random** volumes. Both were wrong,
and together they laid a neon spiderweb over the whole composition.

- Constant pixel weight makes every octave's traces the same wire thickness. At the near octave a
  span is many screen-widths long, so it crosses everything at hairline weight. Weight is now in
  **lattice units**, so near traces become the reference's broad ribbons and deep ones fall below
  a pixel and disappear — which self-similarity requires anyway.
- A random far end gives lines that cross the whole plate. They now span to a **nearest
  neighbour**, so a line always explains a relationship in the arrangement.

---

## Exploration axes — swept, judged, baked

Four shipped `enum` axes. Every value was rendered and judged from the image; the losers are
repaired and kept, not deleted.

### `weave` on AX_Plan — what a volume's relationship to its parent IS

| | Verdict |
| --- | --- |
| **Interlock** ← **default** | densest, most collage-like, closest to the reference |
| Stacked | tall towers and big open frames — striking, but reads architectural rather than collage |
| Nested | boxes inside boxes; the most apt reading of the concept, since the nesting mirrors the octave nesting |
| Drift | sparser, masses separated, more depth visible between them |

**This axis had a real bug.** `weave` was missing from the regeneration signature, so changing it
did nothing at all — the first two sweep captures came back pixel-identical. Caught only because
the images were compared rather than assumed. Any new structural parameter must be added to `sig`
in `plan.hlsl` or it is decorative.

### `lattice` on AX_Plan — the projection

| | Verdict |
| --- | --- |
| **Isometric** ← **default** | the reference's own cube: three faces at equal angles |
| Dimetric | asymmetric isometric, a slight rotation in feel |
| Cabinet | the flattest and most poster-like, with true square front faces. Genuinely closer to the reference's *flatness* even though its hero motif is the isometric cube — the strongest alternative |
| Steep | near top-down and plan-like; the best "falling down a shaft" read |

### `facet_mode` on AX_Press — what decides a face's paper

**Per Facet** (default) is the reference's own answer: every facet of every box is a different
cutting. **Per Volume** / **Per Axis** / **Split** are the disciplined alternatives; Per Axis in
particular gives a much more orderly image where all tops share one stock.

### `ink_mode` on AX_Press — the line treatment

**Hairline** (default) matches the reference's dark drawn edges. **Halo** is worth knowing about:
white facet edges read like *cut paper*, which is arguably more literally true to a collage.
**Heavy** and **None** round out the range.

---

## Getting back to the original arrangement

Three ways, in order of preference:

1. **Recall the `Arrangement — Shipped` preset on AX_Plan.** This is the complete answer. An
   AX_Plan preset carries **6400 bytes of `durable_state`** — the entire 80-record buffer — so
   recall restores the structural parameters *and* every record, hand edits included. `recall`
   reports `durable_state` in `applied[]` when it lands.
2. **Press `Z` in the plan viewport.** Reverts the buffer: zeroes the reseed salt, releases the
   focus back to its parameters, clears selection, and regenerates. It cannot touch Properties —
   a Module cannot write its own parameters — so `weave`, `lattice`, `seed` and the counts stay
   where you left them. Use it when you have been hand-editing and just want the generated
   arrangement back.
3. **Reload the project.** `state_buffers` serialize into the `.sentinel`, so opening it restores
   everything exactly as saved.

Save your own arrangements the same way: set it up, then save a project-scope preset on AX_Plan
with the structural parameters. `Arrangement — Drift Cabinet` is shipped as a second example.

### Two bugs this exposed

**`R` was irreversible.** The reseed salt only ever incremented and is part of the regeneration
signature, so one press put the shipped arrangement permanently out of reach and quietly falsified
the "`variation = 0` is the transcription, so it can never be lost" promise. `Z` exists because of
this; any future irreversible control needs its inverse designed at the same time.

**The header's edit bits had latched on.** `hdr.active` once carried a live tally, and when the
header was repacked to carry the projection and octave ratio downstream, the stale tally (10) was
still sitting in that field and got decoded as flags. Bit 2 is `F_EDITED`, so the focus was
permanently considered hand-moved and `focus_x` / `focus_y` silently did nothing — a dead control
with no error anywhere. The bits now ride inside `hdr.flags` encoded as `1 + hflags * 4`, so any
buffer written before the change decodes to `hflags = 0`.

**The lesson for a persistent buffer: repurposing a field is a migration, not a rename.** The old
value is still in every saved project, every preset and every undo step, and it will be read as
whatever the new code says that field means. Either version the layout or choose an encoding whose
old values decode to a safe default, as the `1 + n*4` above does.

---

## Node presets (project scope, narrow)

| Preset | Scope | Why |
| --- | --- | --- |
| `Arrangement — Shipped` (AX_Plan) | structural params + the full record buffer | the original arrangement, restorable in one action |
| `Arrangement — Drift Cabinet` (AX_Plan) | same | a second worked example |
| `Frame — Composed` | `frame_x`, `frame_y`, `frame_zoom` **alone** | the composed viewpoint. Nothing else in the project records it, so it is recoverable from nothing else. Saved as soon as the pose was chosen, not at the end |
| `Quality — Draft` | `levels`, `aa_samples`, `lod_scale` **alone** | 7 / 1 / 1.6 |
| `Quality — Live` | same | 11 / 1 / 1.0 — **the manifest default**, comfortable to work in |
| `Quality — Beauty` | same | 14 / 2 / 0.9 |
| `Quality — Hero` | same | 17 / 3 / 0.8 — **capture only** |

Recalling the camera does not disturb the look and recalling a rung does not disturb the framing.
That is the whole point of the narrow scope.

### `lod_scale` is a look control, not just a cost control

The obvious ladder buys quality by driving `lod_scale` down. **Do not.** Below about 0.7 the
fractal plates resolve so fine that the newsprint and houndstooth stop reading as *print* and
become grey grain — the image gets more expensive and worse. A rung at 0.45 was built, rendered,
and rejected on exactly that evidence.

So the ladder buys depth (`levels`) and edge quality (`aa_samples`) instead, and holds
`lod_scale` near 1.0. This is the "buy along the axis the image is about" rule: this image is
about legible print at a readable pitch.

### Measurements, and an honest caveat

End-of-chain cook rate, all four rungs measured in one sitting at 1280×720 with all three node
previews open:

| Rung | cooks/s | ratio to Live |
| --- | --- | --- |
| Draft | 73 | 1.27× |
| Live | 58 | 1.00× |
| Beauty | 61 | 1.07× |
| Hero | 61 | 1.07× |

**Read that as "no measurable difference", not as "Hero is free."** Beauty and Hero landing
*above* Live is noise. Hero does roughly 9× the per-pixel shading of Live and the throughput did
not move, which means the chain is **not shading-limited at 720p on this machine** — the cook
rate is pinned by something upstream of the shader. The rungs are real and visibly different in
the image; their *cost* is simply below what this method can resolve here.

Detailed Profiling is a UI-only preference with no state-tree path, so per-node CPU/GPU timing
could not be collected over MCP. These numbers are `framesProcessed` deltas over timed 10s
windows. Expect the top rung to bite at higher output resolution, where 9× the pixel work will
not stay free.

---

## AX_Ink: the surface is screen-fixed

Grain, misregistration and paper tone do **not** move with the fall, because they are the sheet
you are looking *through* rather than anything in the collage. That single decision is most of
what stops the result reading as a 3D flythrough.

Dot gain takes the **minimum** of a small neighbourhood rather than blurring — that is what ink
spreading physically does, and a symmetric blur just softens the image and loses the hard cut
edges that make a collage a collage. Each plate gets its **own** misregistration direction; a
shared axis reads as motion blur.

---

## What is proven, and what is not

**Proven live:**

- All three nodes healthy, `framesProcessed` climbing, no health reasons.
- The octave-boundary continuity, analytically and from a capture pair (`seam_a` / `seam_b`).
- Every `weave`, `lattice`, `facet_mode` and `ink_mode` value renders a distinct valid image.
- Both node presets recall cleanly (`applied[]` full, `skipped[]` empty).
- A 14s real-time motion clip of the fall at `fall_speed = 0.45`.
- The three flicker fixes, from the live preview.

**Not proven, and needing hand exercise:**

- **Every viewport gesture.** Injected input does not reach Module viewport events, so click,
  drag, `F`, `W`/`S`, `Q`/`E`, `K`, `M`, `P`, `X`, `N`, `R` and `C` could not be exercised over
  MCP. The maths behind them is shared with the canvas so a handle is drawn where it is grabbed,
  and buffer persistence and signature behaviour were verified — but **the gestures themselves
  need a human on the preview.** Worth checking first: dragging in the plate versus dragging in
  the ladder, since those are two different edits on one handle.
- Long-run drift. The loop is bit-exact by construction and was verified across one boundary; it
  has not been left running for hours.

## Files

```
axon_press.sentinel          the show
hero.png                     reviewed final capture (Beauty rung)
proof/                       graph, links, health, profile, capture, window — LOCAL ONLY
modules/_shared/axon.hlsli   contract, lattice projection, palette, editor geometry
modules/_shared/plates.hlsli the printed stock
modules/_shared/plan_theme.hlsli   vendored instrument palette
```
