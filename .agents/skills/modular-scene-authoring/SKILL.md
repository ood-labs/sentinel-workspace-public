---
name: modular-scene-authoring
description: Author Sentinel scenes as a modular Module graph — separable generator, data-lane, renderer, compositor, and post nodes wired by typed data ports — instead of one monolithic shader. Use when recreating a reference image or building a complex scene. Covers the mandatory design-first workflow (decide 2D-vs-3D, composite-vs-single-scene, and the transport per element before building), composing structured-buffer / texture-field / atlas / control-output lanes, and — for dense instanced HUD/FUI scenes — the reusable data-driven cloner kit (pl_grid→pl_path→pl_spawn→pl_render + prim_atlas) stamped many times, with per-chain previewable rendering, shared control sources, signal-bus motion, and point2D pads. Also preserving route/group ids, the compile-check→force-reload iteration loop, and harvesting reusable techniques into the library afterward.
distribution: true
---

# Modular Scene Authoring (Module Graph Patterns)

Build a scene as a graph of small, semantic Module nodes that pass typed data and texture lanes to each other, rather than one giant shader that does everything. This is how Sentinel's Module system (`data_inputs` / `data_outputs`, zero-copy SRV routing, control outputs) is designed to be used. A monolith is hard to inspect, hard to iterate, and hides the design structure; a graph of named nodes lets you prove each stage, swap a renderer without touching the generator, and tune one contract at a time.

Every build is also an investment: the modules you author become **reusable tools** for the next scene. So you work library-aware — consult what already exists, invent what doesn't, and harvest the genuinely reusable pieces back into the toolkit when you finish. Over time this turns a pile of one-offs into a navigable palette of techniques you can compose to tackle anything.

For manifest syntax, HLSL compiler name mappings, structured buffer I/O, and hot-reload mechanics, use the `module-authoring` skill and `docs/knowledge/module-pipeline.md`. This skill is about the workflow, graph decomposition, and technique selection on top of those mechanics.

---

## How to operate: plan first, then build autonomously

When asked to build a scene — even from a bare "make this" — **do not start writing shaders.** Produce the design plan first (see Phase 0). This is mandatory, not optional. The plan is a written artifact you make and act on; it is **not** an approval gate. Once the plan and the creative decisions are down, **proceed autonomously** — create modules, wire, prove, tune — without stopping for sign-off at each step.

- **Make the creative decisions up front.** Decide the architecture, the technique per element, the palette/mode direction, and the motion model in Phase 0, so execution is mostly mechanical follow-through.
- **The user steers mid-flight.** They can interject to redirect at any time; you don't pause to ask permission to continue.
- **Divert deliberately, not by drift.** If you discover something better while building — a technique that reads stronger, a simpler graph — it's fine to stop, note the change, and divert. That is a conscious decision recorded in the plan, not silent scope creep.
- **When genuinely blocked** on a creative fork you cannot resolve from the reference (e.g. output target unknown, or two equally-valid directions), ask one sharp question, then continue.

---

## Phase 0: Analyze & design before building

The most expensive mistake in this workflow is choosing the wrong structure, and structure comes from the reference, not a favorite technique. Before any code, work the reference through these four steps and write them down.

### 1. Settle the architecture axes

These are orthogonal decisions that shape the whole graph. Name each one explicitly:

- **2D screen-space ↔ 3D world-space.** Flat layered passes, or a raymarched/rasterized 3D scene with a shared camera? This is the first fork and it changes everything downstream.
- **Composite-of-layers ↔ single-scene-with-materials.** Do many render nodes each draw a layer that a compositor blends, or does all geometry feed **one** scene pass that shades everything under shared lighting/occlusion? (See *Architecture forks* below for when each is right.)
- **Transport per element** — the core decomposition. Break the reference into its visual elements and assign each the right technique + transport (see *The technique palette*). One scene routinely **mixes** transports; that's expected, not a smell.
- **Motion model.** Self-animating (driven by injected `_Time`), reactive-ready (control outputs + exposed params for audio/OSC), or static. Default to self-animating + reactive-ready unless told otherwise.
- **Output target.** Screen/Spout raster (keep bloom/atmosphere/post), laser/vector (binary, vectorizable — see `laser-content-authoring`), or data. This gates whole families of technique.

### 2. The technique palette — transport per element

Pick the native technique for each element and mix freely in one graph. Choosing the wrong transport for an element is what makes a build fight you.

| Element kind | Technique | Transport |
| --- | --- | --- |
| Continuous organic field (terrain, contours, flow, fog, height) | domain-warped FBM / scalar field; derive isolines, gradients, warps **from** it | **float texture lane** (R32F / RGBA16F) via `set_input` |
| Hard, sparse, individually-addressable geometry (nodes, connectors, routes, arcs) | seeded/derived point & segment records; bezier-capable | **StructuredBuffer records** via `add_link` (zero-copy SRV data ports) |
| Repeated stamps / glyphs / text labels | atlas sample + per-instance placement | **atlas texture + placement/instance buffer** |
| **Dense field of many addressable widgets** (HUD/FUI dashboards, panels, dials, markers, reticles) | the **reusable cloner kit** — structure → [splines] → distribute → map+stamp, one renderer per cloner | **PNode placement buffers + primitive atlas + per-chain render layers** (see *the Layout Kit* below) |
| 3D volumetric form with shared lighting/occlusion | raymarched SDF scene, one material pass | **single scene node** (not layers) |
| Cross-module animation / reactivity | LFOs / trackers publishing scalars | **control outputs + `ref()` expressions** (a signal bus) |
| Cheap procedural chrome (rings, ticks, dust, stars) | procedural polar/hash | **procedural render node**, no data ports |
| Finish (bloom, vignette, grade, chroma, grain) | filter post-stack | consumes the composited scene |

**The elegance move — generate once, derive many.** Where several elements are level-sets or samples of the same underlying thing, author **one** producer (a height field, a route plan) and have multiple nodes *derive* from it (soft contours, gated accents, a warped grid, peak-placed points all read one field). Change the producer once and the whole scene re-coheres. This is what keeps a highly modular graph elegant instead of sprawling: complexity lives in parameters and derivations, not in node count.

### 3. Architecture forks — when each is right

- **Composite layers** when elements have *different visual languages* (contours vs glyphs vs bloom-nodes) and you want independent per-layer control, ordering, and post. Native to HUDs, posters, 2D motion graphics.
- **Single scene with materials** when elements *share space, lighting, and occlusion* and must interocclude under one camera. Native to 3D worlds. Splitting a coherent 3D scene into layers throws away the shared depth you built it for.
- **2D** when the reference is fundamentally flat/graphic; **3D** when parallax, real occlusion, or volumetric lighting is doing the work. Don't fake 3D with stacked 2D layers if the reference needs true depth, and don't raymarch a flat graphic.

### 4. Library-consult pass — reuse, adapt, or invent

Before authoring, consult `knowledge/technique-catalogue.md` (the map of the technique library in `modules/`). For each element in your decomposition, mark it:

- **reuse** `<module>` — an existing technique fits; wire it as-is.
- **adapt** `<module>` — harvest the math, keep your own contract.
- **invent** — nothing fits. Author a new module, and build it in its **reusable** form (generic name, mode enums, clean ports) — it's a future toolkit candidate from the start. Flag these; they're what you'll harvest at the end.

Don't be trapped by what exists. Reaching for a new technique the library lacks is how the toolkit grows. But don't reinvent a solved one either — that's what the catalogue prevents.

### 5. The plan deliverable

Write the plan before shaders. It contains: the architecture-axes decisions; the **element → technique → transport table**; a module-graph data-flow sketch (who produces what, texture lanes vs data links); the lane contracts (record layouts, element counts, texture formats); the reuse/adapt/invent map; and a build sequence that proves each stage before the next. Then build it.

---

## Design bar: build semantic nodes, not a monolith

A good modular scene reads as a pipeline of responsibilities:

- **Generator nodes** publish stable data or texture lanes (a field, a point cloud, an atlas).
- **Expansion / assembly nodes** convert high-level plans into renderable records (routes into segments, points into links).
- **Render nodes** draw masks, geometry, or scene layers from those records.
- **Compositor / post nodes** finish the image (additive/subtractive composition, cleanup, grade).

Minimum standards:

- Each generator stays independently inspectable with a cheap preview and a `capture_data_port` proof. If you cannot prove a node's output on its own, it is doing too much.
- Save the project before any major graph or buffer-contract change. Keep a snapshot of the last working state so a failed contract change is one reload away from recovery.
- Judge the actual image, not the shader idea. Capture the output early and often and let the picture drive the next edit.
- Treat the graph layout as part of the authored scene. A finished modular graph must be readable from left to right, with data producers, renderers, compositors, and post nodes in stable semantic columns.

### Granularity — split vs fuse

Split a responsibility into its own node when its output is **independently provable**, **reusable** elsewhere, or **swappable** (a renderer you'd replace without touching the generator). Fuse when a split would only produce a node that is never inspected or reused on its own. Max modularity is a means, not the goal — the goal is a graph a human can read and a next agent can extend. Expressiveness comes from typed params + mode enums + derivations, not from node count.

---

## Graph layout contract

For multi-branch scenes, layout is not cleanup after the fact. Design it with the graph:

- Put **plan/generator nodes** in the left column, **render/expansion nodes** in the next column, **compositor nodes** to the right, and **post/output nodes** at the far right.
- Keep repeated branches in the same vertical order everywhere. If the compositor inputs are `Background`, `Sunflower`, `Poppy`, `Lotus`, `Iris`, the visible node order should match those inlet rows.
- Create nodes with approximate `x`/`y`, wire by pin names, then use `sentinel_graph set_node_geometry` for the final authored coordinates. Use `auto_layout` only as a first pass for stacked newborn nodes; do not trust it to preserve a deliberate composition.
- Use `layout_neighborhood dry_run=true` before applying any local cleanup to an existing hand-authored graph. If it reports meaningful moves against already good bands, prefer manual `set_node_geometry`.
- Add annotation boxes manually with explicit `x/y/width/height` after node bounds are known. Avoid group-wrap helpers when the box needs to look polished.
- Verify with `sentinel_graph get summary=true`, a real Sentinel window screenshot, and the final output capture. A successful link command is not enough.

Reusable branch pattern:

```text
Species_Plan --data:Flower Elements--> Species_Render --texture--> Compositor slot N
Background -----------------------------------------------> Compositor slot 0
Compositor -----------------------------------------------> Post
```

This pattern was proven by the four-flower garden graph: four independently inspectable structured-buffer generators, four matching renderers, one compositor whose inlet order matched the vertical branch order, and a final post node.

---

## Compose transports — pick the shape per element

The data contract comes from the structure of the reference, not a preferred technique. Do not force every reference into a texture atlas or into hand-authored curves. Common shapes you compose per element:

- **Routing / poster graphics** (angle systems, lanes, hard geometry): `grid/lane records` → `route specs` → expanded `segment records` → mask renderers → compositor. A routing/layout problem.
- **Organic / field scenes** (terrain, flow, contours, fog): a scalar/vector **field texture** that downstream passes derive isolines, gradients, and warps from.
- **Volumetric / biomorphic** (flesh, growth, fluid 3D form): `spline / point / cone records` + `material ids`, with ray-step / shadow-step quality controls, resolved in one scene pass.
- **Atlas / instance systems** (many repeated stamps, glyphs): an `atlas texture` + `atlas metadata` buffer + `placement/instance` buffer, then a scene renderer.

A single scene usually combines several of these. Pick per element; name each choice in the plan.

---

## Precise construction blueprints

When a scene is mostly objects with real dimensions, anchors, clearances, and repeated instances, use the blueprint compiler before writing custom generator shaders (details in the `procedural-geometry-authoring` skill and `knowledge/precise-construction.md`). Blueprints compile to generated Module producers publishing fixed 48-byte `PNodes`; wire those into `sdf_scene_render`, then prove with `sentinel_blueprint validate` / `solve_report` / `audit`, plus a renderer capture and `vision_eval`. Author relations first, dimensions second.

---

## Choreographed motion

For staggered entrances, beat-locked pulses, and cue-driven scene hand-offs, use a `conductor` node plus a cue sheet (`sentinel_conductor load_sheet`) instead of ad-hoc LFO wiring, and the shared motion vocabulary in `modules/_shared/anim/anim.hlsli` inside modules. The `timeline_hud` module gives a live arrangement view during rehearsal. See `knowledge/motion-choreography.md`.

---

## Dense & instanced scenes: the Layout Kit (data-driven cloners)

**This is the default architecture for a dense field of many small addressable widgets** — a FUI/HUD dashboard, a control panel, a schematic, a reticle field. It is what separates a shallow first attempt (a handful of hand-placed elements in one shader) from a scene that reads like the reference. Two anti-patterns to avoid: **do not hand-place widgets in shader code** (opaque, uneditable, doesn't scale past ~15 things), and **do not render them all in one merged pass** (correct pixels, but every source node previews as a blank placeholder and you edit blind). Instead build from a **reusable placement kit you stamp down many times**, separating *where things go* from *what gets drawn*.

**The pipeline — one universal record, `PNode`, flows through every stage** (so any node chains to any other):

```
pl_grid ──► pl_path ──► pl_spawn ──► pl_render          (map each point → a primitive-atlas cell, stamp it)
(structure) (splines)  (distribute)      └► spline_render  (draw the paths themselves as strokes)
```

- **`pl_grid`** — the structure source. Modes: **Grid / Ring / Spiral / Scatter / Line / Border / Radial**, with count / rows·cols / rings / center / extent / radius / jitter / depth. Emits grouped, `u`-ordered anchor points. **This is the node you duplicate** — one instance per region (left panels = Grid, hero halo = Ring, marker field = Scatter, top row = Line, corner tabs = Border, connectors = Line/Grid → spline).
- **`pl_path`** — fits a Catmull-Rom curve through each group's anchors and resamples to points-along-the-curve with tangents. This is literally "draw splines within the grid, then spawn points on them."
- **`pl_spawn`** — jitter / decimate / branch the points for organic density on top of a structured source.
- **`pl_render`** — maps each `PNode` → a primitive (kind / scale / tier / rotation modes over an explicit kind-set) **and renders it to a full texture** with an atlas stamp + drifting-camera depth parallax. This node is the payoff — it is `pl_style`'s mapping and the renderer fused so the chain is previewable (rule 2 below).
- **`spline_render`** — draws the paths as glowing dashed strokes (data-driven connectors / leaders; the cousin of a segment-stroke renderer).
- **`prim_atlas`** — bakes N HUD primitives (rings, ticks, reticles, boxes, brackets, warning triangle, bars, hatch, glyph-blocks, mini-dials, markers…) into one grid texture **once**; every renderer stamps cells from it. Adding vocabulary = add an atlas cell, reference its index in a kind-set.

**The three rules that make this work:**

1. **Compose the same kit many times, differentiated only by params.** A dense scene is ~6 `pl_grid → [pl_spawn] → pl_render` chains plus a `pl_grid → pl_path → spline_render` connector chain. One kit, many node instances, no new shaders. Changing one `pl_grid` mode re-forms a whole region. This is the instanced-scene form of *generate once, derive many*: one placement kit, many configured cloners.
2. **Render per-chain — never merge into one monolith.** Each cloner gets its **own** `pl_render` so **its node preview shows exactly what it draws**; you select it and tune it live (add a boundary, change the kind-set, move the grid) and watch that layer. A single renderer that consumes every placement buffer at once is correct but leaves every upstream node a blank solid-colour placeholder — you're editing blind. A wide **additive compositor** sums the per-chain layer textures. (A merged `widget_render` + buffer-only `pl_style` exist for the rare "one big pass" case; default to `pl_render`.)
3. **3D via depth, not stacked layers.** Give each `PNode` a depth; `pl_render` projects it through a slowly drifting camera → real parallax + depth fog. Far widgets recede into haze, near ones read sharp — all from one flat kit, no separate 3D scene.

**Cohesion patterns — make the scene feel like one instrument, not scattered parts:**

- **Shared control source.** When two nodes must move together (a bespoke hero dial + its cloner-halo; a `25%` label + the dial it annotates), never duplicate the position. Publish it once from a tiny control node — a **`focal` node** with a `point2D` pad → `x`/`y` control outputs — and drive both consumers with `ref()` expressions, converting coordinate spaces inside the expression where they differ (e.g. world→UV: `0.5 + ref("focal/control_outputs/x") * (1/(2*aspect))`). One pad now moves the whole focal point as a unit.
- **Signal bus for motion.** A **`signal` node** runs a few LFOs (pulse / sweep / beat / slow) as control outputs; drive *many* params from it — a cloner's `angle_offset` (rotation), a layer's intensity (breathing / beat pulse), a value arc, a label glow. Motion authority lives in one node, so swapping `signal` for an audio/OSC source makes the whole scene reactive with zero rewiring. Apply it liberally — a still HUD reads as dead.
- **Boundary frame.** A cloner renderer can compute the bounding box of *its own* point cloud and draw a padded frame around it, so the gridded objects sit inside a titled module. Make it a per-chain toggle, generic to any cloner.

The exemplar modules live under the **Layout kit**, **Instancing / atlases / depth**, and **FUI / HUD chrome** sections of `knowledge/technique-catalogue.md`. Reach for this kit whenever the element count is high and the widgets are individually addressable; reach for a single procedural chrome node only for a *few* bespoke focal pieces (the hero dial, the globe) that deserve hand-authored detail.

---

## Routing graphics rules

For graphic-design references with obvious angle systems:

- Derive geometry from an aspect-correct grid. Lock route segments to the intended angle family (for example horizontal / vertical / 45-degree) before adding any variation.
- On a portrait canvas, a visual 45-degree diagonal needs the row pitch scaled by the canvas aspect (row pitch = column pitch times height/width). A naive equal pitch reads as the wrong angle.
- If the user needs to crop into a generated field, make the generated grid larger than the visible frame and expose wide scale/offset controls so they can pan and zoom within it.

---

## One layout transform, at the generator

Apply the layout transform (global offset, scale, aspect correction) exactly once, where the coordinate system is generated. Downstream renderers consume that same coordinate system and must not re-apply global transforms. Repeating a global transform in a consumer node double-applies it and produces drift that is painful to debug because each node looks locally correct.

---

## Continuous group rendering: routes vs segments

Distinguish **route records** (the logical path the user thinks about) from **segment records** (the transport/render implementation detail an expander produces). Visual behavior such as taper, dashes, rounded joins, and continuous accents belongs to the whole route, not to individual segments.

When a route expands to multiple segment records:

- Preserve a route/group id on every segment record.
- Downstream renderers that need continuity reconstruct route groups from those ids before drawing.
- Compute total route length and a global route coordinate `t` before applying dash or taper profiles, so the profile runs across the whole route.
- Apply rounded joins at interior route vertices, not caps at every segment endpoint. Per-segment taper or rounding creates visible breaks and destroys the line language.
- Avoid per-segment taper unless broken strokes are explicitly the intent.

If several downstream nodes need route-level behavior, add a small route-group metadata buffer (group count, records-per-group, id ranges) so consumers can discover grouping instead of re-deriving it.

---

## Parameter design: controls must change structure, and author for reuse

Use typed controls, and make every one visibly matter:

- `enum` for presets and modes, `int` for true counts, `float` for precise fractional controls, `point2D` for pan/offset, `color` for colors. (See `module-authoring` for the fixed int/enum/bool cbuffer path.)
- **Position with `point2D` XY pads, never separate `_x`/`_y` float sliders.** A pad reads and edits as one point. A `point2D` named `center` still exposes `center_x`/`center_y` state paths and appears in HLSL as `float2 center`, so **converting an existing float pair to a pad preserves its value and any expression** (the reload reports zero params added/removed). For a line/segment placement, expose an explicit **start and end `point2D`** (two draggable handles) rather than a center-plus-extent that distributes outward from the middle.
- A seed, preset, or mode must change whole structures or families, not add tiny jitter. If a control barely changes the image, redesign it.
- Avoid hidden randomness where the user needs direct control. For a "one large dash" look, expose `dash_count` (precise float range) and `dash_offset` (explicit 0..1 phase) instead of silently hashing ids into a phase.
- Keep experimental controls default-off when they can damage the design language. Do not apply organic sine displacement to a hard graphic-design reference.

**Author for reuse** (so the module earns a place in the library):

- Give reusable technique-modules a **generic name** (`field_gen`, not `topo_terrain`) and behavior selected by **mode enums**, so one module covers a family of looks.
- Keep the ports clean and the technique legible: a one-line header comment stating *what technique it embodies and its input/output ports*.
- Build for the current scene first; generalize on the second use. Reusable ≠ maximally abstract — it means well-named, well-parametrized, and catalogued. Don't gold-plate a technique into infinite configurability before a second scene has asked for it.

---

## MCP iteration loop

The tight loop for multi-node contract work:

1. `sentinel_app ping`, then `sentinel_pipeline list_types` and `sentinel_app capabilities` if starting fresh.
2. **Snapshot before you experiment.** `sentinel_state action=snapshot pipeline_id=<id>` returns the node's current params inline so you can revert a throwaway test with `sentinel_state action=restore` and no filesystem churn. Save the whole project (`save_project`) before large graph or buffer-contract changes.
3. Edit the Module files. **Write all shader files before saving `manifest.yaml`** (the file-watch hot-reload fires on the manifest save and fails if a referenced shader is missing; see `docs/knowledge/module-pipeline.md`).
4. `sentinel_pipeline compile_check project_dir=<dir>` for every touched Module before reloading anything.
5. `sentinel_pipeline force_reload pipeline_id=<id>` only after the compile checks pass.
6. Poll `sentinel_pipeline compile_status` to `ok`.
7. Confirm data schemas and element counts with `sentinel_pipeline get_data_schemas` before wiring, and after a contract change re-check that producer counts and consumer loop limits still agree.
8. Capture the final/post node and useful intermediate nodes. Use `sentinel_pipeline capture_data_port` to prove a structured buffer's contents (record counts, ids, active flags) rather than trusting the schema alone.
9. Profile with `sentinel_graph profile summary=true` to catch a node that dominates frame time.
10. **Checkpoint the working state.** `sentinel_capture action=checkpoint pipeline_id=<id>` saves a bundled `.sentinel`, captures the output image, and records the graph profile in one call. Use it whenever a look is worth keeping.

After creating pipelines and wiring links, run `sentinel_graph auto_layout` only to unstack newborn nodes, then immediately set the final authored positions with `sentinel_graph set_node_geometry`. On an existing hand-arranged graph prefer `layout_neighborhood dry_run=true` or manual geometry edits; global layout can destroy semantic bands.

Note: `save_project bundle_modules=true` copies referenced Module folders but **not** `modules/_shared/`. If your modules `#include` from `_shared`, copy it into the bundle (`projects/<show>/modules/_shared/`) or the bundled show won't compile standalone.

---

## Workspace layout: scratch, projects, modules

- **`scratch/`** — throwaway experiments and standalone tinkering. Never committed, never catalogued. This is where "let me try something" lives.
- **`projects/<name>/`** — structured scene builds, the workbench. Self-contained bundled shows. Creative work happens here.
- **`modules/`** — the **curated technique library**. Only harvested, documented, reusable techniques live here, each with a `knowledge/technique-catalogue.md` entry. Its `_shared/` holds common includes (fonts, os_text). Grows slowly and deliberately.

A finished scene is more valuable as an editable show project (a bundled `.sentinel` with `modules/<id>/` folders) than as one collapsed Module. The graph is the thing the artist tunes and the next agent inherits.

---

## Harvest: grow the toolkit

A build isn't done when the image is right — it's done when you've banked what you learned. At session close (`/wrap` or `/end-session`), run the **harvest gate**:

1. **Judge each new module: novel *and* reusable?** A reusable **technique** (an isoline extractor, a spline expander, a glyph-atlas renderer, a control-output signal bus) is worth banking. **Scene glue** (this compositor's exact input ordering, this scene's specific label strings) is not — it lives and dies with its project.
2. **For each keeper:** extract it from the project into `modules/` in reusable form, add its entry to `knowledge/technique-catalogue.md` (technique family, transport, what it does, compose-with), and it auto-tracks in git.
3. **Skip the rest.** Don't pad the library. A variant of an existing technique updates that catalogue entry's exemplars rather than adding a new one.

This is the one-way valve that keeps `modules/` a navigable toolkit instead of another undifferentiated pile. Reuse-vs-glue is the same distinction you drew in Phase 0's library pass — now you're closing the loop.

---

## Cross-links

- `knowledge/technique-catalogue.md`: the map of the technique library — consult it in Phase 0, extend it at harvest. For dense instanced scenes, read its **Layout kit**, **Instancing / atlases / depth**, and **FUI / HUD chrome** sections first.
- `module-authoring` skill: manifest syntax, compiler name mappings, structured buffer I/O, hot-reload, control outputs.
- `docs/knowledge/module-pipeline.md`: data ports, `resolution_source`, bundling, write-order gotcha.
- `laser-content-authoring` skill: multi-output Module composition and HStack routing for laser/vector output.
