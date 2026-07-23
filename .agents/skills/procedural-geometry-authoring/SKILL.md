---
name: procedural-geometry-authoring
description: Author precise Sentinel procedural geometry from semantic blueprints, including registry-backed SDF instance kinds, relation solving, generated PNode modules, audit sidecars, and live MCP proof.
distribution: true
---

# Procedural Geometry Authoring

Use the precise-construction blueprint path when a scene needs real dimensions, named anchors, clearances, repeatable layout, or audit evidence. Reserve hand-authored shader placement for scenes that cannot be described as objects plus relations.

## Blueprint-first workflow

1. Write a YAML blueprint under `examples/blueprints/` or the current show folder.
2. Use kinds from `modules/_shared/sdf/sdf_kinds.yaml`.
3. Author in two passes: first use registry-default dimensions and relations only, then validate and add dimension overrides only where the scene needs them.
4. Prefer relations over raw coordinates:
   - `supported_by` for objects on surfaces.
   - `tucked`, `flush`, `adjacent`, and `clear_of` for side relationships.
   - `facing` for direction vectors.
   - `centered_between` for midpoint placement.
5. Use groups for repeated records. Generated group ids are `<group_id>_<index>`, such as `left_table_mid_00`, and can be relation targets.
6. Add `clearances[]` for aisles, streets, and keep-out zones.

Validation command:

```json
{"action":"validate","path":"examples/blueprints/living_room_architecture.yaml"}
```

The expected cafe summary is `ok: true`, `node_count: 14`, `group_instance_count: 6`, `resolved_instance_count: 20`, and `instance_budget: 96`.

## Compile and render

Compile with `sentinel_blueprint compile`. With `create: true`, the tool creates a Module producer that publishes `PNodes`.

```json
{"action":"compile","path":"examples/blueprints/living_room_architecture.yaml","create":true,"pipeline_name":"Blueprint_Living_Room"}
```

During visible authoring, place/focus/open and prove the generated producer before creating the renderer. Then create and place the renderer relative to it, wire `PNodes`, focus/open the renderer, and inspect the result. Reserve whole-graph `auto_layout` for explicit batch work.

The PNode schema is fixed at 48 bytes: position, scale, kind id, seed, yaw, height, width, depth, and direction. Keep scene-specific needs in blueprint data or renderer logic.

## Audit

For measured assertions, place `<blueprint-stem>.audit.yaml` beside the blueprint. Supported generated audit measures:

- `record_field`
- `count_kind`
- `flush_gap`
- `pair_separation`

Run `sentinel_blueprint audit` against the generated producer's `Audit Results` port with explicit `max_elements`.

```json
{"action":"audit","pipeline_id":"Blueprint_Living_Room","audit_path":"path/to/blueprint.audit.yaml","port_name":"Audit Results","max_elements":5}
```

## Proof helpers

- `sentinel_blueprint solve_report` independently reports solved records, topology, and solver stability.
- `sentinel_blueprint audit` evaluates an authored audit sidecar against live GPU output.
- Use `sentinel_vision action="eval"` on the renderer capture for visible scene claims. If it reports a missing or rejected key, run `sentinel_vision action="status"` and have the user paste their provider key into the returned workspace `vision.json` `api_key` field, then rerun `status` until `key_present` and `key_ok` are true. Never take keys through chat or tool arguments.

For detailed schema notes, read `knowledge/precise-construction.md`.
