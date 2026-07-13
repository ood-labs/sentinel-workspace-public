# Phase 89 viewport MCP verification and docs — 2026-07-12

## Progress saved

- Verified the entire Phase 89 / 0.5.31 surface hands-on against a freshly built app and MCP server, then documented it operationally.
- `sentinel_viewport` proven action by action on the committed fixtures: `info` reports bindings, controls, selection config, and `edit_transaction_active`; `objects` returned all six descriptors with transforms, bounds, pivots, and flags; `pick` at an object's normalized position returned `hit: true` with the right `object_id` at 1-frame latency; `selection set` took ids with source MCP; `edit` ran a begin/preview/commit move transaction that landed exactly in the module's hidden gesture parameters; `state` reported the durable buffer inventory (200 elements, 3200 bytes, schema signature).
- `knowledge/module-pipeline.md` gained a full Viewport Persistence, Controls, and Selection guide: `param_gestures` (previously documented nowhere; field schema taken from the manifest validator, including the radius (0, 0.5] rule and the drag-interest requirement), authored `controls` with the compile-checked kind-to-parameter-type table (slider float/int, button `type: button`, toggle bool, xypad vec2), `state_buffers` with the serialization contract, the `selection:` block with both providers, and per-action MCP recipes.
- Agent manuals note the 0.5.31 surfaces and the `sentinel_viewport` tool; the `mcp-automation` skill (both trees) documents all 14 tools including the verified `sentinel_viewport` behavior.
- Anchor advanced to sentinel `ebbbbac2` at installed build 0.5.31.

## Still in progress

- The sentinel repo seed edits remain uncommitted there; three provisioning regressions have now been recovered because of it. Commit the seeds before the next installer.

This is a documentation verification checkpoint, not a phase or subphase completion.
