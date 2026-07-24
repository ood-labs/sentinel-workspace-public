# Nocturne Marble Relic — Modular Scene Plan

## Direction

An abstract ray-marched marble statue that sits between an ancient votive object and a post-human artifact: a tall, asymmetrical figure with a strong central void, compressed limbs or wings, carved seams, and a dark stone plinth. The image should feel physically lit, not neon-lit: near-black surroundings, charcoal marble, restrained warm ivory highlights, deep umber cavities, and brief copper/amber light events driven by the existing trigger sequencer.

The sculpture is the subject. Procedural texture, lighting, and motion support its silhouette and material read rather than becoming unrelated decoration.

## Data archetype

Organic / biomorphic scene: structured SDF-part records plus structured light records and one compact material record. The renderer consumes those records and produces display color plus native depth. The same sculpture-part records must remain the source of truth for preview, raymarching, and future selection/picking.

## Planned graph

```text
trigger_sequencer ── control outputs / expressions ──┬─> nocturne_light_rig ──┐
                                                     └─> sculpture motion       │
marble_sculpture_plan ── SDF Parts ─────────────────────────────────────────────┤
marble_material_profile ── Marble Profile ──────────────────────────────────────┤
                                                                                v
                                                                    marble_sdf_renderer
                                                                    ├─ Color
                                                                    └─ Depth
                                                                                |
                                                                      nocturne_final_grade
                                                                      └─ final Color
```

### 1. `marble_sculpture_plan` — semantic form producer

Publishes a fixed-capacity `SDFParts` buffer. Each record contains a stable logical id, primitive kind, material id, parent/group id, position, scale, rotation, blend radius, and active flag. The first composition uses roughly 12–20 parts:

- a tapered central reliquary body;
- two offset shoulder / wing masses;
- a broken halo or crown arc;
- a carved central negative-space cutter;
- two asymmetrical lower supports;
- a dark plinth and a few fracture / seam volumes.

Its preview must show the actual part bounds, group colors, active flags, and the central void. Parameters should change structure: silhouette preset, asymmetry, void width, torsion, crown break, base spread, and detail density.

### 2. `marble_material_profile` — surface authority

Publishes one `MarbleProfile` record rather than duplicating material constants in the renderer. Fields cover stone base, warm highlight, vein tint, pore scale, vein scale, vein contrast, roughness, subsurface lift, cavity darkening, and micro-normal strength. Its preview is a material swatch / diagnostic slab that visibly shows the procedural vein response.

Keep this node quiet and legible. It is the material laboratory, not a second sculpture.

### 3. `nocturne_light_rig` — animated light authority

Publishes 6–8 light records: position, color, intensity, radius, type, and active flag. Default rig:

- one large warm key from high left;
- one weak cool-gray fill from low right;
- two narrow rim lights behind the silhouette;
- two moving slash lights that skim the marble relief;
- one short-lived copper pulse reserved for sequencer triggers.

Its preview must show the sculpture proxy, light positions, direction vectors, influence radii, and current intensities. It should never be decorative telemetry.

The existing `Trigger_Sequencer` drives only high-impact light behavior through expressions: envelope → intensity/rim lift, trigger → pulse amount, clock phase → orbit phase. The sequencer remains a control source, not a second animation system.

### 4. `marble_sdf_renderer` — single rendering authority

Consumes `SDFParts`, `MarbleProfile`, and `LightRecords`. Uses the host camera feature as the sole camera owner initially. The raymarch is responsible for:

- smooth unions, cuts, and detail displacement from the part records;
- silhouette-preserving marble veins and pores;
- soft multi-light shading, contact occlusion, and bounded shadows;
- controlled subsurface / edge lift for readable dark marble;
- restrained volumetric darkness around the base;
- separate display-safe Color and native Depth outputs.

The renderer should expose only high-impact controls: ray quality, sculpture scale, detail amount, vein visibility, cavity depth, shadow softness, and exposure. Camera rows stay on this node's preview and never move to a Scene Group.

### 5. `nocturne_final_grade` — image finish

Consumes renderer Color and Depth. Applies restrained filmic tone mapping, black-level shaping, subtle vignette, controlled grain, and a low-frequency warm/cool balance. It must preserve the marble silhouette and not turn the image into a glow effect. This is where the final darkness is controlled, not by crushing the renderer until its form disappears.

## Contracts

### `SDFParts` — 64-byte record, fixed capacity

```text
float4 transform_a  // position.xyz, primitive kind
float4 transform_b  // scale.xyz, blend radius
float4 rotation     // euler.xyz, material id
float4 meta         // logical id, group id, seed, active
```

The renderer interprets primitive kinds through a registry-backed table. The first version can use hand-authored semantic records, but the record layout must leave room for stable ids and grouping so later editing and picking do not require a contract break.

### `LightRecords` — 48-byte record, fixed capacity

```text
float4 position_radius
float4 color_intensity
float4 direction_type
```

The renderer reads the active count from the manifest capacity plus `active`/type metadata. No renderer-side light reconstruction.

### `MarbleProfile` — one 64-byte record

```text
float4 stone_color_roughness
float4 vein_color_scale
float4 vein_contrast_pore_scale
float4 cavity_subsurface_micro_normal
```

## Build order and proof gates

1. Author `marble_sculpture_plan`; compile-check; create it alone; inspect its part preview and capture its data port.
2. Author `marble_material_profile`; prove the marble swatch and its parameter response.
3. Author `nocturne_light_rig`; prove moving light records and preview vectors without the final renderer.
4. Author `marble_sdf_renderer`; wire the three data lanes one at a time; prove silhouette, then material, then lights, then depth.
5. Connect `Trigger_Sequencer` expressions only after the rig is stable; capture before/after pulse states and confirm the change is visually meaningful.
6. Add `nocturne_final_grade`; compare renderer Color against graded Color so the grade is demonstrably improving legibility.
7. Profile the graph, checkpoint the show with bundled Module folders, and capture a short motion sweep across the light pulse and sculpture torsion.

Every node must have a meaningful intermediate preview, advancing frames, healthy runtime state, and a structural control that visibly changes its own output before the next node is started.

## Palette and motion language

- Background: near-black charcoal, never empty gray.
- Marble: blackened ivory / graphite with warm stone highlights.
- Accent: one copper-amber pulse; cool light stays nearly neutral gray.
- Motion: slow monumental torsion, tiny breathing displacement, and abrupt but sparse light cuts. No constant neon shimmer.
- Texture: veins follow form and stretch around the SDF, with a few intentional large mineral bands plus restrained micro-noise.

## Pass criteria

- The silhouette reads as a deliberate statue before texture or lighting is enabled.
- The central void remains legible at thumbnail size.
- Marble reads as stone through value structure, veins, cavities, and roughness — not just a noisy color map.
- Each light has a visible, bounded effect; no global gray wash or unbounded inverse-square glow.
- Trigger pulses produce an immediate, legible lighting event without changing the sculpture's identity.
- Color and Depth are separate, healthy outputs, and all active Module nodes compile with no health reasons.
