---
type: devlog
date: 2026-07-26
phase: 3
subphase: 3E
status: in-progress
approval: pending
summary: "Gizmo Desk v3 rebuilt on the sui3 kit with lit raymarched solids; host pick/shift-extend proven over MCP, multi-selection orbit proven numerically and visually"
---

# Phase 3E - Gizmo Desk

## Done

`modules/gizmo_desk/` (live node `Gizmo_Desk`), the fourth v3 station. The transform layer IS the
contract, so `types.hlsli`, `descriptors.hlsl`, `pick.hlsl`, `snapshot.hlsl` and the whole v1
transaction model (handle armed at mouse-down, capture retained through the drag, rendered pivot as
the transaction source) were preserved; the interaction toolbar and the renderer were rebuilt.

| # | Criterion | Result |
| --- | --- | --- |
| 1 | Hands-on transform pass | **PARTIAL - drag deferred to 3F.** Click-select and shift-extend are proven over MCP: `pick` at object 1 then `modifiers: 1` at object 2 returns `ids [1, 2]`, `source: User`, and the shader's `selection_mask` control output reads `3.000000`. The pointer drag on the gizmo is not provable - see below |
| 2 | Multi-selection shares one pivot | Two objects selected, +40 deg about Y: object 1 `(-2.175, -1.25, -0.200) -> (-2.092, -1.25, 0.298)` and object 2 `(-0.725, -1.25, 0.070) -> (-0.808, -1.25, -0.427)`, each rotation.y +40 exactly. They swing to opposite sides of the shared midpoint, matching the closed-form prediction to 4 decimals. Before/after capture pair shows the sphere receding and the box advancing. A -40/+40 round trip returns **bit-identical** values |
| 3 | Durable transforms survive save/close/reopen | SHA-256 over all 16 `Scene Objects` records identical (`3e4309014f538958`) across save -> new project -> reopen, carrying the orbited transforms, not the seed |
| 4 | v3 language; axis colours the only chroma besides amber | Hue audit of the live frame: **2614 chromatic px (0.23%)** - amber 878, axis red 315, axis green 565, axis blue 793, and **63 px off-palette (0.0057% of frame), 100% of which sit within 2px of a palette hue**, i.e. antialiasing blends at ring crossings and glyph edges. No independent hue |
| 5 | Criterion 4 at both extents; validate clean | Legible at 640x360, 1600x900 and 1920x403. `module-ui.ps1 validate`: `OK Gizmo Desk (2 controls)` |

Cost: **3.30 ms** median wall time (7 samples, 3.23-4.06).

## The reversal: these are lit solids, not outlines

The twelve objects were first rendered as flat screen-space silhouettes - ring, square, diamond,
brackets - on the reasoning that kind-as-shape kept them distinguishable without colour. The
operator rejected that on sight, and correctly: **a transform gizmo is only judgeable against shaded
geometry.** A rotation is invisible on a flat outline, and so is a non-uniform scale. The renderer
now raymarches the same SDF v1 used, with one key light, a dim opposing fill, a silhouette rim,
specular, and soft shadows against the objects. The floor is a real lit plane carrying the
measurement grid in world space, so it recedes with perspective instead of lying over the image as
graph paper. Shading is strictly greyscale, which is what keeps criterion 4 intact.

## Defects found and fixed

- **Missed rays printed black pixels at every object centre.** Testing `abs(d) < 0.0018` against a
  fixed `0.004` step floor: a ray that overshoots lands *inside* at `d = -0.004`, keeps adding the
  floor, and marches deeper forever. The hit epsilon is now distance-relative and the test is
  `d < eps`, so crossing the surface counts as a hit. Measured by counting isolated near-black
  pixels surrounded by lit neighbours: **many -> 2 of 1,112,375**.
- **The amber selection rim was drifting to yellow.** Added at 1.55 gain onto an already-lit body,
  the red channel clipped first and the hue slid to 60 deg. Blending toward amber instead of adding
  cut off-palette pixels from 137 to 63 and put the remainder entirely on antialiasing edges.
- **Self-shadow banding** - concentric rings around the lit pole of every sphere, because the
  shadow ray started at `t = 0.05` and sampled its own surface at near-zero distance in `10*d/t`.
- **The numeric orbit read `drag_snapshot`, not the live scene.** In `update.hlsl` `_Tex1` is the
  drag origin, which is correct for the continuous re-application a drag performs and wrong for a
  discrete edit. Same class of mistake as 3D's snapshot ordering bug, opposite direction.
- **Title sat 1px off the bank frame at 1600x900.** `gdCapFits` demanded 12px for an 11px glyph
  run; now 15px, which is clearance rather than a coincidence.

## Decisions

**Transform mode is one `int` parameter on a three-cell bank, not three `type: button` controls.**
A mode is a mode: backing it with an ordinary parameter gets undo, presets, project save and OSC,
and sidesteps the one-way button latch 3C measured entirely.

**A numeric-transform door (`do_orbit` / `orbit_axis` / `orbit_degrees`).** Every 3D tool has exact
numeric entry beside its gizmo, and this is also the only way to transform the selection without a
pointer, so it is what criterion 2 goes through - and what OSC and Conductor cues would go through.
It orbits about the *same* shared pivot the drag uses, so it exercises the real code path rather
than a parallel one.

## The gesture gap is narrower than 3D recorded

3D's devlog says "no MCP call can click inside a module preview." That is now known to be too
broad. For a module declaring a `selection` interaction, `sentinel_viewport action=pick` drives the
host's real asynchronous pick, and the resulting selection reports `source: User` - it is not a
side door. Click-select, shift-extend, and clear are all reachable.

What is **not** reachable is the drag. `sentinel_viewport action=edit` returns
`Error: Could not begin edit` for this module at every coordinate tried, with and without an
explicit `phase`, because `edit` drives the host's object-edit transaction and this module renders
and drives its own gizmo from raw viewport events. Both paths are legitimate; they are just not the
same path. The pointer-drag half of criterion 1 batches into 3F's hands-on pass.

Note also that object screen coordinates are camera-dependent, and the camera is user-operable - a
hard-coded pick coordinate silently stops hitting after the operator orbits the view. The probe now
sweeps a grid to locate an object id before clicking it.

## Known limit, carried forward

Host control rects are static normalized, so the toolbar's hit regions scale proportionally with
the panel and fall under the 32px minimum below roughly 1000px wide. Recorded in the phase doc's
Amendment 3; unchanged here.

## Next

3F: consolidation, presets, the batched hands-on interaction pass (3B.3 hover, 3D criterion 1, and
3E's gizmo drag), clean-checkout proof, and retiring the v1 nodes.
