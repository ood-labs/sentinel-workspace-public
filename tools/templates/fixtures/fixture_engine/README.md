# Fixture engine template

The workspace fixture engine's four Modules, ready to copy into any project that has a Fixture Rig node
(`fixturerig`). They draw every fixture of the rig from its GDTF, read through the node's `FixtureRender` port: drop a
library type onto the node's plan and it renders within a second, with no per-type code and no recompile.

| Module | Does |
|---|---|
| `FE_Rig` | one record per Fixtures record: rig type, engine mode, mount pose, DMX breaks; a type the engine cannot draw becomes a placeholder |
| `FE_Console` | a programmer: looks, chases and positions, encoded to DMX for every universe of the patch |
| `FE_Decode` | DMX back to per-fixture state, as a console's DMX would be decoded |
| `FE_Renderer` | bodies, beams, cells, haze and the deck, with a fly camera |

`modules/_shared/` holds the includes all four read; keep it beside them, since the Modules include `../_shared/`.

## Add it to a project

1. Copy `modules/` into the project folder (the four Modules and `_shared` side by side).
2. Create the Modules, each from its folder:

   ```text
   sentinel_pipeline action="create" type="module" name="FE_Rig" project_dir="<project>/modules/FE_Rig"
   sentinel_pipeline action="create" type="module" name="FE_Console" project_dir="<project>/modules/FE_Console"
   sentinel_pipeline action="create" type="module" name="FE_Decode" project_dir="<project>/modules/FE_Decode"
   sentinel_pipeline action="create" type="module" name="FE_Renderer" project_dir="<project>/modules/FE_Renderer"
   ```

3. Link them (`sentinel_graph action="add_link"` by pin name), then `sentinel_graph action="auto_layout"`:

   | From | To |
   |---|---|
   | Fixture Rig `Fixtures` | FE_Rig `Fixtures` |
   | Fixture Rig `FixtureRender` | FE_Rig, FE_Console, FE_Decode and FE_Renderer `FixtureRender` |
   | FE_Rig `Rig` | FE_Console, FE_Decode and FE_Renderer `Rig` |
   | FE_Console `DMX` | FE_Decode `DMX` (and a DMX Out node's `DMX` to send it) |
   | FE_Decode `State` | FE_Renderer `State` |

4. Add fixtures: drag a tile from the node's Library browser onto its plan, or
   `sentinel_fixture action="add_fixtures" pipeline=<rig> type=<library file>`. FE_Rig's `rig_state` reads 0 once the
   rig has records, and `fixtures` counts them.
5. Frame them in FE_Renderer: its viewport camera (`camera_pos_x`, `camera_pos_y`, `camera_pos_z`, `camera_yaw`,
   `camera_pitch`, `camera_fov`) flies with the mouse in its window, or set the values through `sentinel_state`. Its
   frame is the stage's with z reversed (upstage is +z): by default it stands 5 m out in the audience at 1 m height
   (`camera_pos_z` -5) and looks upstage. A tile dropped on an empty rig's plan lands on a default 16 m by 10 m stage
   about the origin, in front of that camera.

A type graded Generic renders on the generic rules; the `fixture-refinement` skill refines what its readiness report
flags. A Blocked type draws as a red placeholder box. See `knowledge/fixture-import.md`.
