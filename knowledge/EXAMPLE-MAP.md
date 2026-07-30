# Example Map

Use this map to choose a teaching reference, not a ready-made solution. Read the
selected project's README, inspect its saved graph, and reimplement the relevant
architecture for the current problem. Project-specific Modules are copied only
for an explicit fork or remix. See `example-authoring.md`.

## Collection at a glance

| Project | Saved graphs | Live/AI dependencies | Core route | Reviewed output | Study it for |
| --- | ---: | --- | --- | --- | --- |
| `autopsia` | 1 | Features | authored specimen → proxy → Features → stabilizer → relief/census → grade | `au_grade` | closed analysis loops, stable identities, data-driven annotation |
| `camera_reference` | 1 | none | camera-capable grid renderer | `Native_Camera_Reference` | the native internal camera contract |
| `cloth_lab` | 1 | Audio In | loopback audio → band analysis → XPBD cloth | `cloth_engine` | audio data ports, simulation, grabbing, tearing |
| `face_collage` | 1 | MediaPipe, StreamDiff, Background Removal | face tracking/guide → StreamDiff → accumulation/cutout/composite/post | Group Output | tracking-conditioned generative collage |
| `industrial_lattice` | 1 | none | infinite SDF lattice → monochrome post | `Post` | a compact two-node 3D graph |
| `interaction_lab` | 1 | Audio In | independent UI/editor stations plus two data routes | station previews | Canvas panels, splines, selection, gizmos, traces |
| `living_room_sdf` | 1 | none | architecture/furnishings/material/light records → SDF renderer → grade | `LR_Cinematic_Grade` | modular 3D construction and spatial editing |
| `scientific_organism` | 1 | Features | biotic source → proxy/Features → temporal/topology/memory layers → renderer/grade | Group Output | a large, inspectable analysis-to-render system |
| `strata` | 1 | Features | background/plates/layout/marks → feature-reactive renderers → composite/post | `post_1` | modular 2D composition and proxy analysis |
| `streamdiff_canvas` | 1 | StreamDiff, Depth, Background Removal | paint/pattern fields → depth controls → StreamDiff → cutout | `Collage_Cutout` | direct manipulation of generative conditioning |
| `streamdiff_workflows` | 6 | StreamDiff; Depth and Background Removal in study 05 | one focused routing pattern per graph | named StreamDiff/Mux/composite preview | small, isolated StreamDiff techniques |
| `touchdesigner_new_project` | 1 | image asset only | Hermite signal → texture → image displacement → geometry → output | `Out` | typed signal-to-texture modulation |

## Dependency and portability notes

- Every active Module is under its owning `projects/<project>/modules/` tree.
- No project links to a root Module catalog or another project's files.
- StreamDiff graphs require a compatible StreamDiff engine pack.
- Depth Estimation requires the compatible auxiliary depth pack.
- Background Removal requires its matting engine.
- MediaPipe, Features, Audio In, and authored Modules need no TensorRT pack, but
  their availability still comes from the live `list_types` response.
- `projects/streamdiff_workflows/assets/dancer_vert.mp4` and
  `projects/touchdesigner_new_project/images/jellybeans.png` are the only
  bundled runtime media assets.
- Scientifica-derived tables carry an OFL notice beside every retained copy.

## Project routes

### Autopsia

`au_stylus` publishes interventions to `au_specimen`. The specimen's plate is
shaped for analysis by `au_proxy`, observed by the real `features` node
`au_observe`, and stabilized into persistent agents by `au_stabilizer`.
`au_relief` and `au_census` render complementary interpretations; `au_grade`
produces the reviewed program image while `au_deck` supplies performance macros.

Remix seam: replace the authored specimen and redefine the semantic observations
while retaining the idea of stabilizing noisy findings before visualization.

### Camera Reference

`Native_Camera_Reference` is a single camera-capable Module with a black field,
thin antialiased ground grid, optional colored origin axes, and color/depth
outputs. It owns Sentinel's internal Fly/Orbit camera and keeps `camera_ref`
empty.

Remix seam: use the camera contract, not the grid's visual design.

### Cloth Lab

`cloth_audio` captures the current default loopback device. Its Spectrum data
feeds `cloth_bands`, which publishes musical envelopes and counters to
`cloth_engine`. The engine owns XPBD simulation, grabbing, cutting, rendering,
and the internal camera.

Remix seam: keep Audio In's chronological ring discipline and design a new
analysis/visual mapping for the user's material.

### Face Collage

`Face_Track`, `Face_DS`, and `Face_Guide` establish the face-conditioned guide.
`SD_Face` generates the photographic source. `Accum`, `Face_Cutout`,
`Clone_Overlay`, `Overlay_Comp`, `Editorial_Post`, and `Prompt_LFO` build and
shape the collage before `Face_Collage_Group_Output`.

Remix seam: change the editorial system and prompt behavior; do not treat its
collage Modules as generic templates.

### Industrial Lattice

`lattice` raymarches the repeated structural field with its native camera.
`Post` provides the final monochrome finishing pass. The two-node route is
intentionally legible and has no object-selection model.

Remix seam: study how a compact generator/post graph exposes only honest
controls.

### Interaction Lab

`Style_Authority`, `Motion_Console`, and `Gizmo_Desk` are independent authored
panel/editor stations. `Spline_Desk` publishes sampled path data to
`Spline_Output`. `Scope_Audio` feeds PCM/Spectrum data to `Data_Scope`;
`Signal_Trails` is another trace-oriented station.

Remix seam: copy interaction architecture only at the level of ideas—manifest
hit contracts, durable state, selection ownership, and responsive layout.

### Living Room SDF

`LR_Architecture`, `LR_Furnishings`, `LR_Materials`, and `LR_Lighting` publish
separate scene records. `LR_SDF_Renderer` consumes the construction data and
owns the native camera. `LR_Cinematic_Grade` is the final presentation pass.

Remix seam: preserve separable plans and typed records, then define new object
kinds, relations, materials, lighting, and rendering for the requested space.

### Scientific Organism

`Scientific_Seed_Lab` controls the system. `Scientific_Biotic_Source` feeds
`Scientific_Analysis_Proxy` and `Scientific_Features`; temporalized findings
drive the topology, synaptic field, filament memory, spectral archive, relief,
glyph, and final renderer layers. `Scientific_Performance_Deck` shapes the live
system, `Scientific_Final_Grade` finishes it, and
`Scientific_Organism_Output` marks the Scene Group result.

Remix seam: study responsibility boundaries and intermediate previews in a
large graph, not its scientific-instrument aesthetic.

### Strata

`strata_bg`, `marble_panel`, `blob_layout`, and `marks` establish the
composition. `features_0` analyzes an explicit proxy branch. `blob_render`,
`wire_render`, and `corner_thread` map structure and findings into layers;
`plate_comp` combines them and `post_1` finishes the image.

Remix seam: retain the distinction between composition data, analysis proxy,
layer renderers, and final treatment.

### StreamDiff Canvas

`Paint_Canvas` and `Pattern_Canvas` capture persistent authored input.
`Radial_Gradient` and three instances of `Pattern_Depth_SDF` shape spatial depth
fields. `depthestimation_0` supplies image depth, `Generation_Controller`
coordinates generation, `Collage_Diffusion` renders the photographic collage,
and `Collage_Cutout` supplies the reviewed isolated result.

Remix seam: invent new direct-manipulation fields and prompt semantics while
preserving the separation between editable control images and generation.

### StreamDiff Workflows

The folder contains six independent graphs:

1. `01_2d_feedback_zoom.sentinel`: one StreamDiff node using 2D feedback.
2. `02_depth_parallax_zoom.sentinel`: one StreamDiff node using depth-parallax
   motion.
3. `03_backrooms_flythrough.sentinel`: one StreamDiff flythrough setup.
4. `04_direct_variant_mux.sentinel`: three StreamDiff variants selected by
   `Direct Variant Mux`, with `Variant Switcher UI` demonstrating automatic
   selection.
5. `05_video_depth_control.sentinel`: bundled dancer video → Depth Estimation →
   `Depth Threshold` → StreamDiff control; the original-video matte masks the
   generated dancer before `Generated Over Original` composites it.
6. `06_procedural_warp_map.sentinel`: `Procedural Flow Map` drives a StreamDiff
   warp input.

Open one at a time to avoid unnecessary engine-memory pressure.

### TouchDesigner Starter

The bundled `Jellybeans_Image` source and `Hermite_Signal` feed
`Signal_to_Texture`. `Vertical_Displace` applies that texture to the image,
`Geometry_Pass` presents the displaced surface, and `Out` is the final texture.

Remix seam: use the typed signal-to-texture boundary to replace familiar
operator wiring with a purpose-built Sentinel graph.
