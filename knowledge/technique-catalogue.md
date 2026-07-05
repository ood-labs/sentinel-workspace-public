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

## Control & reactivity

- **Control-output signal bus** — *compute → control outputs* · `signal` · one tiny module runs N
  LFOs (pulse / sweep / beat / slow) and publishes them as scalar control outputs. Other nodes
  *subscribe* via `ref("signal/control_outputs/<name>")` expressions — decoupling animation authority
  from the animated nodes, so swapping the source (LFO → audio/OSC) makes a scene reactive with no
  rewiring. The cleanest reuse pattern in the library. · *compose-with:* any parameter, via
  `sentinel_expression`.

## Compositing & finish

- **Post finish stack** — *filter* · `post` · chromatic aberration + multi-tap bloom + teal/orange
  split-tone grade + contrast/saturation + vignette + film grain; resolves to 8-bit. Reusable across
  raster scenes; tune thresholds per look. · *compose-with:* a composited scene.
- **Multi-layer compositor** — *pattern, usually scene-glue* · ordered additive/screen blend of layer
  textures with per-layer gains + optional viewport-mask clip. The *pattern* is reusable; a specific
  instance (which layers, what order) is usually project glue — rebuild per scene rather than
  harvesting. Promote only if a genuinely general compositor emerges.
