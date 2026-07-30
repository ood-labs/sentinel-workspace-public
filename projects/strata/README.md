# Strata

Strata is a modular portrait composition built from independent background, marble, sculptural blob, wire, marks, live feature-thread, plate-composite, and post passes. The modernization keeps that premultiplied architecture intact and adds a movable marble focal, shared palette modes, curated presets, and an efficient in-node analysis path.

## What to open

Open `strata.sentinel`. All ten active nodes live in one flat `STRATA` Scene Group with no child groups. `post_1` is the final image node, and every pipeline node preview is visible by default.

No engine pack is required. The project uses authored Modules plus the model-free `Features` pipeline.

## Feature analysis branch

`plate_comp` keeps its full 720 x 1080 output for the composition and thread.
`Features #0` receives that texture directly and uses its built-in
`analysis_downsample` control at 4x, reducing feature analysis to 180 x 270
without adding a proxy node or lowering the full-resolution video output.
Detected corner coordinates remain normalized against the analysis extent
before `corner_thread` renders them back into Program space.

## Direct marble placement

Open `marble_panel` and left-drag the marble focal in its viewport. The `marble_focal` parameter gesture updates the compound `panel_center` control while preserving the panel aspect ratio and the existing premultiplied plate contract. Reset the compound control from Properties to return to the authored center.

This project deliberately does not add generic object selection or transform gizmos. The only direct manipulation is the composition-specific focal that maps cleanly to a real parameter.

## Scene Group presets

- **Clean Studio** — balanced Atelier palette and the recommended hero state.
- **Melted Chrome** — warm reflective material with stronger melt and warp.
- **Graphic Poster** — saturated high-contrast color blocks and reduced wire.
- **Wire Cage** — dark restrained sculpture with dominant feature and cage lines.
- **Performance** — monochrome lower-cost mode; disables Features and uses one render sample.

The group exposes five stable remix controls for sculpture gloss/reflection,
marble panel size, and thread width.

## Remix

Start with **Clean Studio** for material and focal placement, use **Graphic
Poster** or **Wire Cage** when changing plate balance, and return to
**Performance** for the documented lower-cost live state. Shape exact plate
weights and deformation on the nodes that own them. The only
direct-manipulation surface is the useful one: `marble_panel`, where the marble
focal is spatially dragged.

## Node presets

- `blob_render` / **Hero Sculpture** captures the renderer's material, deformation, light, quality, and camera essentials.

It is project-scoped, so it travels inside the project rather than relying on a machine-local preset library.

## Graph lanes

```text
blob_layout -- BlobInstances --> blob_render ----+
strata_bg ---------------------------------------+
marble_panel ------------------------------------+--> plate_comp --> corner_thread --> post_1
wire_render -------------------------------------+
marks -------------------------------------------+
plate_comp --> Features -- Corners ---------------------+
```

Textures carry plates, while structured buffers carry blob instances and detected corners.

## Runtime checks

All nodes should be healthy in the five intended presets. `Features #0` should
report `analysis_downsample = 4x`, fifteen live corners, and a full-resolution
720 x 1080 video output; the resulting thread should span the portrait. In
**Performance**, `Features #0` is intentionally bypassed while the rest of the
graph remains healthy. The project should contain exactly one flat Scene
Group, zero child groups, no Group Output, no expression drivers, and
visible-by-default previews for every pipeline node.
