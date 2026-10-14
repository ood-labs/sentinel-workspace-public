# Blueprint template: a living room

A complete precise-construction chain to copy into a project and run: two blueprints and their kind registry, plus
the renderer, materials and lighting Modules they feed. It is the reference for `knowledge/precise-construction.md`
and the `procedural-geometry-authoring` skill: validate and compile real blueprints, then see them rendered.

| Path | What it is |
|---|---|
| `blueprints/living_room_sdf_kinds.yaml` | The kind registry: each SDF object kind's id, real dimensions, footprint and anchors |
| `blueprints/living_room_architecture.yaml` | The room's shell: walls, floor, ceiling and its lights, a window, a doorway, a rug and two framed pictures (13 instances) |
| `blueprints/living_room_furnishings.yaml` | The furniture at real dimensions from the registry: a sofa, armchairs, coffee table and ottoman, side tables, a media wall, a bookshelf, lamps, plants, cushions and decor, with an entry path the validator keeps clear (23 instances) |
| `blueprints/*.solved.json` | Solved sidecars, so a recompile warm-starts and surviving instances keep their places |
| `modules/LR_SDF_Renderer` | The renderer: draws every kind from `PNodes` records with the internal camera |
| `modules/LR_Materials` | Procedural material records for the renderer |
| `modules/LR_Lighting` | A lighting desk (daylight, practical lamps, ambient, shadows) that reads both PNodes buffers for context |
| `modules/_shared` | The Interaction Lab UI files and IBM Plex type atlas the lighting desk draws with (OFL notice beside it) |

## Run it

1. Copy this folder into a project, for example `projects/my_room/`.
2. Validate both blueprints against the registry (`sentinel_blueprint action=validate`, with `registry_path` set to
   `blueprints/living_room_sdf_kinds.yaml`).
3. Compile each one into a generated producer Module, creating its node: `action=compile`, `create=true`,
   `output_dir` `modules/BP_Architecture` (and `modules/BP_Furnishings`), `pipeline_name` the same. Each publishes one
   `PNodes` output of 48-byte records.
4. Create `LR_Materials`, `LR_Lighting` and `LR_SDF_Renderer` from `modules/`, one at a time.
5. Wire the data ports:

   | From | To |
   |---|---|
   | `BP_Architecture` `PNodes` | `LR_SDF_Renderer` `Architecture PNodes`, `LR_Lighting` `Architecture PNodes` |
   | `BP_Furnishings` `PNodes` | `LR_SDF_Renderer` `Furnishings PNodes`, `LR_Lighting` `Furnishings PNodes` |
   | `LR_Materials` `Material Records` | `LR_SDF_Renderer` `Material Records` |
   | `LR_Lighting` `Light Records` | `LR_SDF_Renderer` `Light Records` |

6. Frame the room. The renderer flies Sentinel's internal camera; the composed corner view is position
   (-2.72, 1.30, -1.12), yaw 0.813, pitch -0.075, field of view 89.8. Save it as a camera-only node preset.

Then change the room: edit a blueprint and recompile, and the producer republishes while the renderer stays as it is.
These two place every object at an explicit position; relations (`flush`, `tucked`, `supported_by`, `facing` and the
rest in `knowledge/precise-construction.md`) solve placements for you, so try replacing a position with one. Add a
`<blueprint>.audit.yaml` sidecar to measure the result (`knowledge/precise-construction.md`, Audits).

Proven on Sentinel 0.6.8: both blueprints validate (13 and 23 instances, budget 96), compile with no overlaps or
clearance violations, and render through these three Modules with every node healthy.
