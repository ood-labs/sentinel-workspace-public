# Precise Construction (Blueprints, Layout Solver, SDF Audit)

Precise construction turns a semantic YAML blueprint (objects, relations, clearances) into a generated Module that publishes flat 48-byte `PNodes` records for `sdf_scene_render`. Use it whenever a 3D scene is mostly objects with real dimensions and relationships: chairs tucked under tables, machines seated on counters, clear aisles, lamps facing a street. Hierarchy and relations resolve at compile time; the renderer contract never changes.

## When To Use Which Lane

- Pattern scatter and organic layouts with no hard relationships: the layout kit (`pl_grid`, `pl_spawn`, `pl_path`).
- Scenes with dimensions, adjacency, support, clearances, or audit requirements: a blueprint through `sentinel_blueprint`.
- Single hero objects with exact dimensions: hand-authored CSG modules (see `procedural-geometry-authoring`), optionally with an audit sidecar.

## Blueprint IR

Top-level fields: `metadata` (`name`, `bounds`, `instance_budget`), `anchors[]` (named points with optional normals), `nodes[]` (`id`, `kind`, optional `position`, `rotation_y`, `dimensions`, optional `relation`), `groups[]` (`id`, `generator`, `kind`, `count`, `region`, optional `dimensions`), `clearances[]` (keep-out boxes).

Relations v1:

- `flush`, `adjacent`, `tucked`, `clear_of`: need `target` plus `side` (`front`, `back`, `left`, `right`).
- `supported_by`: seats a child on the target's top surface with optional `[x, z]` offset.
- `facing`: rotates toward a target, keeping explicit position.
- `centered_between`: midpoint of exactly two targets.

Generated group instances are legal relation targets as `<group_id>_<index>` (for example `left_table_mid_00`).

Author in two passes: relations first with registry-default dimensions (a semantics-only blueprint validates and compiles), then add dimension overrides only where needed. Overrides must stay uniformly scalable against the registry aspect; aspect-changing overrides are a validation error because records carry one uniform scale.

## Kind Registry

`modules/_shared/sdf/sdf_kinds.yaml` describes each SDF object kind: numeric `id` (the record `kind_id`), real dimensions, footprint radius, and named anchors. The registry is the compiler's ground truth for relation arithmetic, validation, relaxation, and the overlap checker.

## Compiler Actions (sentinel_blueprint)

- `validate`: parse plus rule checks (unknown kinds/references, cycles, over budget versus the renderer's 96-instance limit, bad clearances, support overhang, pairwise clearance, aspect drift). Structured errors name the offending node and rule.
- `solve_report`: resolves records and reports hashes, topology, relaxation stats, and warm-start displacement histograms.
- `compile`: solves and emits the generated Module project; with `create: true` it also creates the pipeline in the running app (the producer publishes `PNodes`).
- `audit`: captures a module's `Audit Results` data port and evaluates an audit sidecar against measured values.

Under-constrained placements (scatter groups, spacing) go through a force-directed relaxation pass with deterministic seeding. A `<blueprint-stem>.solved.json` sidecar warm-starts recompiles: surviving instances keep their positions under small edits (add three tables and the room stays put); new instances seed into the largest free region.

## PNode Output

The generated producer publishes one `PNodes` structured output, element size 48 bytes: `position[3]`, `scale`, `kind_id`, `seed`, `yaw`, `height`, `width`, `depth`, `dir[2]`. During visible authoring, place/focus/open and prove the producer before creating the renderer. Then create the renderer beside it, wire the data link, focus/open the renderer, and inspect the result.

## Audits (Measured Geometry Assertions)

A `<blueprint-stem>.audit.yaml` sidecar makes `compile` emit an `Audit Results` data output. Assertions carry `id`, `type`, `expected` or `min_separation`, `tolerance`, optional `pair`; generated measures include `record_field`, `count_kind`, `flush_gap`, and `pair_separation`. Hand-authored hero modules can add their own audit pass with `modules/_shared/sdf/sdf_audit.hlsli` (bisection dimension measurement, bounds clearance, overlap sampling) and the same result-record shape.

Run with explicit `max_elements` (data-port capture defaults to 20 elements and truncates silently):

```json
{"action":"audit","pipeline_id":"Blueprint_Living_Room","audit_path":"path/to/blueprint.audit.yaml","port_name":"Audit Results","max_elements":8}
```

An audit measures the live distance field, so a wrong offset fails mechanically even when the render looks plausible.

## Proof Workflow

1. `sentinel_blueprint validate` until clean (the cafe example returns `ok: true` with node/instance counts versus budget).
2. `compile` with `create: true`; place/focus/open and prove the producer before creating `sdf_scene_render`. Create and place the renderer next, wire `PNodes`, then focus/open and prove it. Use local layout during visible authoring.
3. Capture and evaluate with `sentinel_vision action=eval` (or one-call `action=eval_pipeline`), using the blueprint's counts and relations as the checklist. If the key is missing, follow the setup flow in `knowledge/vision-eval.md`.
4. `audit` for measured dimensions and forbidden overlaps.

Reference blueprints ship under `examples/blueprints/` (`cafe.yaml`, `cafe_grid.yaml`, `city_block.yaml`, `industrial_pipe_canyon.yaml`) with audit and solved sidecars.
