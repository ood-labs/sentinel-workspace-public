# Live verification of Scene Switcher, cameras, and presets — 2026-07-12

## Progress saved

- Completed the hands-on verification pass over the remaining phase 81-88 agent surfaces, building each feature live over MCP and correcting the docs with what actually happened.
- Scene Switcher: built a two-look show from scratch (pattern look and module look, each ended in a `groupoutput`, wrapped in annotations, converted with `convert_to_scene_group`), set the mux `source_mode` enum to `1`, and cut between looks with pixel-distinct captures. Documented the exact MCP sequence, the enum values (0 Wired, 1 Groups), the title-to-slug rule for `select/<slug>` triggers, and `selected_group` holding the group entity id.
- Cameras: created a `camera` rig, bound a camera-feature module through `camera_ref`, and drove the view over plain state writes (38.5% pixel change). Proved lock semantics with a controlled diff: a local fov write on the bound module changed 0.0% of pixels while the rig write changed the render. Bound the module to a `camswitch` and cut between two posed cameras (61.9% pixel change on `selected_camera`).
- Presets: exercised `sentinel_preset` end to end. `save` requires an explicit `params` and/or `groups` selection (no default), identity derives from the module project (`module:click_ripples`), `recall` restores exact values and reports `applied[]`/`skipped[]`, and loose recall onto an incompatible node fails loudly. Call shapes documented in `FEATURE-MAP.md`.
- Compound exposure (Phase 85): compounds live in StateTree as flattened components; `expose_scene_group_parameter` takes a COMPONENT name (the base name errors) and auto-promotes the whole compound, returning all group paths. Group-to-target sync verified with a live write. Documented in the manuals.
- `terminal_read` verified (grid lines, cursor, child status, sequence counter).

## Still in progress

- The sentinel repo seed edits remain uncommitted there; commit before the next installer build.

This is a documentation verification checkpoint, not a phase or subphase completion.
