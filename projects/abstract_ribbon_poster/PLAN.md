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
| Main organic folded ribbon with many rib lines | Aspect-correct screen-space parametric ribbon field, nearest-curve sampling, angular palette | Texture output | Invent reusable candidate |
| White spheres, black sphere, striped oval, chrome ring | Procedural SDF solids and polar rings | Texture output | Adapt `hud_orbits`/`hud_gauge` math |
| Right triangle-pattern column | Procedural triangular tiling clipped to tall rectangle | Texture output | Invent scene glue |
| Blue vertical/horizontal bars, black square, fine orbit lines, glass capsules | Procedural rect/segment/chrome accents | Texture output | Adapt `hud_panels`/`hud_leaders` style |
| Final composition | Ordered blend using luminance masks, soft shadows, bloom-ready highlights | Texture inputs 0-4 | Invent project glue |
| Finish | Existing post stack if needed | Texture input | Reuse `modules/post` |

## Module Graph

```text
abstract_bg        \
abstract_column     \
abstract_solids      \
abstract_accents      -> abstract_comp -> post
abstract_ribbon     /
```

The layers are deliberately texture-only. There is no data-buffer lane in this reference because the elements are not addressable widget fields; they are large poster forms whose controls are better exposed as typed module parameters.

## Lane Contracts

- Shared resolution: 1024 x 1280 portrait.
- `abstract_bg`: generator, output RGBA16F.
- `abstract_ribbon`: generator, output RGBA16F, black outside the ribbon.
- `abstract_solids`: generator, output RGBA16F, black outside solids/glints.
- `abstract_column`: generator, output RGBA16F, black outside right column.
- `abstract_accents`: generator, output RGBA16F, black outside accents/fine lines.
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
