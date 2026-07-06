# Abstract Ribbon Poster Plan

## Architecture Axes

- Space: 2D screen-space composition with 3D-shaded procedural elements.
- Scene shape: composite-of-layers. The reference mixes a soft studio poster background, a biomorphic ribbon, hard triangle graphics, glass/chrome elements, spheres, and flat accent bars. Independent layers make each visual language previewable.
- Motion model: self-animating and reactive-ready. A dedicated `abstract_signal` node publishes `pulse`, `sweep`, `beat`, and `slow` control outputs. Ribbon rib phase, width breathing, highlight drift, and wave amount are driven with `ref()` expressions so animation authority is visible in the graph.
- Output target: raster screen/Spout poster, portrait 1024x1280.

## Element -> Technique -> Transport

| Element | Technique | Transport | Reuse map |
| --- | --- | --- | --- |
| Warm grey studio background, floor, shadows | Procedural gradient/shadow generator | Texture output | Invent scene glue |
| Main organic folded ribbon with many rib lines | Semantic Y-up path handles -> `PNode` ribbon path -> folded ribbon renderer | StructuredBuffer records into texture renderer | Invent reusable candidate |
| White spheres, black sphere, striped oval, chrome ring, blue bars, black square, glass capsules, fine guides | `ShapeRecord` placement generator -> shape renderer | StructuredBuffer records via data links | Invent reusable candidate |
| Right triangle-pattern column | `TriangleRecord` grid generator -> triangle renderer | StructuredBuffer records via data links | Invent reusable candidate |
| Motion bus | Four LFO control outputs for signal-driven params | Control outputs + expressions | Adapt `fui_dashboard` signal |
| Final composition | Ordered blend using luminance masks, soft shadows, bloom-ready highlights | Texture inputs 0-4 | Invent project glue |
| Finish | Existing post stack if needed | Texture input | Reuse `modules/post` |

## Module Graph

```text
abstract_bg ----------------------------\
abstract_signal --expressions------------> abstract_ribbon_path
abstract_signal --expressions------------> abstract_ribbon
abstract_ribbon_path -> abstract_ribbon --\
abstract_triangle_gen -> triangle_render  -> abstract_comp -> post
abstract_shape_gen    -> shape_render ---/
```

The hard/repeated poster objects are data-buffer lanes. Placement lives in generator modules; renderers consume records and do not own hardcoded object positions. The ribbon is now also data-driven: `abstract_ribbon_path` owns semantic form handles and emits a previewable path buffer; `abstract_ribbon` shades the folded material around that path.

All artist-facing placement pads are authored as Y-up controls. Generators convert to UV/Y-down only when emitting records for screen-space renderers. This matches the `fui_dashboard` world-space control convention and avoids inverted Y dragging.

## Lane Contracts

- Shared resolution: 1024 x 1280 portrait.
- `abstract_bg`: generator, output RGBA16F.
- `abstract_signal`: generator, output preview texture + control outputs `pulse`, `sweep`, `beat`, `slow`.
- `abstract_ribbon_path`: generator, output preview texture + `Ribbon Path` data port, 160 x 48-byte `PNode`.
- `abstract_ribbon`: data consumer, output RGBA16F, black outside the ribbon.
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
4. Wire data lanes first: ribbon path -> ribbon render, shape gen -> shape render, triangle gen -> triangle render.
5. Wire texture outputs into `abstract_comp`, then `abstract_comp` into `post`.
6. Register `abstract_signal` expressions with `sentinel_expression`, not raw state strings.
7. Auto-layout the graph and verify `compile_status`, `info.stats.healthy`, preview SRVs, expression list, and frames processed.
8. Capture intermediate layers and the final post output, then checkpoint the project bundle.

## Harvest Notes

Reusable candidates: the Y-up ribbon path -> material renderer pair, and the signal bus adaptation. The column, accent, and compositor modules are reference-specific glue unless a second poster needs the same contracts.
