# Marble SDF Scrapbook

This is the retained map for the current sculpture exploration. Failed live branches are removed from the graph; authored files may remain here as recoverable experiments. The live graph currently keeps three comparable renderer roots.

## Active root: glitch sculpture

Live graph:

`Trigger_Sequencer -> SDF_Glitch_Field -> Marble_SDF_Renderer`

Supporting branches:

`Marble_Sculpture_Plan -> Marble_SDF_Renderer`

`Marble_Material_Profile -> Marble_SDF_Renderer`

`Nocturne_Light_Rig -> Marble_SDF_Renderer`

The renderer owns the proper Sentinel camera template and ray-marches the sculpture plus the glitch field in object space. This is the current restored state after removing the industrial-world experiment.

## Active comparison branch: faceted chrome / lit crossbreed

`Marble_Branch_Faceted_Field + Marble_Branch_Faceted_Lights -> Marble_Branch_Faceted`

Shares the sculpture, material, and light buffers with the root, but uses low warp, high quantization, and planar geometry from the faceted field combined with stronger exposure, veins, and surface readability borrowed from the lit branch. This is the planar/architectural alternative with the crossbred material treatment.

Checkpoint: `C:/Users/bot/Sentinel/captures/Marble_Branch_Faceted_1784878212660.png`.

The faceted branch light rig uses a hard key, restrained fill, narrow rims, and low slash intensity to keep its planar silhouette legible. Preview checkpoint: `C:/Users/bot/Sentinel/captures/Marble_Branch_Faceted_Lights_1784878186331.png`.

## Active comparison branch: orbit array machine

`Marble_Branch_Array_Plan + Marble_Branch_Lit_Field + Marble_Branch_Lit_Lights -> Marble_Branch_Lit`

Uses a 48-record orbit-array plan: six rotating slab/cutter pairs, suspended crossbars, nine razor bars, and diagonal cutters around a broken central mass. It combines broader animated glitch slices, sequencer pulse, stronger veins, high exposure, and the dedicated rim/slash rig. This is the structural/spatial/motion alternative.

Checkpoint: `C:/Users/bot/Sentinel/captures/Marble_Branch_Lit_1784878476346.png`.

Plan preview: `C:/Users/bot/Sentinel/captures/Marble_Branch_Array_Plan_1784878396793.png`.

The branch-specific light rig uses a reduced fill, stronger rims, moving slashes, and sequencer-driven pulse. Its structured preview checkpoint is `C:/Users/bot/Sentinel/captures/Marble_Branch_Lit_Lights_1784878066210.png`.

The earlier asymmetric single-plan lit branch was compared and pruned from the live graph after the orbit-array replacement; its capture remains recoverable on disk.

Current batch comparison checkpoint: `C:/Users/bot/Sentinel/captures/Marble_SDF_Renderer_1784877777933.png`.

## Active graphic scene stack

The sculpture now has a separate graphic-world branch instead of only renderer tweaks:

`Marble_SDF_Renderer -> Marble_Layer_Compositor -> {Marble_Contour_Accent, Marble_Grid_Warp}`

`Marble_Frame_HUD_1 -> Marble_Layer_Compositor`

The HUD is a 34-ring instrument aperture with segmented ticks, rotating bands, and orange registration marks. The compositor mixes it with the 3D sculpture at the canonical 1280x720 output. `Marble_Contour_Accent` is a sparse ridge/accent signal with 88 contour bands and index ticks. `Marble_Grid_Warp` is a separate perspective/warp scan branch with 46 grid lines, high perspective, and blue-black technical coloration.

Graphic checkpoints:

- `C:/Users/bot/Sentinel/captures/Marble_Frame_HUD_radical.png`
- `C:/Users/bot/Sentinel/captures/Marble_Layer_Compositor_radical.png`
- `C:/Users/bot/Sentinel/captures/Marble_Contour_Accent_radical.png`
- `C:/Users/bot/Sentinel/captures/Marble_Grid_Warp_radical.png`

The compositor is the readable handoff view. The branches were then crossbred without creating a feedback cycle:

`Marble_SDF_Renderer -> {Marble_Contour_Accent, Marble_Grid_Warp} -> Marble_Layer_Compositor`

The compositor now mixes the sculpture, HUD, warped grid, and accent contour signals as distinct layers. Crossbred checkpoint: `C:/Users/bot/Sentinel/captures/Marble_Layer_Compositor_crossbred.png`.

## Comparison branch: oblique instrument shell

`Marble_SDF_Renderer + Marble_Frame_HUD_Oblique + Marble_Grid_Warp + Marble_Contour_Accent -> Marble_Compositor_Oblique`

This branch deliberately changes the spatial read: 11 wide blue rings, oversized viewport radius, sparse orange index blocks, warmer background tint, and a quieter scan/contour mix. It keeps the same sculpture and analysis layers so the HUD geometry itself can be compared against the dense 34-ring instrument root.

Checkpoint: `C:/Users/bot/Sentinel/captures/Marble_Compositor_Oblique.png`.

## Motion binding

The graphic branches are now driven by the live sequencer rather than static rates. `Trigger_Sequencer/control_outputs/env_1` modulates both HUD rotation pairs, the grid drift, and the dense compositor HUD gain; the oblique compositor has its own HUD-gain response. This preserves the two spatial identities while giving them a shared pulse language.

Motion-bound checkpoint: `C:/Users/bot/Sentinel/captures/Marble_Layer_Compositor_motion_bound.png`.

## Comparison branch: array machine inside oblique instrument

`Marble_Branch_Lit + Marble_Frame_HUD_Oblique + Marble_Grid_Warp + Marble_Contour_Accent -> Marble_Compositor_Array`

This is the strongest structural crossbreed so far: the 48-record orbital-array SDF machine is placed inside the sparse oblique shell, with the grid and contour signals retained as separate technical layers. The array renderer was tuned from 84 to 60 ray steps after a 9 FPS test; the retained result is visually sharper enough for the branch and runs at approximately 48 FPS.

Checkpoint: `C:/Users/bot/Sentinel/captures/Marble_Compositor_Array_tuned.png`.

## Representational branch: wire cage overlay

`Marble_Branch_Lit + Marble_Grid_Warp + Marble_Contour_Accent + Marble_Frame_HUD_Oblique + Marble_Wire_Cage -> Marble_Compositor_Wire`

Added a separate line-art language: seeded ellipse rings, seven loose strands, and an eight-point triangulated cage. The custom compositor keeps the chrome array as the dominant layer and exposes `wire_gain` plus `wire_tint` for the schematic overlay. The custom pass was compile-checked and its compact Sentinel texture-register mapping was corrected after intermediate preview inspection.

Wire branch checkpoints: `C:/Users/bot/Sentinel/captures/Marble_Wire_Cage.png` and `C:/Users/bot/Sentinel/captures/Marble_Compositor_Wire_fixed.png`.

The wire generator was then normalized to 1280x720 and live-verified at ~47 FPS; the corrected 16:9 source and composite checkpoints are `C:/Users/bot/Sentinel/captures/Marble_Wire_Cage_16x9_fixed.png` and `C:/Users/bot/Sentinel/captures/Marble_Compositor_Wire_16x9_fixed.png`.

The wire topology is now sequencer-bound as well: `env_1` modulates `wire_seed` for topology movement and `wire_bright` for pulse response. Motion-bound checkpoint: `C:/Users/bot/Sentinel/captures/Marble_Compositor_Wire_motion_bound.png`.

The proper internal Orbit camera on `Marble_Branch_Lit` is now sequencer-bound too: `camera_yaw`, `camera_pitch`, and `camera_distance` respond to `env_1`, creating a live exterior dolly/orbit read of the array machine. Camera-motion checkpoint: `C:/Users/bot/Sentinel/captures/Marble_Compositor_Wire_camera_motion.png`. The renderer remains on the Sentinel camera template with `camera_ref` empty.

Hierarchy test: pushing `wire_gain` to 3.0 and whitening the cage did not produce a sufficiently legible integrated overlay, so that experiment was reverted. The quieter baseline is restored and checkpointed at `C:/Users/bot/Sentinel/captures/Marble_Compositor_Wire_baseline_restored.png`; the standalone wire source remains recoverable for a future dedicated overlay treatment.

## Comparison branch: chaos radial machine

`Marble_Branch_Chaos_Plan + Marble_Material_Profile + Marble_Branch_Lit_Lights + Marble_Branch_Lit_Field -> Marble_Branch_Chaos`

A new geometry root widens the orbital radius to 2.18, increases cutter scale to 1.48, pushes orbital twist to 1.42, and uses maximum asymmetry with a new seed. It produces a broader, more exploded radial machine than the retained lit-array root. The branch is independently healthy at approximately 34 FPS with 60 ray steps.

Checkpoint: `C:/Users/bot/Sentinel/captures/Marble_Branch_Chaos_fixed.png`.

The chaos machine was promoted into the graphic hierarchy as:

`Marble_Branch_Chaos + Marble_Frame_HUD_Oblique + Marble_Grid_Warp + Marble_Contour_Accent -> Marble_Compositor_Chaos`

The first composite ran at ~23 FPS, so its renderer was reduced from 60 to 48 ray steps. The retained composite is visually distinct and runs at approximately 29 FPS. Checkpoint: `C:/Users/bot/Sentinel/captures/Marble_Compositor_Chaos_tuned.png`.

Motion checkpoint: `C:/Users/bot/Sentinel/captures/recordings/Marble_Branch_Lit_Field_1784877982772.mp4` — 48 frame-locked frames sweeping `motion_rate` from 0.05 to 1.1, zero dropped frames, automatically restored after recording.

## Recoverable visual roots

- `captures/marble_sdf_renderer_host_camera.png` — exterior Orbit framing and camera proof.
- `captures/marble_sdf_renderer_chrome_faceted.png` — sharper faceted/chrome look.
- `captures/marble_sdf_renderer_lit_faceted.png` — stronger lighting branch.
- `captures/marble_sdf_renderer_black_chrome_final.png` — dark material baseline.
- `C:/Users/bot/Sentinel/captures/Marble_SDF_Renderer_1784877777933.png` — restored root, current batch.
- `C:/Users/bot/Sentinel/captures/Marble_Branch_Faceted_1784878212660.png` — retained faceted/lit crossbreed with dedicated lighting.
- `C:/Users/bot/Sentinel/captures/Marble_Branch_Lit_1784878476346.png` — retained orbit-array machine branch.

## Retained controls

- Sculpture plan: subtractive block, aperture, helix cutters, asymmetry, torsion.
- Material: black chrome, veins, cavity, pores, micro-normal.
- Glitch field: warp, twist, fold, slices, quantization, motion, seed, sequencer pulse.
- Light rig: key/fill/rim/slash/base/pulse lighting.
- Renderer: ray steps, chisel noise, chrome amount, edge break, exposure, Orbit/Fly camera.

## Pruned experiment

`sdf_industrial_world` was tested as a separate 24-record SDF world branch. It produced an unreadable over-fragmented result and was disconnected and destroyed in the live graph. Its authored module remains on disk only as a recoverable reference; it is not part of the active composition.

## Branch comparison and playback pruning

The expanded scene was compared as three full compositions: the lit orbit-array, the chaos radial machine, and the original oblique sculpture stack. The comparison checkpoints are `C:/Users/bot/Sentinel/captures/batch_array_wire.png`, `C:/Users/bot/Sentinel/captures/batch_chaos.png`, and `C:/Users/bot/Sentinel/captures/batch_oblique.png`.

The chaos branch is the most structurally divergent option; the orbit-array branch has the strongest readable industrial silhouette; the wire branch remains the fastest graphic playback surface. Heavy comparison compositors (`Marble_Compositor_Oblique`, `Marble_Compositor_Array`, and `Marble_Compositor_Chaos`) are now disabled but preserved in the graph. The wire compositor remains enabled, healthy, 1280x720, and verified at approximately 61 FPS, so the scene has a usable live baseline while the larger branches remain recoverable for the next comparison pass.

## Industrial enclosure branch

`modules/steel_lattice` was promoted as `Marble_Steel_Lattice`: an infinite repeated SDF structure with carved panel grooves, junction collars, bolts, weathered surface layers, fractal/shatter domain distortion, and its own camera-capable renderer. The initial close framing was rejected as an unreadable interior; the corrected proof is `C:/Users/bot/Sentinel/captures/Marble_Steel_Lattice_exterior.png`.

It was crossbred only at the compositor layer:

`Marble_Steel_Lattice + Marble_Grid_Warp + Marble_Contour_Accent + Marble_Frame_HUD_Oblique -> Marble_Compositor_Lattice`

The retained dark treatment is `C:/Users/bot/Sentinel/captures/Marble_Compositor_Lattice_dark.png`. It establishes a distinct industrial-enclosure branch with blue arc registration, orange index blocks, and sequencer-driven orbit motion. Both lattice nodes are disabled after proof so ordinary playback remains on `Marble_Compositor_Wire`, verified at approximately 60 FPS in `C:/Users/bot/Sentinel/captures/Marble_Compositor_Wire_after_lattice.png`.

## Faceted artifact branch

`modules/c1_polyhedron` was added as `Marble_C1_Polyhedron`, a deliberately different representation: a stellated faceted artifact with multi-axis phase motion, enlarged extrusion, and sharp edge response. Its standalone proof is `C:/Users/bot/Sentinel/captures/Marble_C1_Polyhedron_artifact.png`.

The complementary graphic crossbreed is:

`Marble_C1_Polyhedron + Marble_Grid_Warp + Marble_Contour_Accent + Marble_Frame_HUD_Oblique -> Marble_Compositor_Artifact`

The resulting instrument-like composition is captured at `C:/Users/bot/Sentinel/captures/Marble_Compositor_Artifact.png`. It was retained as a third recoverable visual root because its faceted stellation is visibly distinct from both the subtractive sculpture and industrial enclosure. Both artifact nodes are disabled after comparison; `Marble_Compositor_Wire` remains the ordinary playback surface.

## Pruned fractal-field experiment

The typed `fractal_seed_core -> fractal_field_render` pair was compile-checked and live-wired through the `Seeds` structured buffer. It was tested in Machine mode with high iteration, kaleidoscope, circuit density, and a dark palette. The result remained a diffuse full-frame wash without a useful focal hierarchy (`C:/Users/bot/Sentinel/captures/Marble_Fractal_Field_machine.png` and `C:/Users/bot/Sentinel/captures/Marble_Fractal_Field_dark.png`), so both live nodes were destroyed after comparison. The authored modules remain on disk as a recoverable reference, but the failed branch is not buried in the graph.

## Promoted visible branch

The faceted artifact branch was promoted into live playback after the wire baseline stopped producing a major visible delta. `Marble_Compositor_Wire` is parked, while `Marble_C1_Polyhedron` and `Marble_Compositor_Artifact` are enabled and the compositor window is open. The promoted live proof is `C:/Users/bot/Sentinel/captures/Goal1_artifact_promoted.png`.

The Dada Totem branch was tested from raw and front-facing camera views (`C:/Users/bot/Sentinel/captures/Goal1_Totem_raw.png`, `C:/Users/bot/Sentinel/captures/Goal1_Totem_front.png`) but deleted because it introduced a bright desert/figurative language incompatible with the current instrument composition.

## Consolidated final composition branch

The strongest compatible pieces were finally assembled into a dedicated six-layer module rather than leaving parallel bypass branches:

`Marble_Steel_Lattice (enclosure) + Marble_Branch_Chaos (hero) + Marble_Grid_Warp + Marble_Contour_Accent + Marble_Frame_HUD_Oblique + Marble_Wire_Cage -> Marble_Final_Composition`

`modules/marble_final_compositor` defines explicit hierarchy gains for enclosure, hero, wire cage, grid, contour, and HUD, with a dark-space shadow pass and contrast control. The lattice was customized with new spacing, panel/deformation settings, camera distance, dark steel, and sequencer-driven rotation/deformation; it is no longer the copied default look. The first and refined proofs are `C:/Users/bot/Sentinel/captures/Marble_Final_Composition_pass1.png` and `C:/Users/bot/Sentinel/captures/Marble_Final_Composition_pass2.png`.

The final compositor is enabled and open, healthy at approximately 30 FPS at 1280x720. The old wire and artifact compositors are parked, while their source modules remain available as recoverable material. The existing Trigger Sequencer continues to drive the HUD, lattice motion, and branch camera behavior.

## Monochrome motion and particle pass

The lattice and HUD motion rates were reduced at their sources so the enclosure and outer ring now move with the sculpture instead of jittering ahead of it. The HUD accent was converted from orange to white, retaining the blue-gray ring lines for separation.

`modules/micro_particles` adds a new procedural particle field with density, scale, spread, drift, seed, brightness, and monochrome color controls. It is consumed directly by `Marble_Final_Composition` as a seventh layer at low gain, providing sparse depth texture without competing with the Chaos hero. Proof: `C:/Users/bot/Sentinel/captures/Marble_Final_Composition_particles.png`.

## Portal-depth workshop addition

The next major construction added `modules/portal_field` as `Marble_Portal_Field`: animated concentric depth rings plus axial cuts, driven by the existing sequencer and consumed as an eighth layer in `Marble_Final_Composition`. Its raw proof is `C:/Users/bot/Sentinel/captures/Marble_Portal_Field_raw.png`; the integrated pass is `C:/Users/bot/Sentinel/captures/Marble_Final_Composition_portal2.png`. It provides a restrained intermediate spatial plane between the lattice enclosure and the Chaos hero rather than another foreground object.

## Aperture hierarchy pass

The portal-expanded image showed that the wire/grid textures were crossing the Chaos hero too uniformly. The final compositor now has a spatial hero aperture with adjustable radius and softness: wire and grid recede through the hero zone and return around the perimeter, while particles and portal depth are attenuated in the center. This is a compositing-architecture change, not a grade correction. Retained proof: `C:/Users/bot/Sentinel/captures/Marble_Final_Composition_aperture.png`.
## Dirty-lens glass pass and restored motion

`Marble_Dirty_Lens` wraps the complete composition with procedural glass warping, restrained chromatic separation, irregular dirt blooms, etched streaks, and micro-grain. Proof: `C:/Users/bot/Sentinel/captures/Marble_Dirty_Lens_refined.png`.

The expression-driven lattice jitter was removed. It now uses stable moderate rates (`rotate_speed 0.02`, `fx_speed 0.06`, wave speeds `0.13/0.16`) while the wire cage's sporadic movement remains intentional.

## Restored instrument motion and particle shell

The final compositor's wire gain was raised to `0.24` so the cage reads through the dirty lens. The oblique HUD was given stable opposing rotation rates (`-0.014/0.009`), restoring visible ring motion without returning to the old expression jitter. The Chaos renderer now owns a very small time-based camera yaw/pitch drift (`0.08/0.055` radian rates), keeping the sculpture alive as a whole rather than shaking individual layers.

`modules/particle_shell` adds a new outer spherical point field: 72 deterministic orbiting points, depth-weighted and edge-masked so it frames the sculpture without covering the hero. It is integrated as slot 8 of `Marble_Final_Composition` at low gain. Raw proof: `C:/Users/bot/Sentinel/captures/Marble_Particle_Shell_raw.png`; integrated proof: `C:/Users/bot/Sentinel/captures/Goal1_shell_motion_lens.png`.

## Refractive shard branch

`modules/shard_aperture` is a separate post-compositing branch consuming `Marble_Dirty_Lens`. It folds the image into four angular sectors with animated seam drift and edge glints, changing the representation from a flat lens view into a faceted optical aperture. It is healthy at 1280x720 and retained as a live comparison root rather than replacing the cleaner lens playback. Candidate proof: `C:/Users/bot/Sentinel/captures/Marble_Shard_Aperture_candidate.png`.
## Nested chamber branch

`modules/recursive_aperture` consumes the shard branch and creates three scale-stepped, rotated echoes inside separate radial bands. This changes the frame from a single optical fold into a receding chamber/tunnel while keeping the center readable. It is healthy at 1280x720 and retained as a second comparison root. Candidate proof: `C:/Users/bot/Sentinel/captures/Marble_Recursive_Aperture_candidate.png`.

## Temporal chamber branch

`modules/temporal_chamber` adds a persistent RGBA16F trail buffer after the recursive aperture. It combines the current chamber with a low-bleed memory of previous frames, creating architectural ghosting and a new persistence-based motion regime. The branch is healthy at 1280x720 around 25-26 FPS and retained as a third live comparison root. Candidate proof: `C:/Users/bot/Sentinel/captures/Marble_Temporal_Chamber_candidate.png`.

## Polar orbit branch

`modules/polar_orbit` consumes the temporal chamber and reprojects its memory into rotating radial bands while preserving the central aperture. This opens a new orbiting-field representation rather than another nested copy. It is healthy at 1280x720 around 26 FPS and retained as a comparison root. Candidate proof: `C:/Users/bot/Sentinel/captures/Marble_Polar_Orbit_candidate.png`.

## Orbit contour branch

`modules/orbit_contours` transforms the polar-orbit output into an edge-derived registration drawing with quantized bands and animated scan marks. It is intentionally much more graphic and crowded than the temporal branch, translating the sculpture into hard technical linework. It is healthy at 1280x720 around 25 FPS and retained as an exploratory root. Candidate proof: `C:/Users/bot/Sentinel/captures/Marble_Orbit_Contours_candidate.png`.
