# 2026-07-04 - Modular Poster V3 Workflow

## Context

Built a Sentinel Module graph to recreate a black-and-white abstract poster reference using modular data lanes instead of one monolithic shader. The final working project is saved at `projects/poster_modular_graphic_v3/poster_modular_graphic_v3_final_working.sentinel`; the current editable project is `projects/poster_modular_graphic_v3/poster_modular_graphic_v3.sentinel`.

## What we did

- Saved the failed earlier approaches before replacing them:
  - `projects/poster_modular_graphic_v3/poster_modular_graphic_v3_pre_expanded_grid.sentinel`
  - Earlier V2 and atlas attempts were kept under `projects/poster_modular_graphic_v2/` and `projects/poster_modular_graphic/`.
- Built a six-node graph:
  - `Poster_V3_Grid_Plan`: grid nodes plus route specs.
  - `Poster_V3_Route_Expander`: route specs to segment records.
  - `Poster_V3_Slab_Mask_Renderer`: white slab, black cut, thin white, thin black masks.
  - `Poster_V3_Accent_Renderer`: continuous route accents from segment data.
  - `Poster_V3_Compositor`: additive/subtractive mask composition.
  - `Poster_V3_Crisp_Post`: final cleanup.
- Expanded the grid contract after the core look worked:
  - `Grid Nodes`: 1488 records.
  - `Route Specs`: 64 records.
  - `Segment Records`: 192 records.
  - `Route Density`: max 64.
  - `Layout Scale`: 0.35 to 2.8.
  - `Global Offset`: -0.9 to 0.9.
- Preserved the first 20 authored routes and added procedural extra routes above density 20 so existing useful seed/preset combinations still mattered.
- Fixed `global_offset_x` direction in `modules/poster_v3_grid_plan/compute_nodes.hlsl`.
- Reworked `Poster_V3_Accent_Renderer` so accents render per continuous route, not per segment.
- Added precise accent pattern controls:
  - `dash_count`: float, 0.0 to 2.0.
  - `dash_offset`: float, 0.0 to 1.0.
  - deterministic dash phase, no hidden per-route random offset.
- Captured proof images in `projects/poster_modular_graphic_v3/captures/`.

## What we learned

- The successful workflow was modular, but only after the data contracts matched the actual design structure. The useful graph was `grid -> routes -> segments -> masks/accent -> compositor -> post`.
- The failed atlas attempt was not a good fit for this poster. The reference is a routing/layout problem, not a tile-stamping problem.
- Hand-authored loose Bezier paths read as random scribbles. This style needs an aspect-correct constrained grid with only horizontal, vertical, and 45-degree diagonals.
- Aspect correctness matters: a visually 45-degree route on a 900x1600 canvas needs row pitch = column pitch * 900/1600.
- Downstream renderers should not repeat global layout transforms. One layout transform should happen where the coordinate system is generated.
- Seed parameters must produce materially different structure, not tiny jitter. Useful controls are route preset, route density, expanded-canvas scale/offset, width scale, and accent pattern controls.
- Do not apply organic sine displacement to a hard graphic design reference. Controlled width profiles and rounded joins are different from wavy paths.
- Accents must operate on continuous route groups, not individual segment records. Per-segment taper/rounding creates visible breaks and destroys the line language.
- For "one large dash" workflows, dash count should be a precise float range and dash offset should be explicit.

## Decisions made

- Treat the poster as a structured routing system:
  - grid records define possible positions;
  - route records define logical paths;
  - segment records are an implementation detail;
  - renderers should recover route continuity when the visual depends on a route.
- Keep black/white construction additive/subtractive:
  - white slab masks add territory;
  - black cut masks carve lanes;
  - accents are separate so they can be refined without disturbing the main composition.
- Keep the final V3 graph as an editable show project rather than collapse it into one Module.
- Preserve project snapshots before major contract changes.

## MCP/tooling improvements requested by this workflow

- A typed bulk parameter snapshot/restore tool for one or more pipelines. This would avoid manually reading values before temporary tests.
- A route/geometry buffer inspector that can validate constraints such as "all segments are 0/45/90 degrees" and report offending records.
- A visual diff or side-by-side capture helper optimized for creative iteration, including current parameter overlays.
- A graph-level "contract migration" helper that updates producer buffer counts and all consumers that loop over those counts.
- A module parameter schema diff that highlights changed parameter type/range/default and whether live values were preserved or clamped.
- A project checkpoint command that saves a named `.sentinel`, bundles modules, captures the final output, and records graph profile in one call.
- A data-port preview helper for structured buffers that can render route groups, segment groups, ids, and active flags without writing a custom preview pass.
- Better support for route/group semantics in structured buffers: group count, records-per-group, and a way for downstream nodes to discover grouping metadata.
- Faster compile/reload orchestration for multi-node contract changes: reload in dependency order and report all compile failures together.

## What's next

- Continue tuning the V3 poster by adjusting route density, route preset, seed, layout scale/offset, slab width, and accent dash controls.
- Consider a future `Route Group Metadata` buffer if more downstream nodes need route-level behavior.
- Consider adding a dedicated route-debug Module that colors route groups and labels active route ids.

## Open questions

- Whether the expanded procedural routes above route 20 should stay purely generated or become a second authored route family.
- Whether `Poster_V3_Slab_Mask_Renderer` should also gain route-continuous rounded corner behavior, or whether hard bevels should remain the default for the main slab language.
- Whether a reusable "poster routing" module template should be extracted from this project.
