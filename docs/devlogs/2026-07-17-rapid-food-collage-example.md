# Rapid food collage example checkpoint — 2026-07-17

## Progress saved

- Rebuilt `fruit_atlas_scatter` as a persistent rapid food-collage poster driven by StreamDiff plus matting, replacing the old Atlas/LFO/3D scene path.
- Added the project-local `Food_Collage` module with atomic per-hit latching, accumulated cutouts, generated food/pattern prompts, print finishing, rare halftone/rip/displacement events, registration echoes, graphic frames, and negative-space overlay blocks.
- Replaced the unstable sine probability picker with a deterministic integer hash and separated rare texture-event rates from more-visible structural frame/block rates.
- Rebuilt and recall-tested Scene Group presets: `Default`, `Machine Gun`, `Giant Cuts`, `Night Press`, `Freeze Frame`, and `Performance`. `Default` is the user-approved current setup.
- Added a healthy `groupoutput`, exposed eight Scene Group controls, and added project-scoped node presets `Editorial Default` and `Graphic Structure`.
- Removed retired public `Fruit_LFO` and `Fruit_Scene` module copies as validator-detected orphans; the private workspace copies remain available for a future standalone LFO/UI example.
- Proved a clean public cold-load with no unresolved module paths, both live modules compiling `ok`, and the Group Output healthy at 1080×1350.
- Ran `tools/validate-official-examples.ps1` for `fruit_atlas_scatter`; result: portable, one project passed, zero failures, zero warnings.

## Still in progress

- The wider Phase 1 official-examples modernization approval remains pending independently of this example checkpoint.

This is a save point, not a phase or subphase completion.
