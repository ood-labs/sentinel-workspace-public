---
name: procedural-geometry-authoring
description: Author real-time 3D geometry in Sentinel as raymarched SDF Module nodes — parametric objects with exact dimensions (furniture, machine parts, architecture, props) and instanced 3D scenes (rooms, plazas, cities) driven by the PNode layout kit. Use when a scene needs actual 3D objects rather than flat atlas stamps, when building a single hero object from a text spec with precise dimensions, when populating a ground plane with many placed/cloned/arranged objects via pl_grid/pl_spawn/pl_path chains feeding sdf_scene_render, or when extending the shared object vocabulary in modules/_shared/sdf/. Covers the sceneMap contract, exact-fillet CSG ops, per-pixel ray-sphere shortlist culling, kind/scale/rot mapping modes, the compile_check→create→capture→vision_eval verification loop, and camera rigs (deterministic orbit + fly cam).
distribution: true
---

# Procedural Geometry Authoring (Raymarched SDF Modules)

Build real 3D geometry as compute-shader raymarch Modules. There is no mesh anywhere:
an object is a signed distance function, so every dimension is a typed manifest parameter,
edits are instant (no rebuild), and booleans/fillets are one-liners. Two patterns:

1. **Hero object module** — one module renders one parametric object from a spec
   ("a flanged bracket, plate diameter 3.0, four bolt holes on a 1.05 bolt circle").
   Precision is structural: the CSG expression is written once and the dimensions come
   from parameters, so a 0.5-diameter hole is exactly 0.5 world units.
2. **Instanced scene** — `sdf_scene_render` consumes a PNode placement buffer and stamps
   a kind-indexed object vocabulary onto a ground plane with sun shadows, AO, and fog.
   Any layout-kit chain (`pl_grid → pl_spawn → pl_path`) becomes a room, plaza, or city.

For manifest/HLSL mechanics use `module-authoring`; for graph decomposition and the
design-first workflow use `modular-scene-authoring`. This skill covers the geometry lane.

## Shared library (modules/_shared/sdf/)

Include order matters, and none of the headers nest includes:

```hlsl
#include "../_shared/sdf/sdf_ops.hlsli"      // primitives, booleans, transforms, hashes
#include "../_shared/sdf/sdf_objects.hlsli"  // kind-indexed object vocabulary (optional)
#include "../_shared/sdf/sdf_shading.hlsli"  // normals, AO, soft shadow, march, camera, shade
```

- `sd_`/`op_` prefixes avoid the engine `sdf` feature library. **Never enable
  `features: [sdf]` in a module that includes these headers** (name collisions).
- `sdf_shading.hlsli` forward-declares `float2 sceneMap(float3 p)` (x = distance,
  y = material id). Your shader must define it; definition can come after the include.
- Exact vs approximate: `op_fillet_union(d1, d2, r)` is a true quarter-circle fillet
  where `r` is a real dimension. `op_smin` is an organic blend; use it for foliage and
  soft forms, never when the spec states a fillet radius.
- Materials: `MAT_GROUND/BODY/ACCENT/METAL/EMISSIVE/FOLIAGE` constants. Carry material
  in `.y` through `op_matmin`; a fractional offset on `.y` encodes per-instance tint.

## Object vocabulary (sdf_objects.hlsli)

`obj_sdf(p, kind, seed)` dispatches: 0 Crate, 1 Column, 2 Chair, 3 Table, 4 Tower,
5 Arch, 6 Tree, 7 Lamp. Contract for adding a kind:

- Local space: ground at y = 0, footprint within |x|,|z| < ~0.5, height <= ~1.7.
- Must fit the shared bounding sphere (`OBJ_BOUND_C`, `OBJ_BOUND_R`) — renderers cull
  with it, so geometry outside the sphere gets clipped from some camera angles.
- Take `seed` and vary proportions with `sd_hash11` so clones don't read as copies.
- Bump `OBJ_KIND_COUNT`, then raise the `kind*` param max in consumer manifests.
- Keep it cheap: an object SDF runs per march step. Use `sd_mirrorXZ` for leg/pillar
  symmetry (one eval = four legs); prefer a few well-chosen primitives over many.

## Instanced scenes (sdf_scene_render)

- Data contract: the standard 48-byte PNode (`pos, dir, depth, u, v, weight, group,
  kind, seed, active`). Canvas maps to ground: `pos.x → world X, pos.y → world Z`,
  scaled by `world_scale`. Any PNode producer works — grid, ring, spiral, scatter,
  border, spline-resampled paths.
- Mapping modes mirror `pl_render`: kind FromNode/Fixed/Cycle/Hash over `kind0..3`,
  scale Uniform/ByWeight/ByDepth/Hash, rotation FromDir/Fixed/Hash. `FromDir` yaw plus
  a `pl_path` chain gives objects that face along a street or curve.
- Performance architecture: per pixel, every instance is tested once against the ray
  (bounding-sphere shortlist, `MAX_LIST` 24), then only shortlisted instances march.
  Shadow rays build a second shortlist toward the sun. Budgets: `render_count` <= 96,
  720p, shadows on ran ~43 fps sharing the GPU with a StreamDiff node on an RTX 5090.
  Knobs when tight: `shadows` off, lower `render_count`, more fog, lower resolution.
- One `sdf_scene_render` = one 3D world (single depth domain). Do not additively
  composite two of them expecting correct occlusion; give each region its own records
  instead (multiple data chains can merge upstream). A float depth output for true
  cross-node 3D compositing is future work.

### Recipes

Café / room: `pl_grid` mode Grid (6x4, count 24, slight jitter) → scene with
`kind_mode Cycle, set_size 2, kind0 2 (chair), kind1 3 (table)`, `world_scale 2.4`,
`scale_base 0.42`.

Dusk city: `pl_grid` mode Scatter (count 96, extent 1.6x1.3) → `kind_mode Hash,
set_size 4, kinds [4, 4, 6, 7]` (towers weighted double, trees, lamps),
`world_scale 4.5`, `scale_base 0.75, scale_var 0.55`, `fog_density 0.45`,
`sun_elevation 28`. Streets: add a `pl_grid mode Line → pl_path` chain with lamps on
`rot_mode FromDir`.

## Camera

Modules ship two rigs, chosen by a `cam_mode` enum button-grid `[Fly, Orbit]`,
**default Fly**. Never default to Orbit and never gate the mode behind a `bool` toggle —
see the two hard-won rules at the end of this section.

- **Fly** (default): the `camera` feature — WASD + right-drag in the viewport. Generate
  the ray by UNPROJECTING NDC through `_InvViewProjMatrix` (below), NOT the
  `_RayDirection(uv)` helper, which does not reliably track the live view. The fly camera
  is driven ONLY by live viewport input: the `camera_pos_x/y/z`, `camera_yaw/pitch`
  StateTree params do NOT move it (setting them via MCP is a proven no-op), so you cannot
  frame or capture the fly camera from automation — switch to Orbit for that.
- **Orbit**: deterministic rig (`cam_orbit/elevation/distance/target_y`, `cam_focal`,
  `rotate_speed` turntable). Fully drivable from StateTree/MCP, so use it for captures and
  A/B comparisons; expressions can drive `cam_orbit` from a `signal` LFO.

Fly ray-gen (canonical — matrix path, Y-flipped for DX clip space):
```hlsl
if (cam_mode == 0) {                                  // Fly
    float2 ndcv = float2(uv.x*2-1, 1 - uv.y*2);
    float4 nW = mul(_InvViewProjMatrix, float4(ndcv,0,1));
    float4 fW = mul(_InvViewProjMatrix, float4(ndcv,1,1));
    nW/=nW.w; fW/=fW.w;
    ro = _CameraPos; rd = normalize(fW.xyz - nW.xyz);
} else {                                              // Orbit
    sdf_orbitRay(cam_orbit + rotate_speed*_Time*30.0, cam_elevation, cam_distance,
                 float3(0, cam_target_y, 0), ndc, cam_focal, ro, rd);
}
```

Two rules learned the hard way (industrial_lattice, working example modules/steel_lattice):
1. **Default to Fly, not Orbit.** A forced orbit branch silently discards the viewport
   camera every frame, so right-drag/WASD look completely dead ("locked to orbit").
2. **Use an enum button-grid for the mode switch, not a `bool`+`flags: button`** — the
   bool checkbox did not latch reliably in the panel, so the mode never actually flipped.

## Verification loop

1. Write all `.hlsl` files first, `manifest.yaml` LAST (hot reload fires on manifest save).
2. `sentinel_pipeline compile_check project_dir=...` offline until clean.
3. `create type=module project_dir=...`, poll `compile_status`.
4. `sentinel_capture pipeline` → look at it yourself, then `vision_eval` with the spec
   as a checklist (features present, counts, proportion ratios) for an independent score.
5. Judge structure with parameter A/Bs: change `bolt_count`/`slot_count`/`kind*` via
   `set_many` and confirm the restructure in a second capture.
6. Motion: `sweep_record` a dimension or `cam_orbit` and eval the MP4 (`motion-eval`).

## Gotchas

- **Module reload with `features: [camera]` crashed Sentinel once** (unhandled C++
  exception during a `force_reload` that added the feature). Until root-caused: prefer
  destroy + recreate over `force_reload`/hot-reload for camera-feature modules, and
  save the project before editing their files while the app runs.
- `sentinel_capture capture_at` rejects `overrides` when the client serializes them as
  a JSON string. Workaround: `sentinel_state set_many` + plain capture + restore.
- `set_many` cannot set a `point2D` as an array value; write the decomposed scalar
  paths (`.../extent_x`, `.../extent_y`).
- Parameters without explicit `min`/`max` clamp to 0..1. Dimensions need real ranges.
- Alpha must be 1.0 in the output write, or the preview blends to invisible.
- Marching guard band: keep the march's max distance above `world_scale` times the
  canvas diagonal or distant instances vanish before the fog does.

## Harvest

New object kinds belong in `sdf_objects.hlsli` (update the kind list here and in the
catalogue entry). A genuinely new geometry technique (new renderer, new placement
transport) gets its own module + a `knowledge/technique-catalogue.md` entry, per the
standard harvest rule.
