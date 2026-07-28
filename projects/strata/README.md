# Strata Composition Desk

Strata is a modular portrait composition built from independent background, marble, sculptural blob, wire, marks, live feature-thread, plate-composite, and post passes. The modernization keeps that premultiplied architecture intact and adds a focused gray-and-red composition desk, a movable marble focal, shared palette modes, curated presets, and one Group Output.

## What to open

Open `strata.sentinel`. All twelve active nodes live in one flat `STRATA COMPOSITION DESK` Scene Group with no child groups. `Strata_Group_Output` is the sole final endpoint.

No engine pack is required. The project uses authored Modules plus the model-free `Features` pipeline.

## Composition Desk

Open `strata_control` for the full-bleed **Strata Composition Desk**. Its four
Canvas rails balance the sculpture, marble, wire, and graphic-mark plates while
the coupled composition plot shows their resolved weight.

Exact setup belongs in the node's Properties: shared seed and palette; melt,
twist, marble warp, spread, and wire scale; and the Feature Thread enable and
gain. The Canvas reads those values and the real corner count as telemetry
without duplicating their ordinary scalar/toggle controls.

The desk reads the real `Feature Corners` buffer and shows its live count. It publishes the scalar controls used by visible expressions throughout the graph, so the authority remains inspectable instead of being hidden in a monolithic renderer.

## Direct marble placement

Open `marble_panel` and left-drag the marble focal in its viewport. The `marble_focal` parameter gesture updates the compound `panel_center` control while preserving the panel aspect ratio and the existing premultiplied plate contract. Reset the compound control from Properties to return to the authored center.

This project deliberately does not add generic object selection or transform gizmos. The only direct manipulation is the composition-specific focal that maps cleanly to a real parameter.

## Scene Group presets

- **Clean Studio** — balanced Atelier palette and the recommended hero state.
- **Melted Chrome** — warm reflective material with stronger melt and warp.
- **Graphic Poster** — saturated high-contrast color blocks and reduced wire.
- **Wire Cage** — dark restrained sculpture with dominant feature and cage lines.
- **Performance** — monochrome lower-cost mode; disables Features and uses one render sample.

The group exposes seven stable remix controls for sculpture gloss/reflection, marble panel size, thread width, bloom, and grain. Composition Desk controls are not duplicated there.

## Remix

Start with **Clean Studio** for material and focal placement, use **Graphic
Poster** or **Wire Cage** when changing plate balance, and return to
**Performance** for the documented lower-cost live state. Shape exact
deformation and Feature Thread behavior in `strata_control` Properties, then
perform the four plate weights from the Canvas. Drag the marble itself only in
`marble_panel`; the two direct-manipulation surfaces have distinct jobs.

## Node presets

- `strata_control` / **Atelier Plate Balance** captures the complete
  thirteen-parameter desk state, including the four Canvas rails and nine
  Properties-only setup values.
- `blob_render` / **Hero Sculpture** captures the renderer's material, deformation, light, quality, and camera essentials.

Both are project-scoped, so they travel inside the project rather than relying on a machine-local preset library.

## Graph lanes

```text
blob_layout -- BlobInstances --> blob_render ----+
strata_bg ---------------------------------------+
marble_panel ------------------------------------+--> plate_comp --> post --> Strata_Group_Output
wire_render -------------------------------------+
marks -------------------------------------------+
plate_comp --> Features -- Corners --> corner_thread --+
                                  +--> strata_control
strata_control -- control outputs / expressions -------> authored parameters
```

Textures carry plates, structured buffers carry blob instances and detected corners, and expressions carry the shared scalar composition state.

## Runtime checks

All nodes should be healthy in the four hero presets. `Features #0` should report fifteen live corners and the thread should visibly disappear when its Composition Desk toggle is off. In **Performance**, `Features #0` is intentionally bypassed while the rest of the graph remains healthy. The project should contain exactly one flat Scene Group, zero child groups, and one Group Output.
