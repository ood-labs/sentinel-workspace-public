---
name: modular-scene-authoring
description: Author Sentinel scenes as a modular Module graph of separable generator, data-lane, renderer, compositor, and post nodes wired by typed data ports, instead of one monolithic shader. Use when recreating a reference image or building a complex scene, choosing a data contract from the reference's structure (routing/poster vs organic vs atlas), wiring producer/consumer structured buffers, preserving route/group ids across segment records, or running the compile-check to force-reload to capture iteration loop.
distribution: true
---

# Modular Scene Authoring (Module Graph Patterns)

Build a scene as a graph of small, semantic Module nodes that pass typed data and texture lanes to each other, rather than one giant shader that does everything. This is how Sentinel's Module system (`data_inputs` / `data_outputs`, zero-copy SRV routing, control outputs) is designed to be used. A monolith is hard to inspect, hard to iterate, and hides the design structure; a graph of named nodes lets you prove each stage, swap a renderer without touching the generator, and tune one contract at a time.

For manifest syntax, HLSL compiler name mappings, structured buffer I/O, and hot-reload mechanics, use the `module-authoring` skill and `docs/knowledge/module-pipeline.md`. This skill is about the workflow and graph decomposition on top of those mechanics.

In-repo modular graphs worth reading before starting: `shaders/projects/mux_demo/`, `projects/switcher_demo.sentinel`, `shaders/projects/hstack_3/`, `shaders/projects/compositor/`.

---

## Precise construction blueprints

When a scene is mostly objects with real dimensions, anchors, clearances, and repeated instances, use the `procedural-geometry-authoring` skill and the Phase 76 blueprint compiler before writing custom generator shaders.

Blueprint producers compile to generated Module projects that publish fixed 48-byte `PNodes`. Wire those records into `shaders/projects/sdf_scene_render`, run `sentinel_graph auto_layout`, then prove the graph with:

- `sentinel_blueprint validate` for schema and relation errors.
- `sentinel_blueprint solve_report` for record hashes, topology, solver stats, and warm-start stability.
- `sentinel_blueprint audit` when a `<blueprint-stem>.audit.yaml` sidecar exists.
- `tools/blueprint_spotcheck.py` and `tools/check_overlaps.py` for independent record-level checks.
- A renderer capture plus `sentinel_vision action="eval"` for visible scene claims. If it reports a missing or rejected key, run `sentinel_vision action="status"` and have the user paste their provider key (OpenRouter or another OpenAI-compatible provider) into the returned workspace `vision.json` `api_key` field, then rerun `status` until `key_present` and `key_ok` are true. Never take keys through chat or tool arguments.

The canonical smoke scene is `examples/blueprints/cafe.yaml`. From skill text alone, validating it should return `ok: true`, `node_count: 14`, `group_instance_count: 6`, `resolved_instance_count: 20`, and `instance_budget: 96`.

---

## Design bar: build a graph of semantic nodes

A good modular scene reads as a pipeline of responsibilities:

- **Generator nodes** publish stable data or texture lanes (a grid, a point cloud, an atlas).
- **Expansion / assembly nodes** convert high-level plans into renderable records (routes into segments, splines into cones).
- **Render nodes** draw masks, geometry, or scene layers from those records.
- **Compositor / post nodes** finish the image (additive/subtractive composition, cleanup, grade).

Minimum standards:

- Each generator stays independently inspectable with a cheap preview and a `capture_data_port` proof. If you cannot prove a node's output on its own, it is doing too much.
- Save the project before any major graph or buffer-contract change. Keep a snapshot of the last working state so a failed contract change is one reload away from recovery.
- Judge the actual image the pipeline produces. Capture the output early and often and let the picture drive the next edit.

---

## Design-led contracts: pick the data shape from the reference

The single most important decision is the data contract, and it follows from the structure of the reference image. Do not force every reference into a texture atlas or into hand-authored curves.

Three common archetypes:

- **Routing / poster graphics** (angle systems, lanes, hard geometry):
  `grid/lane records` produced by a plan node, then `route specs`, then expanded `segment records`, then mask renderers and a compositor. This is a routing/layout problem.
- **Organic / biomorphic scenes** (flesh, growth, fluid forms):
  `spline / point / cone records` plus `material ids`, plus quality controls for ray steps and shadow steps.
- **Atlas / instance systems** (many repeated stamps):
  an `atlas texture`, an `atlas metadata` buffer, a `placement / instance` buffer, then a spawner or scene renderer.

If the reference is a routing problem, an atlas will fight you the whole way, and vice versa. Choosing the wrong contract is the most expensive mistake in this workflow, so name the archetype out loud before building.

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

## Parameter design: controls must change structure

Use typed controls, and make every one visibly matter:

- `enum` for presets and modes, `int` for true counts, `float` for precise fractional controls, `point2D` for pan/offset, `color` for colors. (See `module-authoring` for the fixed int/enum/bool cbuffer path.)
- A seed, preset, or mode must change whole route structures or families, not add tiny jitter. If a control barely changes the image, redesign it. Useful controls for a routing scene: route preset, route density, expanded-canvas scale/offset, width scale, and explicit accent pattern controls.
- Avoid hidden randomness where the user needs direct control. For a "one large dash" look, expose `dash_count` (precise float range) and `dash_offset` (explicit 0..1 phase) instead of silently hashing route ids into a phase.
- Keep experimental controls default-off when they can damage the design language. Do not apply organic sine displacement or wavy paths to a hard graphic-design reference; controlled width profiles and rounded joins are a different language from noise.

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
10. **Checkpoint the working state.** `sentinel_capture action=checkpoint pipeline_id=<id>` saves a bundled `.sentinel`, captures the output image, and records the graph profile in one call, writing a `summary.md` proof folder. Use it whenever a look is worth keeping.

After creating pipelines and wiring links, always run `sentinel_graph auto_layout` (nodes spawn at 0,0 and stack otherwise); on a hand-arranged graph prefer `layout_neighborhood`.

---

## Keep the graph, don't collapse it

A finished modular scene is more valuable as an editable show project (a bundled `.sentinel` with `modules/<id>/` folders) than as one collapsed Module. The graph is the thing the artist tunes and the next agent inherits. Save with `save_project bundle_modules=true` (or the checkpoint action) so the show travels with its real Module files.

## Motion vocabulary

For scene motion, use the Phase 75 shared vocabulary from `docs/knowledge/motion-choreography.md` and `shaders/projects/_shared/anim/anim.hlsli`. Do not hand-roll independent spring or stagger equations in renderer nodes. Keep rate-driven timelines on accumulated phase, and use retarget stamps plus `an_spring_v` when a cue jump or target change must remain continuous.

---

## Cross-links

- `module-authoring` skill: manifest syntax, compiler name mappings, structured buffer I/O, hot-reload, control outputs.
- `docs/knowledge/module-pipeline.md`: data ports, `resolution_source`, bundling, write-order gotcha.
- `laser-content-authoring` skill: multi-output Module composition and HStack routing, a concrete instance of this modular approach.
