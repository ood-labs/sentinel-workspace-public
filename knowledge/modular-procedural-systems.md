# Modular Procedural Systems

Use this contract when a Sentinel scene is a system of editable generators, structured data, and downstream renderers rather than one self-contained visual effect. The canonical example is `projects/procedural_building_system/`.

## 1. Decompose by semantic authority

Give each node one responsibility that remains useful on its own:

- plan or massing;
- expansion or facade generation;
- material records;
- lighting records;
- renderer;
- optional post or AI interpretation.

Name the node after the concept the artist edits, not the implementation technique. A node boundary should correspond to a reusable contract, an inspectable intermediate result, or an independently tunable concern.

## 2. Make structured data the source of truth

Publish typed buffers for semantic records and keep producer and consumer schemas byte-for-byte identical. Put stable ids, dimensions, transforms, type/material ids, active flags, and any grouping needed by downstream nodes into the records.

Do not make the preview texture the hidden source of architectural truth. The preview explains the records; data links carry them.

When several nodes use the same geometry, wire the same producer records to all of them. Do not reconstruct a second approximate building in the facade, lighting, or renderer node.

## 3. Require an honest preview from every node

Every generator, plan, facade, material, lighting, or transform node must render a meaningful preview of its own current records. A preview should reveal spatial arrangement, type, grouping, selection, or material response well enough to diagnose that stage without opening the final renderer.

`has_preview_srv=true` is necessary but not sufficient. Blank, generic, constant, misleading, or illegible previews block downstream work.

## 4. Split Canvas interaction from Properties tuning

Use Canvas for tasks whose meaning is spatial:

- selecting and moving masses;
- rotating a logical object;
- positioning a facade feature against the elevation it changes;
- placing important lights in plan.

Keep dense numeric and color tuning in Properties. Do not duplicate every parameter as an authored slider rail merely to make the Canvas look like a control panel. Properties already provide reset, range editing, OSC, expressions, presets, undo, and compound color/XY widgets.

Only add authored sliders when their visual placement is part of the experience and their render/hit rectangles remain correct at every supported panel extent.

## 5. Use one coordinate transform for render, pick, and drag

For every spatial editor:

1. define one normalized edit rectangle;
2. map semantic/world state into that rectangle for rendering;
3. publish selection descriptors at those rendered coordinates;
4. evaluate picks against those same coordinates;
5. invert the same mapping when committing a drag.

Do not independently eyeball preview placement and interaction placement. A marker that selects the wrong facade cell is a contract failure even when both pieces look plausible alone.

Keep drag ownership from pointer-down through commit/cancel. Store logical state in declared state buffers so save/reload, presets, and undo restore meaningful edits.

When a canvas layout changes, migrate persistent normalized state once or store state in semantic/world coordinates so it naturally remaps into the new rectangle.

## 6. Keep the interface quiet and aspect-tolerant

Use a dark monochrome baseline with one restrained accent unless the project calls for a distinct palette. Let the actual plan/elevation/material/light field fill the available Canvas after the header. Prefer a small tool strip plus direct manipulation over permanent side rails.

Derive stroke, label, and handle sizes from `_Resolution`. Re-evaluate the canvas at multiple aspect ratios, but do not invent a second responsive-layout system inside HLSL if Sentinel's hit rectangles cannot follow it.

## 7. Choose exactly one camera owner

Use either the renderer's native camera or a deliberate external `camera`/`camswitch` node. Do not add renderer-authored Hero, Architectural Orbit, or alternate ray modes when the host already provides Fly and Orbit navigation.

For an internal camera, save Fly as the default unless the example specifically teaches another owner. Construct rays from `_InvViewProjMatrix` and `_CameraPos`; do not maintain a parallel camera equation in the shader. Never expose camera rows on the Scene Group.

## 8. Publish consumer-specific output lanes

A renderer may use linear HDR internally while still publishing display-safe outputs:

- keep shading and accumulation in `RGBA16F` when needed;
- publish tone-mapped, sRGB-encoded `RGBA8` color for normal video consumers;
- publish native camera-aligned depth separately when a downstream node needs structure.

Color and depth are different contracts. Never send a duplicate color image into a depth ControlNet input.

## 9. Treat AI as an optional interpretation layer

The procedural graph must remain useful without AI engines. Validate geometry, materials, lighting, camera, color, and depth before adding StreamDiff.

For depth-conditioned StreamDiff:

- connect sRGB color to Video Input;
- connect color to Style Reference only when wanted;
- connect native renderer depth to Control Image;
- select Depth ControlNet and disable automatic depth;
- use `hold=false` for live camera work;
- use `frame_skip=1` when the target GPU supports it.

Save a successful setting snapshot, but describe the AI branch honestly. It may add useful realism while relaxing exact facade fidelity.

## 10. Build and prove one node at a time

For each semantic node:

1. author and `compile_check` it;
2. create or reload only that node;
3. place it beside its neighbor and add the known typed links;
4. inspect health, schemas, counts, and frames;
5. focus and open its preview;
6. exercise its spatial interaction or a structural Property;
7. fix the preview before continuing.

After the graph is complete:

- confirm every active Module compiles;
- verify every pipeline is healthy with advancing frames;
- inspect structured-buffer counts and sample records;
- prove picks at the exact visible handles;
- capture every important intermediate Canvas;
- capture display color and auxiliary outputs separately;
- profile the graph;
- save with only active, portable Module paths;
- document which branches are core and which are optional experiments.

## Reference graph

`procedural_building_system` demonstrates the complete pattern:

```text
massing records ─┬─> facade records ─┐
                 ├─> lighting records ┤
                 └─────────────────────┤
material records ──────────────────────┤
                                       v
                              renderer: sRGB + depth
                                       |
                                       v
                              optional StreamDiff
```

Its final UI decision is intentional: canvases manipulate spatial objects, while Properties own dense parameter editing.
