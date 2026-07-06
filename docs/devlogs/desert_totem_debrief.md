# Desert Totem — Build Debrief

*Project: `projects/desert_totem` · branch `wip/desert-dada-totem` · Sentinel 0.5.16 (dist),
RTX 5090 / sm120 / driver 610.62, Windows 11.*

A surrealist Dada assemblage painting (a totem of primitive painted solids on a plank in a
desert) recreated as **real-time procedural 3D** — then pushed into a deep, drivable
distortion toolkit. Two generations:

- **v1 — monolithic hero assemblage.** ~40 hand-placed SDF primitives in one `sceneMap`,
  single raymarch pass, procedural materials, `post` grade + `signal` motion. Reference-match
  88/100, "excellent" turntable. (`modules/dada_totem`, commit `d670ae9`.)
- **v2 — data-driven + distortion.** The arrangement externalized into structured-buffer
  records authored by generator nodes, marched by a forked renderer, with a full domain-warp
  toolkit on top. (`dada_layout`/`dada_scatter`/`dada_render`/`dada_control`, commits
  `40172ed`→`ff64361`.)

---

## The headline technique (reuse this everywhere)

**Look at an image → build *all* of its geometry as procedural raymarched SDF primitives →
externalize the arrangement as data → warp the entire distance field.**

Why it's stupidly powerful:

1. **No meshes, no assets, no DCC round-trip.** Every object is math. Every dimension is a
   typed parameter, so edits are instant and exact. A crescent moon is `sphere − offset
   sphere`; a beach ball is a sphere with an angular gore material; a turned baluster is a
   stack of lathe-like primitives. You author a whole still-life vocabulary from a text/image
   read (`modules/_shared/sdf/sdf_dada.hlsli`).
2. **One depth domain.** Because the whole scene is a single signed distance function, you get
   real occlusion, sun shadows, AO, and a fly-camera for free — and you can compose dozens of
   objects into one coherent pass.
3. **The arrangement is data.** Each object is a 64-byte `DadaPart` record (pos / scale /
   3-axis rotation / kind / material / params) in a structured buffer authored by a compute
   node. So placement is externally drivable — reshuffle, spread, explode, jitter, or drive it
   from OSC/expressions — without touching the renderer.
4. **The warp is the magic.** Because it's *all one distance field*, a domain warp applied
   before evaluation **melts / twists / shatters the entire scene coherently** — sculpture,
   shelf, plank, and scattered accents all deform together as one material. This is the
   mind-blowing part and the thing worth building on: **procedural SDF scene + domain
   distortion is a complete generative-art engine in one shader.**

This pipeline is now a reusable capability, not a one-off. Expect to use "SDF-from-reference +
warp" as a core technique going forward.

---

## The warp toolkit (the star of the show)

Everything lives in `dada_render`'s `domainDistort(p)` (geometry) and the shading tail
(surface), each op gated by its amount so it's free when off.

### 3-slot warp stack
Three independent warp fields, summed under a master **Melt**, each with:

- **Mode** (7): flowy — *Flow · Ripple · Turbulent · Fractal*; rectilinear — *Steps* (terraced),
  *Boxes* (soft square-wave plateaus), *Shatter* (per-grid-cell constant hash offset → cubist
  block displacement).
- **Freq / Speed**, **Yaw + Pitch** (orient the field in any direction), **Offset X/Y/Z**.
- Sampled in its own rotated/offset frame, returned in world orientation — so layering three
  differently-oriented fields (e.g. slow Flow up the tower + fast Ripple across it + Shatter at
  an angle) gives rich multi-directional warp instead of one uniform wobble.

### Geometric deform ops
Twist (spiral by height), Bend (arc), Swirl (radius-falloff vortex), Sag (affine gravity
droop), Wave (sinusoidal ripple), Pinch/Inflate (radial), Mirror (Radial kaleidoscope /
MirrorX), plus a distortion **center** (x/y/z) that moves the pivot for twist/swirl/pinch.

### Surface ops
Painterly (+scale) hand-made normal/albedo noise, Facet (low-poly normal quantize), Wobble
(animated shimmer), Hue Shift (rotate the palette up the tower).

### The two load-bearing tricks
- **Lipschitz safety factor.** A domain warp `p + A·f(p)` inflates the distance gradient, so a
  naïve sphere-tracer overshoots and punches holes. `distortLip()` sums every active
  distortion's strength and multiplies the returned distance by `1/(1 + Σ strength)` — the
  marcher under-steps exactly enough to stay artifact-free. **This is the key to stable
  warped-SDF rendering.**
- **Distortion partitioned by type** (a Plan-agent pressure-test finding): a global `p`-warp
  breaks per-pixel bounding-sphere culling, so v2 **dropped the shortlist** for brute-force +
  a cheap 1-D height-band reject (the v1 monolith proved ~40 primitives run at 60 fps
  unculled). Radial fold is applied to the ray/point *before* the loop (stays valid); sag is
  affine (bounds preserved); painterly is shading-only (never touches the field).

---

## Architecture (v2)

```
dada_control ─┐  (master macros: melt/sag/spread/explode → control outputs)
signal ───────┤  (LFO bus)
              ↓  ref() expressions
dada_layout ──┐  (compute → StructuredBuffer<DadaPart>: the totem, ~33 records + arrange xforms)
dada_scatter ─┤→ dada_render ──▶ post ──▶ out
              │  (compute → DadaPart: scattered accent field)
              │
   _shared/sdf/{sdf_ops, sdf_extras, sdf_dada, sdf_shading}.hlsli
```

- **`sdf_dada.hlsli`** — 12-kind object vocabulary (sphere/box/cone/disc/hoop/crescent/lens/
  beachball/baluster/bowl/harlequin/rod) with local-space gore/stripe/checker sub-materials.
- **`dada_render`** — brute-force + height-band raymarch of two `DadaPart` buffers, a hardcoded
  armature + wires (a 14×-tall spine as a scaled unit-object would step-starve the marcher, so
  the frame stays hardcoded), a once-per-pixel `shadeSample` for object materials, the full
  distortion toolkit, a procedural desert-mountain horizon + heat-haze + photo-collage inset,
  and a fly/orbit camera. 760×1140, ~60 fps with distortion on.
- **Generator previews render a real front-view *layout map*** (each record → a placed disc)
  so the node shows the arrangement you're authoring, not an opaque debug strip.

---

## What worked (decisions that paid off)

- **Design-first + a Plan-agent pressure-test** before the v2 rebuild caught two would-be
  dead-ends: drop the ray-sphere shortlist (defeated by a vertical stack), and keep the
  armature hardcoded. Both were correct.
- **Parity checkpoint before distortion** — proved the data-driven rebuild reproduced v1 at
  9.5/10 (`vision_eval`) before layering effects, so any later regression was obviously the
  effect, not the port.
- **`vision_eval` as an objective critic** in a tight capture→eval loop (72→88 on v1, plus
  motion/parity checks) kept the composition honest.
- **Externalizing the arrangement into data** made "drive it from outside" real — one
  `dada_control` slider explodes/reshapes the whole scene.

---

## Crashes & gotchas (hard-won — see bug reports)

1. **Camera-feature hot-reload crash.** Editing a live `features:[camera]` module's shader
   files triggers the file-watch recompile, which crashes the app. Workaround adopted for the
   whole build: **destroy the node before editing, recreate after.**
2. **GPU TDR on heavy distortion.** A melt-heavy raymarch frame (many primitives × ~10×
   normal/AO/shadow re-entry × warp) exceeded the driver watchdog and the app *exited* rather
   than recovering. Mitigations: march steps 200→140, render resolution 900×1350→760×1140, and
   the Lipschitz under-step. Stable after.
3. **Slow first compile.** Large compute shaders take 40–60 s in fxc on first build (cache
   miss); the shader cache makes subsequent identical builds instant. The MCP `compile_check`/
   `compile_status` 5 s IPC timeout is far shorter than the compile, so it returns a
   misleading `Timeout` while the compile is actually progressing.
4. **`sentinel_state set_many`** failed through this MCP client ("Missing 'values'"); single
   `set` calls worked. (Serialization mismatch.)
5. **Post output-format warning** — a module whose final pass resolves to RGBA16F while the
   pipeline output is BGRA8 logs a forced-downcast warning; worth an explicit `output_format`
   or a clearer authoring hint.

---

## Improvement suggestions

### MCP tooling
- **Async / longer compile calls.** `compile_check` and `compile_status` should not sync-block
  on a 5 s IPC deadline when fxc can run 40–60 s. Either bump the deadline for compile calls,
  or make them return a job handle immediately and stream progress (the async `create` path
  already does this better — `compile_check` should match).
- **Fix `set_many`** serialization (batching camera/param writes one-at-a-time is slow and, on
  a fragile heavy shader, more IPC round-trips = more chances to hit a spike-crash).
- **A guarded "edit live module" path.** Since editing a camera-feature module's files crashes
  the app, an MCP action that safely destroys→edits→recreates (or hot-swaps behind a barrier)
  would remove the biggest footgun in this workflow.
- **`capture_data_port` was excellent** — keep and extend it; proving buffer contents before
  wiring saved real debugging.

### Sentinel
- **GPU watchdog resilience.** A single expensive compute frame should not exit the whole app.
  Catch the device-removed/TDR, drop the offending pipeline to an error state, and keep the app
  and the rest of the graph alive (the way a compile error is handled).
- **Camera-feature hot-reload stability** — reloading a `features:[camera]` module should not
  crash; this forced destroy+recreate on every iteration of a long build.
- **Frame-time / cost guardrails.** An optional per-pipeline "max frame ms" or adaptive
  step/resolution fallback would let heavy authored shaders degrade gracefully instead of
  TDR-ing. A live cost/step-count readout in the module panel would help authors stay under
  budget.
- **Clearer output-format authoring.** Auto-insert or warn earlier when a float final pass
  meets an 8-bit output, with a one-click "add `output_format`" fix.

---

## Reusable techniques harvested (in `knowledge/technique-catalogue.md`)

- **`sdf_dada.hlsli`** — Dada/still-life SDF object vocabulary (kind-indexed).
- **`sdf_extras.hlsli`** — `sd_bezierTube` (spline sweep) + `obj_baluster` (turned finial).
- **Data-driven SDF assemblage** (`DadaPart` buffer + generator/renderer split) with
  layout-map previews and a macro control node.
- **Domain-distortion warp toolkit** — the 3-slot warp stack + geometric/surface ops + the
  Lipschitz-safety pattern. *The most valuable single technique from this build.*
