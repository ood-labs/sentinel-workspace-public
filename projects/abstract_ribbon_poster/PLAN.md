# Abstract Ribbon Poster Plan

## Architecture Axes

- Space: 2D screen-space composition with 3D-shaded procedural elements.
- Scene shape: composite-of-layers. The reference mixes a soft studio poster background, a biomorphic ribbon, hard triangle graphics, glass/chrome elements, spheres, and flat accent bars. Independent layers make each visual language previewable.
- Motion model: self-animating and reactive-ready. Defaults are subtle: ribbon shimmer, drifting highlights, tiny glass/ring motion. Each module exposes `phase`/`motion` controls that can later be driven by `signal` or audio/OSC expressions.
- Output target: raster screen/Spout poster, portrait 1024x1280.

## Element -> Technique -> Transport

| Element | Technique | Transport | Reuse map |
| --- | --- | --- | --- |
| Warm grey studio background, floor, shadows | Procedural gradient/shadow generator | Texture output | Invent scene glue |
| Main organic folded ribbon with many rib lines | Aspect-correct continuous ribbon field with editable center/scale/tilt/aperture | Texture output | Invent reusable candidate |
| White spheres, black sphere, striped oval, chrome ring, blue bars, black square, glass capsules, fine guides | `ShapeRecord` placement generator -> shape renderer | StructuredBuffer records via data links | Invent reusable candidate |
| Right triangle-pattern column | `TriangleRecord` grid generator -> triangle renderer | StructuredBuffer records via data links | Invent reusable candidate |
| Final composition | Ordered blend using luminance masks, soft shadows, bloom-ready highlights | Texture inputs 0-4 | Invent project glue |
| Finish | Existing post stack if needed | Texture input | Reuse `modules/post` |

## Module Graph

```text
abstract_bg ----------------------------\
abstract_ribbon -------------------------\
abstract_triangle_gen -> triangle_render  -> abstract_comp -> post
abstract_shape_gen    -> shape_render ---/
```

The hard/repeated poster objects are now data-buffer lanes. Placement lives in the generator modules; renderers consume records and do not own hardcoded object positions. The ribbon stays texture-field driven because it is a continuous organic form.

## Lane Contracts

- Shared resolution: 1024 x 1280 portrait.
- `abstract_bg`: generator, output RGBA16F.
- `abstract_ribbon`: generator, output RGBA16F, black outside the ribbon.
- `abstract_shape_gen`: generator, output preview texture + `Shapes` data port, 32 x 64-byte `ShapeRecord`.
- `abstract_shape_render`: data consumer, output RGBA16F, renders `Shapes`.
- `abstract_triangle_gen`: generator, output preview texture + `Triangles` data port, 128 x 64-byte `TriangleRecord`.
- `abstract_triangle_render`: data consumer, output RGBA16F, renders `Triangles`.
- `abstract_comp`: filter, five optional video inputs, output RGBA16F. Blends by luminance/soft screen rather than alpha.
- `post`: existing filter, converts to display-ready 8-bit.

## Build Sequence

1. Author all shader files first, then manifests.
2. Run `compile_check` on each project module.
3. Create live Module pipelines in Sentinel.
4. Wire all generator texture outputs into `abstract_comp`, then `abstract_comp` into `post`.
5. Auto-layout the graph and verify `compile_status`, `info.stats.healthy`, preview SRVs, and frames processed.
6. Capture intermediate layers and the final post output, then checkpoint the project bundle.

## Harvest Notes

The ribbon renderer is the only likely library candidate. The column, accent, and compositor modules are reference-specific glue unless a second poster needs the same contracts.
