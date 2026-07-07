# C1 - tg6SMjlAs3yrFGLN - Pulsating Metallic Polyhedron

## Reference Read
- 1080x1350, 12 s, 30 fps, seamless.
- Four 3 s cycles: compact faceted icosahedron at 0/3/6/9 s, stellated flower/star at 1.5/4.5/7.5/10.5 s.
- Static mauve-gray radial/vertical studio gradient. No floor, no text, no particles.
- Hero material is glossy metallic: deep black-violet shadows, white specular panels, pink center reflections, pale green rim reflections.

## Architecture Axes
- 3D world-space hero over 2D screen-space backdrop.
- Composite-of-layers: background plate + premultiplied hero plate + final comp.
- Self-animating, deterministic 12 s loop; exposed phase override for sweep proof.
- Raster/Spout target, not laser/vector.

## Element -> Technique -> Transport
| Element | Technique | Transport | Reuse |
| --- | --- | --- | --- |
| Mauve studio backdrop | radial/vertical gradient with grain | texture lane | invent as scene-specific `c1_bg` |
| Icosahedron/stellation hero | procedural triangle ray tracer over hardcoded icosahedron faces; face-center apex extrusion | premultiplied texture lane | adapt SDF/plate material patterns |
| Final look | premultiplied over + vignette/exposure/gamma | texture lane | adapt plate compositor |

## Module Graph
`c1_bg -> c1_comp[BG]`
`c1_polyhedron -> c1_comp[Hero]`

## Lane Contracts
- Resolution: 864x1080 (4:5, reference aspect, fast enough for iteration).
- `c1_bg`: opaque RGBA8 color.
- `c1_polyhedron`: premultiplied RGBA; alpha is object coverage.
- `c1_comp`: samples both inputs, over-composites hero, applies exposure, vignette, and gamma.

## Build Sequence
1. Author all three modules and compile-check.
2. Create fresh Sentinel graph with `c1_bg`, `c1_polyhedron`, and `c1_comp`.
3. Wire BG and Hero into comp, auto-layout, capture rough whole scene.
4. Compare compact and stellated key frames against reference; refine silhouette/material/motion as whole-scene passes.
5. Save bundled project and capture proof.
