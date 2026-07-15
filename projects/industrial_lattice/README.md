# Industrial Lattice

Industrial Lattice is a deliberately compact official example: one procedural structure Module, one monochrome post Module, four wireless cameras, one Camera Switcher, and one Group Output. The scene raymarches an infinite repeated steel-and-concrete frame with panel grooves, junction collars, bolts, weathering, local light, shadows, and depth fog.

## Open the project

Open `industrial_lattice.sentinel`. Every required dependency is bundled under `modules/`; no engine pack or manual wiring is required.

All eight nodes sit in one flat low-alpha purple `INDUSTRIAL LATTICE` Scene Group. `Industrial_Group_Output` is the sole final endpoint. The graph stays intentionally small so a new user can understand the complete render path immediately:

```text
lattice -> post -> Industrial_Group_Output
camera nodes -> Industrial_Camera_Switcher -- camera_ref --> lattice
```

## Cameras

`Industrial_Camera_Switcher` owns four wireless framings:

- **Hero** frames the full structural cage from an oblique interior vantage.
- **Lookup** aims upward through repeating floors and is the default Fidelity view.
- **Deep Grid** emphasizes lateral depth and the endless bay rhythm.
- **Fly** is a navigable starting camera for WASD/right-drag exploration.

The renderer references the switcher through `camera_ref`; the Camera nodes do not need fake video links.

## Scene controls

The Scene Group exposes only eight useful controls:

- grid spacing, floor height, and column thickness for the structural profile;
- junctions for connection detail;
- grime for surface character;
- spot intensity and fog density for depth and lighting;
- bloom intensity for the final monochrome finish.

The complete node Properties remain available when deeper editing is useful. Panels carve real recessed bands into the field, junctions add collars and bolts, and the Surface section layers grime, streaks, cracks, spalling, and edge wear.

## Presets

- **Box Frame** strips the panel treatment back to a clean, thin structural skeleton.
- **Heavy Steel** tightens the grid and uses substantially heavier columns and beams.
- **Concrete Haze** emphasizes weathering, soft light, bloom, and deep atmospheric recession.
- **Fidelity** is the approved 1280x720 default with 4x4 AA, shadows, panels, junctions, and bolts.
- **Performance** runs at 960x540 with 1x1 AA, a shorter march distance, no shadows, no bolts, and reduced surface detail.

Every preset captures the complete eight-node group state, including the selected camera and all bypass flags.

Two project-scoped node presets provide smaller recall surfaces: `Industrial Fidelity Core` on `lattice` and `Industrial Monochrome Finish` on `post`.

## Why there is no object picking

The lattice is an infinite domain-repetition field. Its visible members do not have stable unique instance identities, so selection gizmos would imply an object model that does not exist. Navigation and authored parameters are the honest interaction model for this example.

## Performance

Start with **Performance** on a slower GPU, then switch to **Fidelity** for the approved full-quality output. AA is an `N x N` control, so its cost grows quadratically; avoid raising it to the maximum while also increasing march distance and every surface feature.

No engine packs are required.
