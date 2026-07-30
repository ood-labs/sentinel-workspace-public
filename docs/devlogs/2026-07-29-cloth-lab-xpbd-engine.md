---
type: devlog
date: 2026-07-29
phase: examples
subphase: cloth-lab-xpbd-engine
status: complete
approval: approved
summary: "Built the Cloth Lab XPBD cloth engine with kick-driven strikes, extracted reusable xpbd/bicubic/pick3d headers, and made audio_bands the documented audio source of truth"
note_created: true
updated: 2026-07-29
---

**Goal**

Build a best-in-class real-time cloth simulation in Sentinel with a real
manipulation interface, then make the reusable parts reusable and the workspace's
audio-reactivity story unambiguous.

**Work Done**

- Authored `modules/cloth_engine/` — a four-pass Module (interact, solve, measure,
  mesh) running a full XPBD cloth solver inside ONE dispatch: 1024 threads, 2048
  particles resident in groupshared, every substep and graph-coloured constraint
  sweep separated by `GroupMemoryBarrierWithGroupSync()`.
- Constraints: distance (structural + shear), sign-aware curvature bending,
  long-range attachment, sphere/plane collision with friction, tearing with
  per-vertex broken-edge bitmasks, and a soft brush-weighted grab.
- Aerodynamics: per-vertex pressure proportional to the square of the wind
  component along the surface normal, which is what makes the sheet flap rather
  than sag. Gust/turbulence from `fbm3D`, evaluated once per cook.
- Render: Catmull-Rom bicubic surface over the sim grid (3x subdivision, analytic
  tangents), two-sided wrapped-diffuse shading, curvature crease darkening,
  hemisphere ambient, weave contour lines, registration line on the anchored edge,
  brush cursor in rest space, vignette.
- Viewport interaction: internal camera + events on one node, ray pick with a
  groupshared min-reduction, latched grab handle, Grab/Cut tools, keyboard reset.
- Audio drive: `cloth_audio` (Audio In) -> `cloth_bands` (`audio_bands`) -> engine
  by EXPRESSION on `kick_count`. Each kick fires one velocity impulse at a random
  interior vertex; the taut sheet rings outward through the solver itself.
- Extracted `modules/_shared/xpbd/xpbd.hlsli`,
  `modules/_shared/surface/bicubic.hlsli`,
  `modules/_shared/viewport/pick3d.hlsli` and refactored the engine onto them,
  verifying identical output.
- Wrote `knowledge/gpu-cloth-and-xpbd.md`; rewrote the head of
  `knowledge/audio-reactivity.md` to make `audio_bands` the source of truth;
  synced the audio note and the new knowledge reference into all three entry
  manuals (CLAUDE/AGENTS/GEMINI).
- Flipped `audio_bands` `adapt_mode` default to Fixed.
- Packaged `projects/cloth_lab/` with README, bundled modules, `Kick Strike
  Membrane` project preset, and allowlisted it in `.gitignore`.

**Decisions Made**

- **Solver + renderer + interaction live in ONE module.** Splitting them would put
  the grab (which needs the camera ray) upstream of the solver and downstream of
  the renderer — a graph cycle. Also the internal-camera contract's own example.
- **Audio telemetry flows by expression, not a data link**, for the same
  acyclicity reason.
- **Drive discrete events from a monotonic counter, not an envelope.** Unambiguous
  edge, no threshold to tune, cannot re-fire during decay, and a large counter jump
  fires once rather than bursting.
- **Bending is a curvature constraint, never a 2-away distance constraint.**
- **Bending default kept deliberately low (0.08).** Above ~0.3 it irons the sheet
  flat.
- Kept the `rupture_*` modules untouched; the physics core needed replacing, not
  extending.
- Did NOT delete the superseded audio modules — all but `cryo_pulse_baseline` are
  referenced by saved projects, including `streamdiff_brush_canvas`. Solved the
  confusion through documentation instead.

**Approvals & Locks**

- User confirmed the look ("this looks fucking crazy, it's dope").
- User confirmed grabbing works correctly in the live viewport, closing the last
  unverified gate — injected input cannot fire Module viewport events, so this
  needed a human.
- User approved `audio_bands` as the only beat detector to build on.
- Packaged state locked as the `Kick Strike Membrane` preset.

**Issues Encountered**

- Structured buffers do not ping-pong. Same-pass SRV+UAV nulled the SRV, the
  solver read zeros and restarted from rest every cook.
- Compliance ranges were calibrated per-application instead of against the
  `substeps * sweeps` product, so bending was first nearly inert, then total.
- Friction applied in every interleaved collision pass compounded into glue.
- Strain metric used `abs()` (counting compression) and included severed edges.
- `rest_scale` shrank the long-range cap, turning a guard into an inward pull; the
  nearest-anchor tie-break then produced a phantom centre-line tether.
- Grab acquired on the drag gesture, which carries no button identity, so RMB
  camera-fly grabbed the cloth.
- `compile_check` is offline; several measurements described stale shader code.
- `pass` is an HLSL reserved word; X4026 rejects barriers after per-thread branches.

All are written up in `docs/lessons.md` and `knowledge/gpu-cloth-and-xpbd.md`.

**Runtime Proof**

Settled from reset, RTX PRO 6000:

- Banner in wind, top edge pinned: 2.5% peak tensile strain
- Sphere drape: 0.78%; `min_clearance` exactly `cloth_thickness` (zero penetration)
- Free fall: 0.012%
- Long-range attachment A/B: 5.8% peak stretch off, 1.6% on
- `rest_scale` cross-check: at 0.629, predicted mean strain `1/k - 1 = 0.590`,
  measured 0.591, with `mean ~= max` confirming even distribution
- Cost: 0.56 ms GPU for 16 substeps x 3 sweeps x 12 constraint colours plus a
  110k-vertex render pass
- Stable at `stretch_stiffness` 1.0 with only 2 substeps (no explosion)
- Grab path verified by `grabs` counter reaching 224 through real user input

**Remaining Work**

- Snare behaviour: a lateral shear or edge-slap, so it reads as a different gesture
  from the kick's poke.
- Optional: scale `strike_gain` by the `kick` envelope for hit dynamics.
- Optional: strike queue — currently one strike per cook maximum.
- Optional: self-collision via a groupshared uniform-grid hash.
- Grid size is still compile-time 64x32; making it a real parameter was scoped out.
- `cryo_pulse_baseline` is the one unreferenced superseded audio module, safe to
  delete if desired.

**Cross-References**

- Example: `projects/cloth_lab/` and its `README.md`
- Engine: `modules/cloth_engine/`
- Shared: `modules/_shared/xpbd/`, `modules/_shared/surface/`,
  `modules/_shared/viewport/`
- Knowledge: `knowledge/gpu-cloth-and-xpbd.md`, `knowledge/audio-reactivity.md`
- Detector: `modules/audio_bands/`
- Prior devlog: `docs/devlogs/2026-07-29-streamdiff-laser-etch-checkpoint.md`
