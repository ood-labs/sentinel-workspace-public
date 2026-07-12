# Workspace feature refresh for phases 81-86 — 2026-07-11

## Progress saved

- Audited the agent manuals, knowledge docs, and skills against the features shipped through Sentinel 0.5.28 plus the just-approved unified preset system, then refreshed every stale surface.
- Agent manuals (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md`): pipeline table gained `groupoutput`, `camera`, and `camswitch` and the Groups-mode Mux description; new Scene Switcher and camera guidance in the choreography section; Scene Group exposed-parameter parity (authored defaults, enums, sections, compound color/XY units); a Node Presets section covering `sentinel_preset` with a live-discovery caveat for builds at or below 0.5.28.
- `knowledge/scene-system.md`: full Scene Switcher section (Group Output authoring contract, freeze semantics, `selected_group` / `fade_time` / `allowed_groups` / `select/<slug>` controls) and a cameras section (shared fly/orbit rig, `camera_ref` binding order, `camswitch` blending).
- `knowledge/FEATURE-MAP.md`: entries for `groupoutput`, `camera`, and `camswitch` plus the Groups-mode Mux role.
- `knowledge/module-pipeline.md`: the Phase 84 `viewport:` manifest block (`hint`, `interactions: mouse | pan_zoom | camera`) and camera binding pointer.
- `knowledge/expressions-and-drivers.md`: bool expression targets and string `ref()` filters such as `allowed_groups`.
- `mcp-automation` skill (both skill trees): 13 tools including `sentinel_preset` (all eight actions incl. `bundle` / `copy_to_library`), `terminal_read`, and the new node types.
- `module-authoring` skill (both skill trees): fly/orbit camera modes, `camera_ref` binding, `camswitch`, and the `viewport:` block with a YAML example.

All content matches the sentinel repo `tools/dist` seeds, so the next provisioning pass will not regress these files.

## Still in progress

- Add `sentinel_preset` to `FEATURE-MAP.md` without the version caveat once an installer newer than 0.5.28 ships it.

This is a documentation refresh checkpoint, not a phase or subphase completion.
