# GPU Cloth And XPBD Modules

Reference for grid-based physics Modules in Sentinel. The worked implementation is
`projects/cloth_lab/modules/cloth_engine/`; its reusable pieces are bundled with
the project under `projects/cloth_lab/modules/_shared/` (`xpbd/xpbd.hlsli`,
`surface/bicubic.hlsli`, and `viewport/pick3d.hlsli`).

## The Single-Dispatch Solver

An iterative solver normally needs one dispatch per iteration, because a barrier
across thread groups is impossible in D3D11. That cost dominates a small
simulation. The way around it: make the whole system fit in ONE thread group.

- `thread_group_x: 1024` with `dispatch: [1, 1, 1]` is valid and compiles.
- Groupshared is capped at **32 KB per group**. Three separate `float` arrays for
  x/y/z avoid any `float3` stride padding: 2048 particles cost 24576 B.
- `GroupMemoryBarrierWithGroupSync()` inside a `[loop]` gives real per-iteration
  synchronisation, so every substep and every graph-coloured sweep runs inside a
  single dispatch.

Verified: 16 substeps x 3 sweeps x 12 barrier-separated colours = 768 sweeps in
**0.56 ms** on an RTX PRO 6000, including a 110k-vertex render pass.

**2048 particles is the practical ceiling** for this pattern. Above that, either
tile the domain with halos and accept one dispatch per tile-sync, or duplicate the
solve pass explicitly in the manifest and prove the synchronization boundary.

Coarse simulation plus a subdivided bicubic render surface is the right split.
A 64x32 sim renders smoothly at 3x subdivision; the extra 93k vertices cost
0.045 ms.

## Structured Buffers Do Not Ping-Pong

**The single most expensive thing to get wrong.** A simulation wants to read last
frame's state and write this frame's. For *texture* buffers Sentinel double-buffers
and flips. Structured buffers do not.

Declaring the same structured buffer as an `inputs:` entry (SRV) and as
`output: "buffer:x"` (UAV) on one pass is illegal in D3D11. The runtime silently
binds a **null SRV**, the shader reads all zeros, and a solver that treats zeros as
"uninitialised" restarts from rest every cook.

The symptom is specific and worth memorising: a perfectly static result, with mean
velocity sitting at exactly `gravity / framerate` — one frame of acceleration from
rest, forever.

**The fix**: give the pass no SRV input for that buffer and read/write the single
UAV. This is safe when every thread loads into groupshared and syncs before the
first store, which a group-local solver does anyway.

Other passes may read the buffer as an SRV normally; only same-pass SRV+UAV is the
problem.

## Compliance Must Be Calibrated Against Cumulative Effect

`alphaTilde = compliance / h^2`, and it only bites when comparable to the
constraint's inverse-mass denominator (~1-2). The trap: a constraint runs
`substeps * sweeps` times per cook, so cumulative enforcement approaches total
even when each application looks gentle.

At 16 substeps x 3 sweeps, 60 fps (`h^2` ~= 1.1e-6), for a curvature constraint:

| compliance | alphaTilde | per application | per cook (48x) |
|---|---|---|---|
| 1e-8 | 0.01 | ~100% | rigid |
| 1e-6 | 0.9  | 62%   | rigid |
| 1e-4 | 90   | 1.6%  | ~50% |
| 1e-3 | 900  | 0.17% | ~7%  |

Stretch should be fully enforced — that is inextensibility. Bending must stay
partial: past roughly 50% per cook the surface irons itself flat and stops reading
as fabric.

## Bending Must Be Sign-Aware

Do not implement bending as a distance constraint between 2-away vertices. That
constraint is **exactly satisfied by an inverted fold**: once a crease folds back
through itself the rest length still holds, the solver reports zero error, and the
crease locks permanently. The visible result is cloth that knots up and never
relaxes.

Constrain the **curvature vector** instead — how far the centre vertex sits off the
midpoint of its two neighbours. It has a single preferred state, so it always
pushes a fold open. `xpbd_curvature_delta()`.

Triplets need **three** colours on a grid (centres 1 *or* 2 apart share a vertex),
where distance families need only two.

## Long-Range Attachment

Local sweeps carry an anchor's influence about one row per iteration, so a sheet
hanging from few anchors stretches regardless of edge stiffness or substep count.
An inequality tying every vertex to its nearest anchor at the rest distance fixes
it in one sweep, needs no colouring (the anchor has infinite mass so only the free
vertex moves), and for a flat rest shape Euclidean rest distance *is* the geodesic
distance.

Measured, 32-row cloth, two-corner hang, settled from reset: **5.8% peak stretch
without, 1.6% with**.

Two ways to get it wrong, both of which produce a phantom crease that looks like
the cloth is tethered to a point it is not attached to:

- **Apply the bound against EVERY anchor, not the nearest one.** Selecting a
  single nearest anchor is discontinuous: with four corners, centre-line vertices
  are equidistant from left and right, the tie-break flips the chosen anchor
  across that line, and each half gets pulled toward a different corner. The seam
  reads as a hard fold, worst where two anchors are equally close. Every anchor is
  an independent valid inequality, so applying all of them is both more correct
  and continuous — and costs only a few extra projections.
- **Never let a rest-length scale TIGHTEN the cap.** It is a one-sided guard
  against reaching further than the material allows. Shrinking the cap converts it
  into an active inward pull toward the anchors. If a "tension" control shortens
  rest lengths, clamp the cap scale to `max(scale, 1.0)`: slack material may
  legitimately extend reach, taut material must not tighten it. Tautness belongs
  to the distance constraints, which already deliver it.

Useful sanity check for a rest-length scale `k`: spanning a fixed frame requires
mean tensile strain of exactly `1/k - 1`. At `k = 0.629` the measured mean strain
was 0.591 against a predicted 0.590, and `mean ~= max` confirmed the tension was
distributed evenly rather than concentrated in a crease.

## Collision Ordering And Friction

Two rules, both measured:

1. **Interleave collisions, do not append them.** Resolved only after the
   constraint sweeps, the stretch a projection introduces goes uncorrected for the
   whole substep. Resolve at the top of each sweep so the distance constraints
   absorb it, then once at the end so a substep cannot end inside a collider.
2. **Apply friction once per substep, in that final pass only.** Friction measures
   the tangential motion of the whole substep; applying it in every interleaved
   pass re-shaves the same displacement and compounds into glue. The cloth then
   stretches to conform to a collider instead of sliding across it. Measured on a
   sphere drape: **0.78% peak stretch applied once, 18% compounded.**

Iterate the collider set twice per resolution so a vertex caught between two
colliders can co-converge. A genuine pinch — two colliders closer than the cloth
thickness — remains unsatisfiable; with tearing enabled the fabric rips, which is
the physically sensible outcome.

## Measure Tensile Strain Only, And Skip Severed Edges

Two mistakes that make a strain readout lie:

- **`abs()` counts compression as strain.** Fabric buckles constantly; a sheet
  piling on a floor squeezes edges to a fraction of rest length and reports
  enormous "strain". Only stretch indicates tension, and only stretch should tear.
- **Severed edges must be excluded.** Once an edge tears its endpoints separate
  freely, so its strain grows without bound — it measured 1.77 after a few hundred
  tears and pinned the stress accent along every torn boundary permanently.

## Viewport Interaction

- Acquire a drag handle on a **raw button edge** (`type 2`, `code 0` for left),
  never on the drag **gesture** (`type 5`, `code 3`). The gesture carries no button
  identity, so an RMB camera-fly drag is indistinguishable from a left drag and
  will grab the scene while the user is flying.
- **Latch** the handle on acquire and hold until release. Re-picking each cook
  drops it under fast motion and on event-free cooks. A sweeping tool (a blade) is
  the deliberate exception.
- While held, recompute the target from the current pointer **every cook**, not
  only on cooks carrying events.
- **Do not read the wheel unmodified** — the host camera consumes it for dolly and
  fly speed, so one scroll does two jobs. Require a modifier and offer a key as a
  guaranteed alternative.
- `grabs`-style monotonic counters in the interaction record, exposed as a data
  output, are how you prove the gesture path works: state writes never exercise it,
  and injected input does not fire Module viewport events, so a real drag is the
  only proof. Read the counter afterwards.

## Draw Pass Gotchas

- **The draw target clears to transparent.** A pass that only draws geometry
  produces alpha-0 everywhere else, and captures read as white. Lay down an opaque
  backdrop with the first six vertices at `z = 0.99999` (inside the far plane so a
  LESS depth test accepts it).
- When several object classes share one draw pass and are distinguished by a flag
  in a vertex attribute, **test the flag values in descending order**. A `> 0.5`
  check written before a `> 1.5` check catches everything.
- Decide tear/visibility **per triangle**, not per quad. Killing a whole quad when
  any of its five edges tore doubles the effective hole size and reads as blocky
  chunks falling out.

## HLSL And Workflow Traps

- **`pass` is a reserved word.** So are `line`, `sample`, `texture`, `point`,
  `linear`, `half`.
- **X4026, sync in varying flow control.** A barrier may not follow a branch on
  per-thread data. Two working patterns: put the per-thread test *inside* the
  called function, and — if that function contains a loop — apply the test as a
  select on the return value rather than an early `return`, because an early return
  puts the following loop into varying flow and the barrier is rejected again.
- **HLSL does not guarantee short-circuit evaluation.** `if (x + 1 < W && buf[i+1])`
  can still issue the out-of-range read. Nest the conditions.
- **`fbm3D` takes an octave count** and returns roughly -1..1, not 0..1.
- **`compile_check` is offline.** It validates the directory, not the live
  pipeline. Editing only a shader (no manifest save) does **not** hot-reload the
  running node — call `force_reload`, or a measurement will describe stale code.
- **`force_reload` preserves live parameter values by name**, so new manifest
  defaults do *not* take effect on an existing node. Set them explicitly when
  verifying a recalibration.
- Aerodynamic force scales with patch area and so does patch mass, so **area
  cancels**: with uniform particle mass, folding an area factor into the
  acceleration makes wind orders of magnitude too weak.

## Proof Discipline

Settle before measuring. Several early conclusions here were wrong because the
sheet was still ringing from a parameter change or recovering from a previous
experiment; peak-strain readings of 63% and 110% were transients and unsettled
state, not solver defects. Reset, wait for mean speed to fall, then read.

Isolate with the metric, not the picture. Toggling one collider and re-reading
`max_strain` located every real defect above; none of them were diagnosable from
the render.
