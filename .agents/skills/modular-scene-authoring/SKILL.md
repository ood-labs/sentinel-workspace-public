---
name: modular-scene-authoring
description: Author Sentinel scenes and procedural systems as modular Module graphs of separable generators, data lanes, editors, renderers, compositors, and post nodes wired by typed data ports. Use when recreating a reference image, building a complex or architectural procedural scene, choosing a data contract from the reference's structure, wiring producer/consumer structured buffers, preserving logical ids, or running the compile-check to live-proof iteration loop.
---

# Modular Scene Authoring (Module Graph Patterns)

Build a scene as a graph of small, semantic Module nodes that pass typed data and texture lanes to each other, rather than one giant shader that does everything. This is how Sentinel's Module system (`data_inputs` / `data_outputs`, zero-copy SRV routing, control outputs) is designed to be used. A monolith is hard to inspect, hard to iterate, and hides the design structure; a graph of named nodes lets you prove each stage, swap a renderer without touching the generator, and tune one contract at a time.

For manifest syntax, HLSL compiler name mappings, structured buffer I/O, and hot-reload mechanics, use the `module-authoring` skill and `knowledge/module-pipeline.md`. This skill is about the workflow and graph decomposition on top of those mechanics.

If one node is meant to be a complete control surface, editor, HUD, or dashboard, use the `module-ui-authoring` skill for that node. A UI Module can declare a full-bleed Canvas and `follow_panel` resolution while remaining one semantic node in the larger scene graph.

In-repo modular references worth reading before starting:
`projects/interaction_lab/interaction_lab.sentinel`,
`projects/scientific_organism/`, and `projects/living_room_sdf/`. Treat them as
architectural references, not runtime dependency libraries. For editable
procedural systems, read `knowledge/modular-procedural-systems.md` before
authoring.

---

## Precise construction blueprints

When a scene is mostly objects with real dimensions, anchors, clearances, and repeated instances, use the `procedural-geometry-authoring` skill and the blueprint compiler before writing custom generator shaders.

Blueprint producers compile to generated Module projects that publish fixed 48-byte `PNodes`. During visible authoring, prove the producer in its focused/open window before creating the renderer; then place the renderer beside it, wire the records, focus/open it, and prove the graph with:

- `sentinel_blueprint validate` for schema and relation errors.
- `sentinel_blueprint solve_report` for record hashes, topology, solver stats, and warm-start stability.
- `sentinel_blueprint audit` when a `<blueprint-stem>.audit.yaml` sidecar exists.
- `sentinel_blueprint solve_report` and `sentinel_blueprint audit` for independent record-level checks.
- A renderer capture plus `sentinel_vision action="eval"` for visible scene claims. If it reports a missing or rejected key, run `sentinel_vision action="status"` and have the user paste their provider key (OpenRouter or another OpenAI-compatible provider) into the returned workspace `vision.json` `api_key` field, then rerun `status` until `key_present` and `key_ok` are true. Never take keys through chat or tool arguments.

The public smoke blueprint is `examples/blueprints/living_room_architecture.yaml`; validate it before compiling or creating a live pipeline.

---

## Design bar: build a graph of semantic nodes

A good modular scene reads as a pipeline of responsibilities:

- **Generator nodes** publish stable data or texture lanes (a grid, a point cloud, an atlas).
- **Expansion / assembly nodes** convert high-level plans into renderable records (routes into segments, splines into cones).
- **Render nodes** draw masks, geometry, or scene layers from those records.
- **Compositor / post nodes** finish the image (additive/subtractive composition, cleanup, grade).

Minimum standards:

- Each generator stays independently inspectable with a cheap, meaningful preview and a `capture_data_port` proof. Open the node and verify that the preview actually decodes its current records; `has_preview_srv` alone is not proof. If you cannot understand a node's output on its own, fix its preview before continuing.
- Save the project before any major graph or buffer-contract change. Keep a snapshot of the last working state so a failed contract change is one reload away from recovery.
- Judge the actual image the pipeline produces. Capture the output early and often and let the picture drive the next edit.

### Visible, one-node-at-a-time construction

Author and create one semantic node at a time. Do not code every planned Module first, create several nodes concurrently, or hide creation inside a batch or loop. After the current node compiles and is wired, place it relative to its neighbor, call `sentinel_graph focus`, call `sentinel_pipeline open_window`, and inspect the live preview before authoring or creating the next node. Exercise at least one structural parameter and require an obvious preview change.

Do not use whole-graph `auto_layout` to repair a bulk-created pile. Use create-time `relative_to`, `place_relative`, or `layout_neighborhood` as each node enters the graph. Whole-graph `auto_layout` is only for an explicitly requested batch build or non-creative smoke test.

Generator, plan, layout, assembly, and data-transform nodes must visualize their active records and enough spatial/type/group/weight information to explain the intermediate state. Treat a blank, constant, generic, misleading, or illegible intermediate preview as a blocking authoring defect. A final renderer or buffer readback supplements this preview; neither replaces it.

### Editable procedural-system contract

For architectural and other multi-editor procedural systems:

- Keep semantic structure in typed records and feed the same source records to every consumer that needs them.
- Use Canvas for spatial manipulation and ordinary Properties for dense numeric/color tuning. Do not duplicate every parameter as a fragile authored slider rail.
- Derive render placement, selection descriptors, picking, and drag inversion from one edit-rectangle transform. A visible handle must pick the exact object or cell it appears to control.
- Keep logical edits in declared state buffers and preserve drag ownership through commit/cancel.
- For authored 3D, use the renderer's internal camera as the mandatory default and read `knowledge/internal-camera-template.md`. Declare `features: [camera]` plus `viewport.interactions: [camera]`, keep `camera_ref` empty, save Fly as the default, and do not invent Hero/Architectural Orbit shader modes. Use an external camera only when multiple separate 3D renderer nodes require one synchronized viewpoint or show-level switching.
- Keep HDR internal if useful, but publish 8-bit sRGB color for video consumers and a separate native depth lane for structural conditioning.
- Treat StreamDiff or other AI interpretation as optional. Prove the procedural renderer and auxiliary outputs first.

Use `projects/living_room_sdf/` for a dimensioned construction example, `projects/scientific_organism/` for a typed-data procedural composition, and `knowledge/modular-procedural-systems.md` as the reusable acceptance contract. Treat their node boundaries as architecture examples, not visual templates.

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

**Hybrids are normal.** A dense collage of technical panels wrapped around organic 3D masses is a routing problem *and* an organic problem. Do not run two parallel contracts: unify them under **one record buffer with a `role` discriminator**, so a single data link carries the whole plan and every consumer takes the records it cares about. `projects/matik_plate/` does this — one 128-record buffer where `role` separates instrument cells from organism anchors from a header record.

---

## Single plan authority

**One node owns placement. Every other node derives from its records and never re-decides them.**

This is stronger than "one layout transform, at the generator" below. The transform rule prevents drift; the authority rule is what makes a finished graph *rearrangeable*, because every question about where something is has exactly one answer. Rearrangement then falls out of the system instead of being a feature you build.

- Build the authority node **first**, in signal-flow order. It is usually not the fun node.
- Its preview becomes the diagnostic surface for the whole graph. Over-invest in it.
- Anything derivable from the records is derived, not republished as a second lane.

**The authority is a contract, not a template.** Fixed: single authority, persistent records, direct manipulation, an honest preview. Open — and yours to design per subject — the **projection**, the **verbs**, and the **readouts**. Ask what a draughtsman would draw for *this* thing. One front elevation suits a frontal arrangement and hides the subject of anything organised by depth, height, or extent along a path; reach for two orthographic strips sharing an axis, a section scrubbed along a path, a timeline, or a network view when that is what the thing is. Put the failure mode in the diagram too — self-intersection, leaving the frame, a mass escaping its container. `projects/sunward_corridor/modules/SC_Plan` is the bar for tailoring: plan over elevation on one z axis, the same handle editing both, and a flight line that turns red where the corridor bends through its own wall. Full guidance: `knowledge/reference-build-method.md` §2.5.

### Generate, then override

If the composition has an arrangement worth randomizing or exploring, the plan authority must be **directly manipulable** — not only when interaction is asked for. It must produce a **complete, good result procedurally**, and let interaction **override individual records** on top of it.

Select-and-move is close to universal; beyond that, design the edit verbs around the two or three properties that actually define an element in *this* subject rather than copying a keymap. Back it with a persistent buffer, an editor header record, and signature-driven regeneration. Study `projects/soft_vitrine/modules/VT_Plan` as the bar to clear — for how cheaply it lets you explore, and for a randomizer whose draws still read as compositions. A plan that offers only a seed and a variation slider is an **opaque plan**: it looks finished and is not.

**Decide what a re-roll means while inventorying, then randomize what actually carries the subject's identity.** Ask: *what relationships make this the thing it is?* If the answer is "none, these are objects on a plane", randomize coordinates — stratify, preserve the size hierarchy, done. If the answer names interlocking, containment, attachment, adjacency or periodicity, coordinates are not what the subject is made of: drawing them fresh per record destroys those relationships and every seed reads as debris, from per-record code that looks perfectly reasonable. Randomize the **relationships** instead — attach to a parent, host inside a container, derive extent from the host — and give the draw explicit guarantees (clamp both ways, bias toward compact, a fit pass that recenters and zooms the result into frame, temper extremes, cap contained families) so an arbitrary seed is presentable by construction. Gate every correction on `variation > 0` or it will nudge the transcription off its own coordinates. Worked case and the full checklist: `knowledge/reference-build-method.md` §3.

- The node is useful and unbroken from the first frame, before anyone touches it.
- Global parameters keep working after hand edits, because edits are deltas rather than a replacement authoring model.
- "Re-roll this record", "disable this one", "cycle its kind" become trivial, because a record already exists to mutate.

Regeneration must be **signature-driven** — hash the structural parameters plus an explicit algorithm-version constant, rebuild only when it changes — or hand edits die on every cook. The failure mode this replaces is the empty editor that renders nothing until fully hand-authored and whose global controls fight the edits.

### Derive magnitudes from upstream records

When a downstream node needs a size, spacing, or extent that relates to something upstream already decided, compute it from the upstream record geometry. Giving that node its own parallel parameter creates two numbers that must be kept in agreement by hand and that silently disagree at every setting nobody tested.

### Coverage and masking authority

- **Derive the mask from the records** wherever the records determine it. A compositor recomputing panel coverage from the same records the panels were drawn from cannot drift out of registration.
- **Publish a real coverage lane only where colour cannot carry the information** — an opaque black shape on a black background is undecidable by colour alone.

Do not smuggle coverage into a colour lane's alpha to avoid declaring an output; it makes the node's own preview read wrong and breaks the honest-preview contract.

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

### Exploration axes are shipped presets, not throwaway variants

When exploring alternatives, build the exploration axis as a permanent `enum` on the node that owns it rather than prototyping versions you intend to delete. Sweep it, capture each value, judge from the images, bake the winner as the manifest default, and **repair the losers instead of removing them**. Exploration cost then converts directly into product features, and a preset that lost on this reference is often the right answer for the next one. Record the verdict and the reasoning in the project README so the next agent does not repeat the search.

Two to four axes is the useful range, and a good axis changes structure — layout strategy, mesh style, growth mode. Palette and grade are not exploration axes.

### Scene Group control surfaces

Expose a curated top-level interface, not member-node internals. Start with roughly four to eight high-impact creative controls, counting a compound color or XY widget as one. Open the Scene Group Properties panel and test every exposed control; remove anything inactive, redundant, confusing, or implementation-level.

Never expose camera-related parameters (binding, mode, position, orbit, target, FOV, or renderer-local/internal camera rows) at Scene Group level. The internal renderer camera is the default owner; do not create an explicit `camera`/`camswitch` for a single renderer, several passes within one Module, or a renderer plus post-processing. External ownership is reserved for multiple separate camera-capable 3D renderer nodes that need a synchronized view or show-level switching. Prove the chosen owner through real interaction in the open renderer preview and visibly different captures.

---

## MCP iteration loop

The tight loop for multi-node contract work:

1. `sentinel_app ping`, then `sentinel_pipeline list_types` and `sentinel_app capabilities` if starting fresh.
2. **Snapshot before you experiment.** `sentinel_state action=snapshot pipeline_id=<id>` returns the node's current params inline so you can revert a throwaway test with `sentinel_state action=restore` and no filesystem churn. Save the whole project (`save_project`) before large graph or buffer-contract changes.
3. Edit the Module files. **Write all shader files before saving `manifest.yaml`** (the file-watch hot-reload fires on the manifest save and fails if a referenced shader is missing; see `knowledge/module-pipeline.md`).
4. `sentinel_pipeline compile_check project_dir=<dir>` for every touched Module before reloading anything.
5. `sentinel_pipeline force_reload pipeline_id=<id>` only after the compile checks pass.
6. Poll `sentinel_pipeline compile_status` to `ok`.
7. Confirm data schemas and element counts with `sentinel_pipeline get_data_schemas` before wiring, and after a contract change re-check that producer counts and consumer loop limits still agree.
8. For the current node, call `sentinel_graph focus` and `sentinel_pipeline open_window`; visually inspect its live preview and exercise a structural control before creating the next node. Fix an uninformative preview immediately.
9. Capture the final/post node and useful intermediate nodes. Use `sentinel_pipeline capture_data_port` to prove a structured buffer's contents (record counts, ids, active flags) rather than trusting the schema alone.
10. Profile with `sentinel_graph profile summary=true` to catch a node that dominates frame time.
11. **Checkpoint the working state.** `sentinel_capture action=checkpoint pipeline_id=<id>` saves a bundled `.sentinel`, captures the output image, and records the graph profile in one call, writing a `summary.md` proof folder. Use it whenever a look is worth keeping.

During visible construction, place and inspect each node before proceeding. Use `layout_neighborhood` for local cleanup; reserve whole-graph `auto_layout` for explicit batch work.

---

## Keep the graph, don't collapse it

A finished modular scene is more valuable as an editable show project (a bundled `.sentinel` with `modules/<id>/` folders) than as one collapsed Module. The graph is the thing the artist tunes and the next agent inherits. Save with `save_project bundle_modules=true` (or the checkpoint action) so the show travels with its real Module files.

## Motion vocabulary

For scene motion, use the shared vocabulary from
`knowledge/motion-choreography.md`. Bundle any HLSL motion helper with the owning
project. Do not hand-roll independent spring or stagger equations in renderer
nodes. Keep rate-driven timelines on accumulated phase, and use retarget stamps
plus `an_spring_v` when a cue jump or target change must remain continuous.

---

## Cross-links

- `knowledge/reference-build-method.md`: the end-to-end method for building a specific ambitious result from a reference — inventory, plan authority, generate-then-override, exploration presets, converge and prove. Read it before starting a from-scratch build.
- `module-authoring` skill: manifest syntax, compiler name mappings, structured buffer I/O, hot-reload, control outputs.
- `knowledge/module-pipeline.md`: data ports, `resolution_source`, bundling, write-order gotcha.
- `laser-content-authoring` skill: multi-output Module composition and HStack routing, a concrete instance of this modular approach.
