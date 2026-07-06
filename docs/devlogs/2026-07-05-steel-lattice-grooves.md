---
type: devlog
date: 2026-07-05
phase: industrial-lattice
subphase: grooves-and-camera-fix
status: in-progress
summary: "Fresh infinite steel lattice + real carved formwork grooves; fly-cam fix harvested to skill/template"
---

**Done**

Restarted the industrial steel scene from scratch as one clean module `modules/steel_lattice/`
(the earlier `industrial_steel_greebled` build got too complex and stalled on camera). Core:
an INFINITE structural lattice — vertical columns + X/Z beams — via pure domain repetition
(`rep1(x,c) = x - c*round(x/c)`), unioned into one raymarched SDF. Cheap (~59 fps, 720p),
truly endless, orbit + fly camera.

Camera feature fix (harvested): the live fly camera drives only `_CameraPos`/`_InvViewProjMatrix`
— the `camera_pos_x/y/z` StateTree params do NOT move it. Root-caused the "locked to orbit /
fly does nothing" complaint: templates defaulted to the orbit branch (discarding the viewport
camera) and used the unreliable `_RayDirection` helper. Fixed steel_lattice to a `cam_mode`
enum `[Fly, Orbit]` default Fly, unprojecting through `_InvViewProjMatrix`, and rolled the same
fix + rules into `procedural-geometry-authoring` + `module-authoring` skills and the
`sdf_scene_render` template. Also fixed a `t > 0` → `t >= 0` march bug (camera-inside-geometry
blacked the frame).

Formwork panels as REAL carved geometry (not a normal-map bump — that was rejected): grooves
subtracted in `sceneMap` via a 1-Lipschitz cutter = (thin slot on a world panel grid) ∩
(near-surface slab with a +eps bridge so the cut reaches the surface — the eps was the bug that
made a first attempt a silent no-op). Sculpting kit: `panel_w/h` scale, `Offset X/Y/Z`,
independent `Flute Width/Depth (V)` + `Band Width/Depth (H)`, `Edge Round`, distance-LOD to
fade far detail. Proof captures under `projects/industrial_lattice/captures/` (grooves_v3,
sculpt_v1).

Gotcha reconfirmed + reported: editing a `features:[camera]` module's shader while the pipeline
is loaded hot-reloads and hard-crashes Sentinel (bug tracker #41, duplicate). Discipline:
destroy → edit → recreate.

**Next**

Pass 2 — junction hardware: guard-banded gusset plates + haunches + bolt rows at the beam↔column
nodes. Then optional major/minor groove tiers, groove bevel, panel-recess mode. Harvest the
lattice + carved-groove technique into `knowledge/technique-catalogue.md` at session close.
