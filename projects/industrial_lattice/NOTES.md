# Industrial Lattice

Fresh restart of the industrial steel-structure scene (the earlier `industrial_steel_greebled`
build got too complex — bay generators, greeble packs, struct merge, surface samplers — and the
camera repair stalled). This time: build up slowly from a clean grid.

The visual reference was a view looking up into a dense concrete-and-steel structural cage:
square box-section columns at grid points, with horizontal beams in X and Z at every floor.

## Step 1 — infinite grid structure (DONE)

Module `modules/steel_lattice/` — one raymarched SDF, no mesh / no placement buffer / no bounds.
**Infinite in all directions via pure domain repetition** (`round()` fold per axis):

- columns: square box-section, infinite along Y, on the XZ grid (`cell`)
- beams-X: bars along X, at every floor height (`floor_h`) and Z grid line
- beams-Z: bars along Z, at every floor height and X grid line

Union of the three = the space frame. Cheap (~59 fps, 720p). Orbit + fly cam, sun shadows, AO,
fog-to-dark depth recession, optional desaturate for the B&W reference look.

Known minor artifacts: faint wavy shading on column faces + specks on distant thin members at
glancing angles — the usual domain-repetition distance-underestimate. Mitigated with a 0.82 march
relax factor; acceptable for the structure pass.

## Next (not started)

Add detail on top of the grid: member cross-section profile (I-beam / channel flanges vs plain
box), rivets/bolt plates at junctions, surface grunge, structural variation so it doesn't read as
a perfect crystal. Decide per-detail whether it lives in the same SDF or a separate pass.
