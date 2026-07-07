# Technique Catalogue

The map of the curated technique library in `modules/`. This is what turns the library from a
pile of modules into a **navigable toolkit** — the palette you compose any new scene from.

**How to use it (Phase 0, `modular-scene-authoring`):** decompose the reference into elements, then
for each element scan this catalogue for a technique that fits — mark it `reuse`, `adapt`, or
`invent`. The catalogue answers "what capabilities do we already have, and what's the one new thing
this scene needs?"

**How entries are earned (harvest, at `/wrap` / `/end-session`):** a module enters the library only
when it's a **novel, reusable technique** — not scene glue. When a build produces one, extract it
from its project into `modules/`, then add or update an entry here. A variant of an existing
technique updates that entry's exemplars rather than adding a new row. Keep it deduped by technique
family, not one row per module.

**Entry shape:** `Technique — transport · exemplar module(s) · what it does · compose-with`.

> Seeded from the `topographic_hud` build (the first project under this system). These are the
> starting exemplars; refine names/params as later scenes exercise them. Everything predating this
> system lives in `scratch/_legacy/` and is deliberately **not** catalogued.

---

## Fields & derivation

Continuous scalar/vector fields carried as float textures (R32F / RGBA16F), with downstream passes
deriving isolines, gradients, and warps **from** the one field. The elegance backbone: generate
once, derive many.

- **Scalar height/region field** — *texture (RGBA16F)* · `field_gen` · multi-center domain-warped
  FBM writing `R=elevation, G=region/basin id, B=slope, A=detail`; flow drift over time; mode enum
  (Basins/Ridges/Islands/Flow). The master others read. · *compose-with:* every derivation below.
- **Isoline / contour extraction** — *reads field texture* · `contour_blue` (soft), `contour_accent`
  (gated to band / every-Nth / region / ridge) · `abs(frac(field*line_count + phase) - 0.5)` sliced
  into lines with major/minor emphasis and elevation fade. · *compose-with:* `field_gen`.
- **Field-warped grid** — *reads field texture* · `grid_warp` · procedural grid whose UVs are
  displaced along the gradient of a smoothed field (sample offset controls coherence; keep the warp
  gentle or lines shatter). · *compose-with:* `field_gen`.

## Points & instances

- **Field-peak point placement** — *field texture → StructuredBuffer\<NodeRecord\>* · `node_gen` ·
  seeds points then runs K gradient-ascent steps to snap them onto field peaks (mode:
  Random/Peaks/Pits/Ring/Hybrid). Emits pos/radius/intensity/kind/active records. · *compose-with:*
  `field_gen` (placement), `link_gen` / `label_gen` (consumers).
- **Point-buffer glow renderer** — *StructuredBuffer\<NodeRecord\> → texture* · `node_render` ·
  bloom-bright cores + optional star rays from a point buffer. · *compose-with:* any point producer.
- **Organic family plan + renderer branch** — *compute → StructuredBuffer\<FlowerElement\> → texture* ·
  `garden_flower_plan` + `garden_flower_render` (four-flower garden proof) · one reusable pattern for
  families of related organic instances: each branch has a plan node that emits self-describing records
  (`center`, `radius`, `angle`, `species`, `part_type`, `layer`, `id`, `color`, `width`, `length`,
  `phase`, `bend`, `active`) and a matching renderer that consumes only that branch. Duplicate the same
  plan/render pair per species or variant, set species/seed/layout params per branch, then feed a named
  compositor whose inlet order matches the branch order. The graph stays clean because every family is
  independently inspectable with `capture_data_port` and a renderer preview. · *compose-with:* background
  texture generator, ordered compositor, post grade, manual `set_node_geometry` layout.

## Spline / segment geometry

Hard, sparse, individually-addressable geometry as bezier-capable segment records with a group id.

- **Point-pair link / route expander** — *NodeRecord → StructuredBuffer\<LinkRecord\>* · `link_gen` ·
  derives connectors between points (Nearest/Chain/Radial/Hub, with min/max distance) plus authored
  arcs (e.g. an orbit arc) as curve records; preserves `group_id` for route continuity. ·
  *compose-with:* `node_gen`, `link_render`.
- **Segment / bezier stroke renderer** — *StructuredBuffer\<LinkRecord\> → texture* · `link_render` ·
  draws straight and cubic strokes (`sdSegment` + bezier) with width, dash, draw-on progress, glow;
  applies dash/taper across the whole route, not per segment. · *compose-with:* any segment producer.

## Text / atlas

- **Glyph-atlas label placement + blit** — *NodeRecord → StructuredBuffer\<LabelRecord\> → texture* ·
  `label_gen` (places anchors near a subset of points / on a ring) + `label_render` (blits baked
  strings via the scientifica font in `modules/_shared/fonts/`; use `#define OS_NO_RECORD_BUFFER`
  with the os_terminal glyph blit). · *compose-with:* any point producer; `_shared` font includes.

## Instancing, atlases & depth

Data-driven widget instancing: **generator compute nodes emit placement records**
(`StructuredBuffer<Widget>`) that a **renderer stamps from a primitive atlas**,
projected through a drifting camera so depth becomes real parallax + fog. The way
to get *many* addressable primitives composited in 3D without a monolith. Seeded
from the `fui_dashboard` v2 build.

- **Primitive atlas bake** — *procedural → texture (grid atlas)* · `prim_atlas` ·
  bakes N primitives (rings/ticks/reticles/boxes/brackets/chevron/triangle/bars/
  hatch/dot-grid/text-block/mini-dial/markers…) into an 8×N grid, one primitive
  per cell in local `q∈[-1,1]` space, packing `R=body, G=core` tiers. The stamp
  vocabulary an instance renderer draws from. · *compose-with:* `widget_render`.
- **Widget placement generator** — *compute → StructuredBuffer\<Widget\>* ·
  `layout_gen` (structural: reticle rows, panel stacks, hero ring clusters, tick
  fans, corner tabs, bg depth rings), `detail_gen` (dense: scattered readouts,
  marker clusters, connector-dot chains, far dust). One thread = one record;
  clusters keyed by index range; `seed`/`density` restructure the whole HUD. The
  `Widget` contract = `pos.xy, depth, rot, scale.xy, kind, value, p01, p23, tier,
  active, group, seed` (64B). Multiple generators feed one renderer on separate
  data slots. · *compose-with:* `prim_atlas`, `widget_render`, `signal`.
- **Atlas-instance depth renderer** — *StructuredBuffer\<Widget\> ×N + atlas →
  texture* · `widget_render` · per-pixel gather over every record: projects the
  widget's `pos+depth` through a drifting camera (`cam_amp`/`cam_speed`/`parallax`
  → real 3D parallax), scales/fogs by depth, transforms the pixel into instance
  local space, stamps the atlas cell, additively accumulates with a cheap bbox
  reject. Order-independent glow; ~384 records/pixel at 60fps. Two data inputs
  (layout + detail) on distinct pass-binding slots so the atlas `_Tex0` doesn't
  collide. · *compose-with:* `prim_atlas`, `layout_gen`/`detail_gen`.

## Layout kit (composable placement pipeline)

A family of buffer nodes that all speak ONE record type — `PNode` (48 B: `pos.xy,
dir.xy, depth, u, v, weight, group, kind, seed, active`) — so any node connects to
any other. Pull *placement* out of renderers: build a **grid → splines → points**
chain, then map points to whatever you draw. Stamp the same chain down many times
in different modes for different regions. Seeded from `fui_dashboard` v3.

- **Parametric structure source** — *compute → StructuredBuffer\<PNode\>* · `pl_grid` ·
  7 modes (Grid / Ring / Spiral / Scatter / Line / Border / Radial) with count /
  rows·cols / rings·per_ring / center / extent / radius / jitter / depth. Emits
  grouped, u-ordered anchors. The node you duplicate everywhere. · *compose-with:*
  every node below.
- **Spline shaper** — *PNode → PNode* · `pl_path` · groups input by `group`, fits a
  Catmull-Rom curve per group (control points gathered in buffer order = u order),
  resamples to `points_per_path` points with `dir` = tangent. Modes Smooth/Linear/
  Loop. "Draw splines within the grid." · *compose-with:* `pl_grid` (source),
  `spline_render` / `pl_style` (consumers).
- **Placement distributor** — *PNode → PNode* · `pl_spawn` · Jitter / Decimate /
  Branch(perp offset) / Passthrough, plus weight/depth jitter. Organic density on
  top of a structured source. · *compose-with:* any PNode stage.
- **Previewable cloner renderer** — *PNode + atlas → texture* · `pl_render` · the
  combined style+stamp node: maps each point to a primitive (kind FromNode/Fixed/
  Cycle/Hash/ByGroup over an explicit 4-kind set; scale base×aspect×weight|depth|hash;
  tier Fixed/ByWeight/GroupParity/Hash; rot FromDir/Fixed/Hash; density gate) AND
  renders it to a full texture with atlas stamp + depth-camera parallax — so **each
  chain owns a renderer and its node preview shows exactly what it draws** (the key
  advantage over the merged `widget_render`: per-chain visibility for editing). One
  `pl_render` per chain; a compositor sums the layer textures. · *compose-with:*
  `pl_grid`/`pl_path`/`pl_spawn` (source), `prim_atlas`, additive compositor.
- **PNode → Widget adapter** — *PNode → StructuredBuffer\<Widget\>* · `pl_style` ·
  the buffer-only variant (maps points → Widget records) for when many chains merge
  into ONE `widget_render` (see Instancing). Prefer `pl_render` when you want
  per-chain previews; `pl_style`+`widget_render` when you want a single merged pass.
- **Spline stroke renderer** — *PNode → texture* · `spline_render` · connects
  consecutive same-`group` PNodes with `sdSegment` (+ dashes, end-node dots). The
  data-driven connector/leader renderer; the alt consumer of a `pl_path` output. ·
  *compose-with:* `pl_grid`→`pl_path`.

Canonical composition (each stamped many times with different params): `pl_grid[mode]
→ [pl_spawn] → pl_style → widget_render` for stamped primitives, and `pl_grid →
pl_path → spline_render` for drawn curves. `widget_render` takes 6 Widget inputs so
several style chains merge into one render.

## 3D object geometry (SDF raymarch)

Real 3D objects as signed distance functions in compute passes: no meshes, every
dimension a typed parameter, CSG booleans and exact fillets as one-line ops. Shared
headers in `modules/_shared/sdf/` (`sdf_ops` primitives/booleans, `sdf_objects`
kind-indexed vocabulary, `sdf_shading` normals/AO/shadow/camera with a
`sceneMap` prototype contract). Authoring method + gotchas live in the
`procedural-geometry-authoring` skill. Seeded from the SDF geometry lane
(bracket/chair experiments + `sdf_scene_render` proof).

- **Parametric hero object** — *generator → texture* · pattern in the
  `procedural-geometry-authoring` skill (bracket + fancy-chair exemplars) · one module
  raymarches one object built from exact typed dimensions (plate/boss/bolt-circle,
  seat/back/legs); dual camera rig (deterministic orbit params + fly cam);
  spec-checklist verification via `vision_eval`. · *compose-with:* `post`, any
  compositor; drive dimensions from `signal` / OSC for morphing props.
- **SDF object vocabulary** — *HLSL include* · `_shared/sdf/sdf_objects.hlsli` ·
  `obj_sdf(p, kind, seed)` dispatching seed-varied objects (crate, column, chair,
  table, setback tower, arch, tree, lamp) in a shared local-space + bounding-sphere
  contract, so renderers cull instances uniformly. Extend by adding a kind function. ·
  *compose-with:* `sdf_scene_render`, any custom raymarcher.
- **Instanced 3D scene renderer** — *StructuredBuffer\<PNode\> → texture* ·
  `sdf_scene_render` · consumes the standard 48 B PNode stream (canvas pos → ground
  plane XZ), maps kind/scale/rot like `pl_render` (FromNode/Fixed/Cycle/Hash), culls
  per pixel with ray-vs-bounding-sphere shortlists, and raymarches ground + instances
  with sun soft shadows, AO, per-instance tint, emissive materials, and fog. A grid
  chain becomes a café; a scatter chain becomes a dusk city; `pl_path` + FromDir yaw
  lines objects along streets. ~96 instances at 720p with shadows runs real-time on a
  5090. · *compose-with:* `pl_grid`/`pl_spawn`/`pl_path` (placement), `post` (finish),
  `signal` (sun/camera motion).
- **Industrial structural SDF world** — *StructPart + GreeblePart buffers → one SDF
  scene* · `industrial_bay_gen`, `industrial_surface_sampler`,
  `industrial_greeble_place`, `industrial_struct_merge`, `industrial_greeble_pack`,
  `sdf_industrial_scene_render` · generates multi-level steel interiors with columns,
  beams, braces, catwalks, pipes, ladders, optional surface-attached greebles, and a
  fly/orbit camera in one occlusion domain. Defaults are intentionally lightweight
  (540×810, greebles/shadows off); raise `max_greebles`, `greeble_density`, shadows,
  and resolution incrementally. · *compose-with:* `industrial_mono_post`, camera
  expressions, saved projects under `projects/industrial_steel_greebled/`.
- **Infinite structural lattice** — *generator → HDR texture* · `steel_lattice` · a whole
  concrete/steel factory interior as ONE raymarched SDF, endless in every direction via
  pure domain repetition (`rep1(x,c)=x-c*round(x/c)`): vertical columns + X/Z beams
  unioned, no mesh / no placement buffer / no bounds. Detail is all real geometry: carved
  formwork grooves (1-Lipschitz cutter with a `+eps` surface bridge; independent H-band /
  V-flute width+depth, offsets, edge rounding, distance-LOD), and guard-banded junction
  hardware (connection collar + gridded bolt rows at every node). Layered procedural
  weathering (macro→meso→fine→cracks→streaks) + a **camera-headlamp** light (lamp at the
  ray origin, distance falloff + torch cone, fade-to-black) + in-shader SSAA (NxN jittered
  rays). Outputs linear HDR. ~60 fps/720p at AA 2–4 on a 5090. · *compose-with:*
  `industrial_mono_post` (B&W bloom grade — the finished two-node graph), `signal` (drive
  `cam_orbit`/light for motion). Show: `projects/industrial_lattice/`.
- **Procedural noise header** — *HLSL include* · `_shared/sdf/sdf_noise.hlsli` ·
  self-contained value-noise kit for SDF surface detail: `sd_hash31`, `sd_vnoise3`,
  `sd_fbm3(p,oct)`, `sd_triplanar_fbm(p,n,scale,oct)` (normal-weighted, wraps faces),
  `sd_ridged3` (turbulence — cracks/veins/rock), `sd_fbm3_warp` (domain-warped, breaks the
  value-noise grid so patterns stop looking stretched). `sd_` prefix, no nested includes —
  include after `sdf_ops.hlsli`. Compose noise layers at different scales for realistic
  weathering. · *compose-with:* any raymarched SDF shade pass.
- **Spline tube + turned finial** — *HLSL include* · `_shared/sdf/sdf_extras.hlsli` ·
  `sd_bezierTube(p,a,b,c,r)` sweeps a capsule along a quadratic bezier (8 segments) —
  the SDF "spline" transport for wires, rigging, hanging cables and bent arcs;
  `obj_baluster(p,base)` is a lathe-like stack of primitives (turned-wood / chess-pawn
  finial). Harvested from `dada_totem`. · *compose-with:* any raymarched sceneMap.
- **Data-driven SDF assemblage + distortion (desert_totem v2)** — *compute → StructuredBuffer\<DadaPart\> → texture* ·
  `dada_layout` / `dada_scatter` / `dada_render` / `dada_control` (project `desert_totem`) · the
  externally-drivable evolution of the hero assemblage: pack every object into a 64 B `DadaPart`
  record (float2s-first: `pos_xy, sc_xy, pos_z, sc_z, yaw, tilt, roll, kind, mat, group, p0..p2,
  active`) authored by a compute generator, then a forked single-pass renderer **brute-forces**
  both buffers with a 1D height-band reject (no ray-sphere shortlist — a vertical stack defeats it;
  the monolith is the perf proof) plus a hardcoded armature/wires, and colours objects with a
  once-per-pixel `shadeSample`. **Domain distortion** as driveable params, partitioned by type:
  `melt` (fbm/sin warp of the solids' domain × a Lipschitz safety factor), affine `sag`, radial
  `mirror` fold (applied pre-loop so culling stays valid), and shading-only `painterly`. Generators
  ship a **front-view layout-map preview** (each record → a placed disc) so the node shows the
  arrangement, not a debug strip. A `dada_control` macro node publishes melt/sag/spread/explode as
  control outputs → `ref()` drives layout + render from one place; `sdf_dada.hlsli` is the kind
  vocabulary. Warp distortion costs ~10× via normal/AO/shadow re-entry — keep field fbm to 2–3
  octaves. · *compose-with:* `sdf_dada`, `post`, `signal`, `sentinel_expression`.
- **Domain-distortion warp toolkit** ⭐ — *in-renderer, params* · `dada_render`'s
  `domainDistort(p)` (project `desert_totem`) · **the highest-value technique from this build.**
  Because a whole procedural scene is ONE distance field, a domain warp applied to `p` before
  evaluation melts/twists/shatters the entire scene coherently. Structure: a **3-slot warp
  stack** (each slot: mode ∈ Flow/Ripple/Turbulent/Fractal/Steps/Boxes/Shatter, freq, speed,
  yaw+pitch orientation, xyz offset — summed under a master melt) + geometric ops (twist, bend,
  swirl, sag, wave, pinch, mirror-fold, movable center) + surface ops (painterly, facet, wobble,
  hue-shift). **Two load-bearing rules:** (1) a **Lipschitz safety factor** — multiply the
  returned distance by `1/(1 + Σ distortion strength)` so the sphere-tracer under-steps and
  doesn't overshoot the inflated gradient (this is what makes warped-SDF marching stable); (2)
  **partition by type** — global `p`-warp breaks bounding-sphere culling (so brute-force +
  height-band instead), radial fold applied pre-loop, sag affine, painterly shading-only.
  Rectilinear modes (Steps/Boxes/Shatter) give cubist/glitch looks; flowy modes give Dalí melt;
  they layer. Watch GPU TDR — melt pays ~10× via normal/AO/shadow re-entry; keep field fbm to
  2–3 octaves, cap resolution/march-steps. · *compose-with:* any single-pass raymarch scene,
  `signal` (animate slots), `post`.
- **Hero SDF assemblage (single-pass, hand-placed)** — *generator → texture* ·
  `dada_totem` (project `desert_totem`) · the bespoke counterpart to `sdf_scene_render`:
  when a scene is a *specific* arrangement of unique objects (a Dada totem, a still
  life) rather than a kind-field of clones, compose one `sceneMap` from readable
  sub-maps (`mapSpine`/`mapParts`/`mapHeroes`/`mapSplines`) with an in-shader part list
  of `op_matmin` primitives, procedural multi-colour materials keyed by material id
  (gore/stripe/checker from a piece's centre constant), a ray-miss sky+desert+ridge
  environment, and a fly/orbit camera — all in one depth domain so a fly-cam roams it.
  NB: the orbit rig's `az=0` looks down **+X**; face-`+Z` flat pieces read frontally at
  `cam_orbit≈90`. · *compose-with:* `sdf_extras`, `post` (painterly grade), `signal`
  (self-animation amplitude via `ref()`).

## Plate system — matte-aware raymarch plates + multi-plate distortion compositing (strata)

The way to build **many independently-distorted procedural passes composited on alpha** —
"sharp lines framing distorted things framing sharp lines." Each pass is its own node that
outputs **premultiplied-alpha RGBA** (a coverage matte, not an opaque frame), so a compositor
can stack them in 2D screen space with per-plate blend/gain. A raymarched 3D plate and a flat
2D graphic plate meet in the same stack. Seeded from the `strata` build (dual-reference: glossy
blob mass + melted marble + graphic framing, one palette, infinitely variable).

- **Matte-aware SDF plate** ⭐ — *generator → premultiplied RGBA* · the reusable contract, embodied
  by `blob_render` (project `strata`) · a compute raymarch that writes `float4(rgb*cov, cov)`
  instead of `float4(col,1)` — coverage alpha from ray hit/miss, **NxN SSAA** for clean silhouette
  matte + interior AA, premultiplied accumulation. This is what lets a 3D raymarch plate composite
  in 2D over other plates. Orbit-only camera (no `features:[camera]` = no reload crash, fully
  MCP-drivable for fixed studio framing). The warp toolkit (`domainDistort` + Lipschitz factor,
  ported from `dada_render`) is wired in per-plate so each plate melts/twists by a different amount
  and kind. · *compose-with:* `plate_comp`, `sdf_blob`, `signal`, `strata_control`.
- **Glossy-gradient blob vocabulary** — *HLSL include* · `_shared/sdf/sdf_blob.hlsli` · biomorphic
  inflated forms (sphere/tube/torus/scoop/rbox/lens/bean/horn) for `op_smin`-blended intertwined
  masses, with `blob_albedo()` materials: 2-stop palette **gradient gloss** (mapped along a form
  axis), chrome swirl (+env reflection flag), 3-colour checker cube, matte. Include after
  `sdf_ops` + `palette`. The plastic/ceramic "melted ribbon" look. · *compose-with:* `blob_layout`
  (placement buffer), `blob_render`.
- **Shared palette header** — *HLSL include* · `_shared/palette.hlsli` · one `str_palette(i)` +
  `str_grad(a,b,t)` + `str_studio(uv)` (neutral studio void + vignette) + `str_envColor(rd)`, so
  EVERY plate draws from the same 10 colours → thousands of seeds all read as one artist. The
  cohesion backbone for a plate system; clone + recolour per project. · *compose-with:* every plate.
- **Multi-plate premultiplied-alpha compositor** ⭐ — *N textures → texture* · `plate_comp` (project
  `strata`) · stacks premultiplied plate textures bottom→top over an opaque base, each with gain +
  blend mode (Over/Add/Screen). Injected `_Tex0.._TexN` + `LinearSampler` from an `inputs:` list;
  `mode: generator` with fixed resolution. The reusable "composite independently-distorted plates"
  node; a specific input ordering is project glue, the premult-over machinery is the technique. ·
  *compose-with:* any matte-aware plate, `post`.
- **Domain-warped fbm marble card** — *generator → premultiplied RGBA* · `marble_panel` (project
  `strata`) · a rectangular panel of self-animating domain-warped value-noise marble (two-level
  warp) ramped through the palette with a fake-normal metallic sheen; the "melted flat element."
  Distortion IS the look (warp/veins/flow params). · *compose-with:* `plate_comp`, `str_palette`.
- **2D line-art plate** — *generator → premultiplied RGBA* · `wire_render` (project `strata`) · thin
  bright lines on transparent: seeded ellipse **rings**, loose quadratic-bezier **strands**, and a
  cross-linked **triangulated cage**, aspect-corrected isotropic. The sharp linework that frames a
  mass (ref-#7 circles / ref-#8 chrome cage). · *compose-with:* `plate_comp`.
- **Graphic-marks framing plate** — *generator → premultiplied RGBA* · `marks` (project `strata`) ·
  the hard 2D overlay: red rule lines, solid red squares, rivet/screw dots, a thin **registration
  frame + corner L-ticks**; table-driven + seedable. Reads as "technical framing" over any scene. ·
  *compose-with:* `plate_comp`, `hud_*` chrome.
- **Studio-void backdrop** — *generator → opaque* · `strata_bg` (project `strata`) · neutral cool-gray
  gradient void + subtle vertical framing panels + vignette + anti-band grain. The photographic
  seamless behind a floating subject. · *compose-with:* `plate_comp` (base), `str_studio`.
- **Master-seed variation control** — *compute → control outputs* · `strata_control` (project
  `strata`) · publishes one **master seed** + distortion macros (melt/twist/marble-warp/spread) as
  control outputs; `ref()` expressions drive EVERY plate's seed + warp from it, so one knob
  reshuffles the whole composition while palette + framing stay fixed. The "infinitely variable
  system" pattern (the seed-bus cousin of the `signal` LFO bus). · *compose-with:* every plate via
  `sentinel_expression`, `signal`.

## Image-analysis feedback (features → geometry)

**Close the loop: analyze the rendered image, then derive new geometry from what was detected.**
A `features` pipeline (model-free corner / line / blob extraction) runs on a composited frame and
publishes structured buffers; a renderer threads splines / stamps marks / annotates *through the
detected features*. The graphic layer stops being authored blind and becomes **reactive to the
actual content** — so it always "fits" whatever the generative side produces, at any seed. This is
the single highest-leverage integration found on `strata`: it made the piece dramatically better
for ~one module of work.

- **Feature-reactive spline overlay** ⭐ — *video + features buffer → texture* · `corner_thread`
  (project `strata`) · takes the final image (`_Tex0`) + a `features` **Corners** buffer
  (`{x, y, response, pad}`, x/y in **pixels**, top-left origin) and threads a Catmull-Rom spline
  **through** the corner points, drawn over the picture with glow, per-corner ring markers, and a
  flowing dash. Two orderings: **Loop** (sort corners by angle around their centroid → a closed
  lasso woven through everything) and **Chain** (buffer/response order → an open path). **Arc-length
  trim** (`chain_length` + `chain_offset`) draws only a window of the path — set a short length and
  animate the offset (drive from `signal/control_outputs/sweep`) for a bright segment crawling the
  thread. · *compose-with:* any `features` node, `signal`, `post`.
- **Wiring it feedback-free** — put the analysis + overlay **downstream** of the composite:
  `plate_comp → features → thread`, and thread over `post` (or over `plate_comp`, then `→ post`, if
  you want the line to bloom). Because nothing feeds back into the composite there is **no graph
  cycle**. It re-detects every frame, so in motion the linework is alive (slightly jittery as
  corners pop in/out — smooth by lerping corner positions frame-to-frame or accumulating a trail
  buffer if you want it to glide). The `features` node exposes a **max-corners** cap (~15 reads
  cleanest); fewer, stronger corners → a calmer thread.
- **The other two feature channels are the same pattern** — `features` also emits **Lines**
  (`{x1,y1,x2,y2,angle,length}`) and **Blobs** (`{centroid, bbox, colorRGB, area}`). Stroke/extend
  the detected line segments, or place labels / reticles / connectors on blob centroids — reuse the
  `corner_thread` scaffold (swap the buffer schema + how you consume it). Corner→spline is just the
  first of a family: *detect structure in the render, then draw new structure from it.*
- **Why it lands with generative content** — warped/organic passes (blobs, marble, SDF melt) have no
  authored vector geometry, but a corner/line detector *finds* their salient structure every frame,
  so a crisp derived overlay tracks the melt for free. Sharp-line-framing that follows the content
  instead of floating over it. Pairs naturally with the `strata` plate system.

## Control & reactivity

- **Control-output signal bus** — *compute → control outputs* · `signal` · one tiny module runs N
  LFOs (pulse / sweep / beat / slow) and publishes them as scalar control outputs. Other nodes
  *subscribe* via `ref("signal/control_outputs/<name>")` expressions — decoupling animation authority
  from the animated nodes, so swapping the source (LFO → audio/OSC) makes a scene reactive with no
  rewiring. The cleanest reuse pattern in the library. · *compose-with:* any parameter, via
  `sentinel_expression`.

## FUI / HUD chrome

Procedural sci-fi interface widgets — flat 2D screen-space graphics, each a
render node emitting `float4(col, luminance)` for additive compositing. No data
ports; layout lives in typed params / in-shader placement tables. Compose as a
layer stack through a compositor. Seeded from the `fui_dashboard` build.

- **Multi-instance dial system** — *procedural polar → texture* · `hud_gauge` ·
  a table of gauge instances drawn in one pass: concentric solid/dashed/tick
  rings, a value arc (0..1), a signature thick bright arc segment, radial spokes,
  inner crosshair, plus a wedge-clipped radiating **tick-fan** instance. Two
  brightness tiers (body/core) for bloom. Value/sweep drivable via `ref()`. ·
  *compose-with:* `signal` (animate spin/value), `hud_comp`, `post`.
- **Orbital rings + wireframe globe** — *procedural ellipse strokes → texture* ·
  `hud_orbits` · tilted crossing ellipses (gyroscope/atom look) with a travelling
  node, and a lat/long wireframe sphere (foreshortened latitude ellipses +
  precessing meridians). `ellipseStroke(q,a,b,rot,w)` helper. · *compose-with:*
  `hud_comp`.
- **Data-panel chrome** — *procedural rect/segment → texture* · `hud_panels` ·
  composable helpers: framed panels with header bars + hashed fake "text" rows,
  warning triangle, X / grid icons, vertical bar-chart block, edge tab boxes.
  Static accumulators for body/core/dim tiers. · *compose-with:* `hud_labels`
  (real text over the tab boxes), `hud_comp`.
- **Dashed leader/connector lines** — *procedural segment SDF → texture* ·
  `hud_leaders` · `sdSeg` + dash-phase strokes over a hand-authored route table
  with elbow routing and end-node dots. The FUI cousin of `link_render` for the
  few specific connectors a HUD needs (no buffer pipeline). · *compose-with:*
  any widget layer, `hud_comp`.
- **Fixed-string glyph labels** — *procedural glyph blit → texture* ·
  `hud_labels` · self-contained variant of `label_render`: a placement table
  (id, UV, scale, accent tier) blits scientifica strings via `_shared` font with
  `#define OS_NO_RECORD_BUFFER` — no data buffer. For hand-placed HUD tokens
  (percent readouts, corner tabs, technical labels). · *compose-with:*
  `_shared` fonts, `hud_panels`, `hud_comp`.

## Compositing & finish

- **Post finish stack** — *filter* · `post` · chromatic aberration + multi-tap bloom + teal/orange
  split-tone grade + contrast/saturation + vignette + film grain; resolves to 8-bit. Reusable across
  raster scenes; tune thresholds per look. · *compose-with:* a composited scene.
- **Multi-layer compositor** — *pattern, usually scene-glue* · ordered additive/screen blend of layer
  textures with per-layer gains + optional viewport-mask clip. The *pattern* is reusable; a specific
  instance (which layers, what order) is usually project glue — rebuild per scene rather than
  harvesting. Promote only if a genuinely general compositor emerges.

## Choreography & timeline

Time-structured motion over instance records and cue-driven shows, built on the shared motion
vocabulary in `modules/_shared/anim/anim.hlsli` (closed-form springs incl. resumable `an_spring_v`,
stagger family, anticipation, squash, seamless loop noise; same equations in ExprTk).

- **Staggered spring cascade** — *reads PNode records* · `choreo_cascade` · radial/index/wave/noise
  staggers delay per-instance closed-form springs (`AN_BOUNCY`..`AN_HEAVY` presets); `ghost_mode`
  renders past/future evaluations as onion-skin ghosts (pure-function motion makes the future
  previewable). · *compose-with:* `pl_grid` (records), `conductor` (cue envelopes via expressions).
- **Timeline HUD** — *reads `Cue Records` data port* · `timeline_hud` · DAW-style lanes, cue blocks,
  beat grid, and live playhead rendered from the conductor's sheet-derived records; drive
  `playhead_seconds` from `ref("Conductor/control_outputs/...")`. · *compose-with:* `conductor`,
  any show graph as a rehearsal overlay.
