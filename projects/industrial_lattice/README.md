# Industrial Lattice

Industrial Lattice is a deliberately compact official example: one procedural structure Module and one monochrome post Module. The scene raymarches an infinite repeated steel-and-concrete frame with panel grooves, junction collars, bolts, weathering, local light, shadows, and depth fog.

## Open the project

Open `industrial_lattice.sentinel`. Every required dependency is bundled under `modules/`; no engine pack or manual wiring is required.

The graph stays intentionally small so a new user can understand the complete render path immediately:

```text
lattice -> post
```

## Camera

`lattice` uses its built-in camera directly. Keep **Camera Ref** empty, then use WASD and right-drag in the viewport or switch the renderer's Camera Mode to Orbit for deterministic framing.

## Scene controls

The Scene Group exposes only eight useful controls:

- grid spacing, floor height, and column thickness for the structural profile;
- junctions for connection detail;
- grime for surface character;
- spot intensity and fog density for depth and lighting;
- bloom intensity for the final monochrome finish.

The complete node Properties remain available when deeper editing is useful. Panels carve real recessed bands into the field, junctions add collars and bolts, and the Surface section layers grime, streaks, cracks, spalling, and edge wear.

The **Distortion** section ports the Living Room renderer's world-space deformation language into the infinite lattice: two independently oriented warp layers offer Flow, Ripple, Turbulent, Fractal, Steps, Boxes, and Shatter fields, followed by melt, twist, bend, swirl, and wave deformation. **Distortion Master** defaults to zero, so the authored structural look is unchanged until the effect is enabled.

## Presets

- **Box Frame** strips the panel treatment back to a clean, thin structural skeleton.
- **Heavy Steel** tightens the grid and uses substantially heavier columns and beams.
- **Concrete Haze** emphasizes weathering, soft light, bloom, and deep atmospheric recession.
- **Fidelity** is the approved 1280x720 default with 4x4 AA, shadows, panels, junctions, and bolts.
- **Performance** runs at 960x540 with 1x1 AA, a shorter march distance, no shadows, no bolts, and reduced surface detail.

Every preset captures the complete render state, including the lattice's internal camera and all bypass flags.

Two project-scoped node presets provide smaller recall surfaces: `Industrial Fidelity Core` on `lattice` and `Industrial Monochrome Finish` on `post`.

## Why there is no object picking

The lattice is an infinite domain-repetition field. Its visible members do not have stable unique instance identities, so selection gizmos would imply an object model that does not exist. Navigation and authored parameters are the honest interaction model for this example.

## Performance

Start with **Performance** on a slower GPU, then switch to **Fidelity** for the approved full-quality output. The renderer's **Quality** section exposes rays per axis, march steps, surface epsilon, step scale, and normal epsilon. AA is an `N x N` control, so its cost grows quadratically; avoid raising it to the maximum while also increasing march distance and every surface feature.

No engine packs are required.
