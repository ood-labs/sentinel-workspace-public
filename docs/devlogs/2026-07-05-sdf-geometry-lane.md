# 2026-07-05 - SDF Geometry Lane: Raymarched 3D Objects + Instanced Scenes

## Context

Explored LLM-generated procedural 3D geometry after reading P3D-Bench (arXiv 2606.11152,
a benchmark for parametric CAD code generation with CadQuery/OpenSCAD targets). Key
takeaways for us: models score high on semantic/aesthetic alignment and weak on exact
dimensions in one-shot settings, and iterative agentic feedback loops are the biggest
lever. Sentinel already has the stronger version of their loop (compile_check, capture,
vision_eval, hot reload), and SDF raymarching makes precision structural: dimensions are
typed parameters feeding analytic primitives, so nothing depends on the model estimating
proportions in token space. CadQuery/mesh ingest was considered and deferred; the
raymarched lane needs no new engine features.

## What we did

- Ran two hero-object experiments in the sentinel dev repo (`shaders/projects/`):
  a flanged bracket from a paper-style dimensioned text spec (first-shot clean compile,
  10/10 spec fidelity from a Gemini vision judge, live restructure bolt_count 4→6) and
  a "fancy chair" (walnut/velvet/brass materials, curved slotted backrest; one lighting
  polish iteration). Both saved in `projects/sdf_geometry_experiments.sentinel` (dev repo).
- Built the workspace lane:
  - `modules/_shared/sdf/sdf_ops.hlsli` — sd_/op_-prefixed primitives, booleans,
    EXACT quarter-circle fillet union, chamfer, mirror/repeat transforms. Prefixed to
    never collide with the engine `sdf` feature library.
  - `modules/_shared/sdf/sdf_objects.hlsli` — `obj_sdf(p, kind, seed)` vocabulary:
    crate, column, chair, table, setback tower, arch, tree, lamp; shared local-space +
    bounding-sphere contract; seed-varied proportions.
  - `modules/_shared/sdf/sdf_shading.hlsli` — `sceneMap` prototype contract, tetrahedral
    normals, AO, soft shadow, sphere-trace helper, orbit camera, sun/shade helpers.
  - `modules/sdf_scene_render/` — the 3D sibling of `pl_render`: consumes the standard
    48 B PNode stream, maps canvas pos to a ground plane, kind/scale/rot modes matching
    pl_render conventions, per-pixel ray-vs-bounding-sphere shortlist culling
    (MAX_LIST 24, render_count cap 96), sun soft shadows via a second shadow-ray
    shortlist, AO, per-instance tint, emissive materials, fog, dual camera rig.
- Live proof: `pl_grid → sdf_scene_render` produced a café floor (Grid 6x4, Cycle
  chairs/tables) and, with parameters only, a dusk city (Scatter 96, Hash over
  towers/trees/lamps, low sun, fog). Healthy at ~43 fps at 720p with shadows while a
  StreamDiff node shared the GPU (graph profiler, RTX 5090).
- Documented: `procedural-geometry-authoring` skill (.claude + .agents), a
  "3D object geometry (SDF raymarch)" section in `knowledge/technique-catalogue.md`.

## Gotchas hit

- A `force_reload` that added `features: [camera]` to a live module killed Sentinel with
  an unhandled C++ exception (0xe06d7363, WER dump `sentinel.exe.383904.dmp`). Not yet
  root-caused; the skill recommends destroy+recreate for camera-feature modules. Needs a
  dev-repo investigation session.
- A second app death had no WER event and coincided with a concurrent agent session
  working in the same Sentinel instance (its Phase 70 StreamDiff node appeared in our
  graph; likely a taskkill before rebuild). Multi-session collisions on one running app
  are real; check `sentinel_app status` pid ownership before blaming code.
- `sentinel_capture capture_at` rejects `overrides` serialized as a JSON string (same
  bug class Phase 69.A fixed for `sentinel_state set_many`). Workaround: set_many +
  capture + restore. Should be fixed in the dev repo MCP server.
- `set_many` cannot write a `point2D` as an array; use the `_x`/`_y` component paths.

## Next

- Sub-agent benchmark: hand a fresh agent only the skill + a dimensioned spec, measure
  iterations-to-pass. That calibrates what the skill is still missing.
- Depth output from `sdf_scene_render` (float port) for true cross-node 3D compositing.
- Streets/interiors recipe pass: `pl_path` chains with FromDir yaw, multiple record
  chains merged upstream into one scene render.
- Field-driven cities: sample `field_gen` elevation into tower heights (needs a texture
  data input on the scene renderer or a bake into PNode weight upstream).
