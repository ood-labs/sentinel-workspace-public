---
type: devlog
date: 2026-07-05
session_start: "16:30"
session_end: "19:20"
phase: industrial-lattice
subphase: texturing-lighting-postfx
status: complete
approval: approved
summary: "Finish steel_lattice: layered grime, camera-headlamp lighting, B&W bloom post, SSAA"
note_created: true
updated: 2026-07-05
---

**Goal**

Bring `steel_lattice` home — add surface texturing, lighting and post-FX to land the
decayed B&W concrete-factory reference, then refine (especially anti-aliasing).

**Work Done**

- **Reusable noise header** `modules/_shared/sdf/sdf_noise.hlsli` (invent/harvest):
  `sd_hash31`, `sd_vnoise3`, `sd_fbm3`, `sd_triplanar_fbm`, plus `sd_ridged3` (turbulence
  for cracks) and `sd_fbm3_warp` (domain-warp to break the value-noise grid).
- **Texturing** (in `steel.hlsl`, shade-time): layered weathered concrete —
  macro triplanar staining → meso mottle → fine pitting → ridged cracks →
  domain-warped sharpenable drip-streaks → recess grime → worn edges. 8 live `Surface`
  controls (Detail Scale, Grime, Fine Detail, Streaks, Streak Sharp, Cracks, Spalling,
  Edge Wear).
- **Lighting**: replaced the sun key with a **camera headlamp** — light at the active ray
  origin `ro` (correct in fly AND orbit), distance falloff + torch cone, everything fades
  to pure black. `Light` group (Spot Intensity/Falloff/Cone, Ambient, Sun Fill).
- **Post-FX** (two-node graph): `steel_lattice` now outputs linear HDR (`working_format:
  RGBA16F`, inline grade removed) into the reused `industrial_mono_post` filter →
  Vogel-spiral bloom + full mono grade (`saturation 0`), vignette, film grain. Wired via
  `set_input`.
- **Anti-aliasing**: refactored `main` into `shadeRay(uv)` + an NxN jittered supersample
  loop (`AA Samples`, 1–8). Distance-fades high-freq surface detail to stop far shimmer.
  AA 3–4 holds ~60 fps/720p on the 5090 (SSAA is nearly free here).
- Baked the user's fully dialed-in values into the manifest defaults (Detail Scale 7.73,
  subtler grime, cell 6, AA 4, headlamp/fog tuning) and dropped 3 now-dead params
  (`bg_color`, `desaturate`, `exposure`). Saved `projects/industrial_lattice/
  industrial_lattice.sentinel` (both nodes + link + post tuning).
- Harvested `sdf_noise.hlsli` + the `steel_lattice` infinite-lattice technique into
  `knowledge/technique-catalogue.md`.

**Decisions Made**

- Diverted from a 2-pass-in-one-module post to a **two-node graph** (`lattice → post`),
  reusing `industrial_mono_post` — matches modular-scene-authoring's finish-post pattern
  and keeps grime/light tuning as live params (no rebuild).
- Headlamp light anchored to `ro`, not `_CameraPos` (latter is stale in orbit mode).
- SSAA over TAA/FXAA: simplest, fixes geometry edges + shading noise, and cheap here.

**Approvals & Locks**

- User: "this is sick we fucking did it" — final look approved and baked as defaults.

**Issues Encountered**

- **`carveGrooves` silent no-op** (grooves round 1): the near-surface `shell` term was
  `max(d, -d-depth)`, which is 0 exactly at the surface, so the cutter never bit where the
  ray stops — carving only affected interior points the ray never visits. Fixed with a
  `+eps` bridge so the cut region straddles the surface (`shell = max(d-eps, -d-depth)`).
  Took several identical captures to spot (looked like a stale/cached render).
- **Camera-module rebuild wipes live params**: every shader/manifest edit needs
  destroy→recreate (hot-reload crashes — bug #41), which resets all params to defaults.
  Nearly lost the dialed-in look twice; mitigated by `get_pipeline_info` read-back + bake.
  Filed as bug/enhancement **#44** (preserve param state across reload).
- **Orbit default framing mismatch**: baked `cam_distance 9` (tuned for old cell 3.631)
  renders black at cell 6 — camera lands in empty/occluded space. Fly (the default mode)
  is unaffected; orbit users just pull distance back.

**Next Steps**

- Optional refinements offered but not taken: glossier metal spec on hardware vs matte
  concrete, deeper contact shadows, grade/highlight-rolloff polish, gusset brackets.
- If revisited, fix the orbit `cam_distance` default for cell 6, and consider per-material
  spec.

**Cross-References**

- Prior: [[2026-07-05-steel-lattice-grooves]]
- Skills: modular-scene-authoring, procedural-geometry-authoring, module-authoring
- Catalogue: `steel_lattice`, `_shared/sdf/sdf_noise.hlsli` entries
- Bugs: #41 (camera hot-reload crash), #44 (reload wipes params)
