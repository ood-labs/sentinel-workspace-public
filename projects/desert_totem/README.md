# Desert Totem Sculpture Workstation

Desert Totem is a procedural Dada assemblage built from typed `DadaPart` records and rendered as one coherent distance field. The modernization preserves the modular layout, accent-field, renderer, signal, and post lanes while adding a semantic assembly editor, a focused ochre/black Warp Deck, and safe scene presets.

## What to open

Open `desert_totem.sentinel`. Its six authored Modules form one compact render graph.

No engine pack is required. Every dependency is bundled under `modules/`.

## Assembly Editor

Open `dada_layout` to edit four stable logical assemblies: Crown, Upper, Mid Shelf, and Base. Pick an assembly, choose Move, Rotate, or Scale, and left-drag. Each edit transforms every child record around the assembly pivot, so compound forms remain intact instead of tearing into primitive pieces. Escape cancels the active transaction.

The transform overrides live in a durable structured buffer. Project-scoped node presets demonstrate the state round trip:

- **Monument Baseline** restores zero offsets, zero rotations, and unit scale.
- **Asymmetric Study** restores a moved Base, rotated Crown, and scaled Mid Shelf.

## Warp Deck

Open `dada_control` for the full-bleed **Desert Warp Deck**. It owns the existing safe macro layer rather than duplicating renderer math:

- melt, sag, spread, explode, primary, secondary, and twist controls;
- painterly, facet, hue, heat-haze, and accent-field controls.

The Canvas uses an ochre/black scientific-instrument treatment. Its aspect ratio is preserved, and `follow_panel` rendering scales to the real dock size. Direct equality controls use bidirectional binds into layout, scatter, and render parameters; derived modulation remains expression-driven.

Warp 1 and Warp 2 mode selection intentionally lives on `dada_render` as named button grids: Flow, Ripple, Turbulent, Fractal, Steps, Boxes, and Shatter. Those enum modes are not duplicated or bound through the Warp Deck, so the renderer buttons remain directly editable.

## Camera

`dada_render` uses its built-in camera directly. Keep **Camera Ref** empty and use the renderer's internal position, target, orbit, and viewport navigation controls for framing.

## Scene Group presets

- **Monument** - balanced frontal sculpture and recommended starting state.
- **Dali Melt** - close, soft, strongly sagged organic deformation.
- **Cubist Glitch** - faceted block distortion from an oblique camera.
- **Painterly** - broad surface treatment with a silhouette framing.
- **Fidelity** - full-resolution, shadowed, populated hero render.
- **Performance** - reduced render resolution, shorter march, no shadows, and a capped accent field.

The Scene Group exposes only eight non-conflicting remix controls: layout and scatter seeds, layout jitter, fog, sun azimuth/elevation, bloom, and grain. Warp Deck controls are deliberately not duplicated at the group level.

## Node presets

- `dada_layout`: **Monument Baseline** and **Asymmetric Study** include durable assembly state.
- `dada_control`: **Monument Warp Desk** captures the complete macro stack.
- `dada_render`: **Safe Sculptural Render** captures bounded quality, sky, and material-scale essentials.
- `post`: **Desert Film Finish** captures the non-group-owned film treatment.

All presets are project-scoped and portable.

## Safety

The complete warp system can become expensive when many high-amplitude distortions are combined. The shipped ranges and presets remain bounded. Use **Performance** first when adapting the scene to a slower GPU; use **Fidelity** for the approved full-quality state. The renderer's **Quality** section exposes rays per axis, march steps, surface epsilon, step scale, normal epsilon, shadow steps, and AO steps. Avoid raising every warp amount and raymarch quality control to its maximum simultaneously.

## Graph lanes

```text
dada_control -- control outputs / expressions --> layout, scatter, renderer
signal ------- slow modulation expression ------> renderer warp speed
dada_layout  -- Parts ---------------------------> dada_render
dada_scatter -- Parts ---------------------------> dada_render
dada_render --> post
```

Textures carry the rendered image; structured buffers carry semantic sculpture records and durable overrides; expressions carry the shared scalar macro state.
