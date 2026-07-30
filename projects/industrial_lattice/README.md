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

## Controls

The approved project keeps control on the two nodes themselves:

- use `lattice` for grid spacing, floor height, column thickness, junction detail,
  grime, light, fog, distortion, and the native camera;
- use `Post` for exposure, contrast, monochrome treatment, bloom, vignette, and
  grain.

Panels carve real recessed bands into the field, junctions add collars and bolts,
and the Surface section layers grime, streaks, cracks, spalling, and edge wear.

The **Distortion** section ports the Living Room renderer's world-space deformation language into the infinite lattice: two independently oriented warp layers offer Flow, Ripple, Turbulent, Fractal, Steps, Boxes, and Shatter fields, followed by melt, twist, bend, swirl, and wave deformation. **Distortion Master** defaults to zero, so the authored structural look is unchanged until the effect is enabled.

## Presets

Two project-scoped node presets provide focused recall surfaces:
`Industrial Fidelity Core` on `lattice` and `Industrial Monochrome Finish` on
`Post`. The saved project itself is the approved complete look.

## Why there is no object picking

The lattice is an infinite domain-repetition field. Its visible members do not have stable unique instance identities, so selection gizmos would imply an object model that does not exist. Navigation and authored parameters are the honest interaction model for this example.

## Performance

The approved state is 1280x720 with 4x4 AA. On a slower GPU, lower AA first,
then reduce march steps or march distance and disable shadows, bolts, or surface
detail. AA is an `N x N` control, so its cost grows quadratically.

No engine packs are required.

## Component map

| Component | Type | Receives | Publishes or contributes |
| --- | --- | --- | --- |
| `lattice` | Module | native viewport camera input | repeated structural SDF scene |
| `Post` | Module | `lattice` texture | final monochrome grade |

`Post` is the reviewed output. Study the clarity of a compact generator/post
route and the honest choice not to add object picking to infinite repetition.
