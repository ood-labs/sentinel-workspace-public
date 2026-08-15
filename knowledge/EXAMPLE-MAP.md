# Example Map

Use this map to choose a teaching reference, not a ready-made solution. Read the
selected project's README, inspect its saved graph, and reimplement the relevant
architecture for the current problem. Project-specific Modules are copied only
for an explicit fork or remix. See `example-authoring.md`.

## Collection at a glance

| Project | Saved graphs | Live/AI dependencies | Core route | Reviewed output | Study it for |
| --- | ---: | --- | --- | --- | --- |
| `autopsia` | 1 | Features | authored specimen → proxy → Features → stabilizer → relief/census → grade | `au_grade` | closed analysis loops, stable identities, data-driven annotation |
| `axon_press` | 1 | none | plan authority → press renderer → screen-fixed ink surface | `AX_Ink` | endless axonometric fall, fractal plate collage, print-finish post |
| `benthic_plate` | 1 | none | plan authority/editor → growth expansion → tile-binned SDF march → printed plate | `BP_Plate` | screen-space tile binning of an acceleration layer, subtractive records, captions that are real readings |
| `camera_reference` | 1 | none | camera-capable grid renderer | `Native_Camera_Reference` | the native internal camera contract |
| `cantilever_canyon` | 1 | none | plan authority/editor → parts+bounds → SDF march → atmosphere finish | `CC_Grade` | a purely relational record contract, a section-over-elevation scaffold with a standability readout, group-bounded marching |
| `candy_effigy` | 1 | none | plan authority/editor → raymarched cast → lens finish | `CE_Grade` | world-space domain distortion as one coherent field, size-preserving record contract, the cost model of a warped march |
| `cloth_lab` | 1 | Audio In | loopback audio → band analysis → XPBD cloth | `cloth_engine` | audio data ports, simulation, grabbing, tearing |
| `droste_heads` | 1 | none | 2D face sketch + plan authority → raymarch → ink outlines | `DH_Ink` | flat cartoon art painted onto 3D as a decal, seamless recursive-zoom loop |
| `face_collage` | 1 | MediaPipe, StreamDiff, Background Removal | face tracking/guide → StreamDiff → accumulation/cutout/composite/post | Group Output | tracking-conditioned generative collage |
| `industrial_lattice` | 1 | none | infinite SDF lattice → monochrome post | `Post` | a compact two-node 3D graph |
| `interaction_lab` | 1 | Audio In | independent UI/editor stations plus two data routes | station previews | Canvas panels, splines, selection, gizmos, traces |
| `kuka_cell` | 1 | none | cell plan authority/editor → ball/rally authority → four-channel choreographer + FK → SDF arm renderer | `KA_Robot` Program | a lattice randomizer that keeps an array an array, choreography whose phase is derived from floor position, a shared-object authority a crowd of agents responds to, per-tile instance culling |
| `living_room_sdf` | 1 | none | architecture/furnishings/material/light records → SDF renderer → grade | `LR_Cinematic_Grade` | modular 3D construction and spatial editing |
| `matik_plate` | 1 | none | interactive plan authority → organisms + instruments + circuitry → composite → post | `MX_Post` | plan authority, generate-then-override editing, hybrid record contract |
| `ossuary_bloom` | 1 | none | plan authority/editor → growth expansion → studio env → SDF renderer → macro-lens post | `OB_Post` | anchors expanded into drawables with their own acceleration bounds in one buffer, and a catalogue of SDF faults that all present as bad lighting |
| `pink_monolith` | 1 | none | plan authority → three press layers → action lines → image effects → print finish | `PM_Ink` | a full entrance/exit lifecycle for every record, compositional armatures, shape vocabularies as handles |
| `prism_reliquary` | 1 | none | plan authority/editor → studio env → SDF renderer → filmic post | `PR_Post` | filmic rendering: thin-film refraction, bokeh depth of field, HDR bloom, layered antialiasing |
| `reactor_shaft` | 1 | none | plan authority/editor → shaft renderer → lens finish | `RS_Lens` | endless machine-shaft zoom, role-discriminated record cast, emissive machinery |
| `scientific_organism` | 1 | Features | biotic source → proxy/Features → temporal/topology/memory layers → renderer/grade | Group Output | a large, inspectable analysis-to-render system |
| `skein` | 1 | none | plan authority (route/squadrons) → flock sim → sky panorama → per-bird march → scope/grade | `SK_Grade` | boids with bird-specific terms, a flight plan whose diagram draws its own failure modes, per-bird bounding-sphere marching with screen-tile lists |
| `soft_vitrine` | 1 | none | plan authority → stage/growth → volumes + strokes + plates → composite → post | `VT_Post` | hybrid 2D/3D record contracts, coverage lanes, seeded arrangement randomization |
| `strata` | 1 | Features | background/plates/layout/marks → feature-reactive renderers → composite/post | `post_1` | modular 2D composition and proxy analysis |
| `streamdiff_canvas` | 1 | StreamDiff, Depth, Background Removal | paint/pattern fields → depth controls → StreamDiff → cutout | `Collage_Cutout` | direct manipulation of generative conditioning |
| `streamdiff_workflows` | 6 | StreamDiff; Depth and Background Removal in study 05 | one focused routing pattern per graph | named StreamDiff/Mux/composite preview | small, isolated StreamDiff techniques |
| `sunward_corridor` | 1 | none | plan authority/editor → corridor renderer → grid finish | `SC_Grid` | endless periodic zoom, one record contract for architecture and organic masses |
| `koi_tank` | 1 | none | plan authority → water sim → photon caustics → koi school → optics → exploded instrument → post | `TP_Post` | wave simulation, photon caustics, procedural koi SDF, boids, depth-composited 3D overlay of live data |
| `touchdesigner_new_project` | 1 | image asset only | Hermite signal → texture → image displacement → geometry → output | `Out` | typed signal-to-texture modulation |
| `vitreous_cross` | 1 | none | plan authority/editor → studio env → SDF renderer → filmic post | `VC_Post` | ray-marched glass with real air-cavity lenses, HDR studio lighting, interior plates |

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

### Benthic Plate

`BP_Plan` is the plan authority and editor over one 160-record buffer where `role` separates a
plate header, specimens, limbs and captions. Its canvas is an **elevation over a skeleton strip**:
the elevation owns where each specimen sits, the skeleton strip blows up the selected specimen's
limb tree in its own local space, because a footprint disc cannot show branch topology. `BP_Growth`
expands limb anchors into curled marchable parts and publishes bounding capsules in the same
buffer. `BP_Render` bins those bounds into 16px screen tiles before marching, and publishes
RGBA16F with linear depth in alpha. `BP_Plate` is the printed finish.

Study it for the **tile-binned acceleration layer** — the marcher tests only the runs its own tile
can see, which turns cost into "how much ink is under this pixel" — and for **subtractive records**:
fenestration holes are their own part kind because a void carved per segment is refilled by the
neighbouring segments, and because a subtraction must never be pruned by a distance early-out.
Also for **captions that are real readings**, derived from the anchored specimen's live record and
suppressed when the field does not apply to that kind.

Remix seam: take the tile binning, the subtraction-record contract and the two-projection scaffold.
Do not take the bone/cobalt specimen cast.

### Camera Reference

`Native_Camera_Reference` is a single camera-capable Module with a black field,
thin antialiased ground grid, optional colored origin axes, and color/depth
outputs. It owns Sentinel's internal Fly/Orbit camera and keeps `camera_ref`
empty.

Remix seam: use the camera contract, not the grid's visual design.

### Candy Effigy

`CE_Plan` is the plan authority and editor: it owns stage space and decides what is in
the cast, where it sits, how deep it is and what colour it wears, over one persistent
32-record `Icons` buffer discriminated by `kind`. `CE_Cast` ray-marches that cast and
re-decides nothing about placement or palette; it owns the internal camera, the light rig
and every surface. `CE_Grade` is the lens finish.

Study it for the **`scale` contract** — one number meaning half the icon's width
everywhere, so cycling a record's kind preserves its footprint with no bookkeeping and the
size table reads directly as the composition's hierarchy. Also for **domain distortion
evaluated in world space before any local transform**, which is what makes the cast read as
suspended in a liquid rather than as per-object modifiers, and for its **cost model**: a
warp stretches space, so the distance stops being a bound, every step shrinks, and
frequency costs exactly as much as amount. Its README documents a measured 30.6 → 108.8 fps
recovery, most of it an over-estimated Lipschitz bound.

Remix seam: take the stage-space/pick-coordinate unification, the size contract, and the
isolation control that routes a deterministic fraction of records into an effect. Do not
take the kawaii vocabulary or the pale sage card.

### Cantilever Canyon

`CC_Plan` is the plan authority and editor: a worm's-eye brutalist canyon where a mass stores
**who it hangs off, not where it is** — host, attach face, offset along that face, and how far it
bites in. World transforms are a RESULT, resolved once into a cache riding above `CC_WORLD_BASE`
in the same buffer, so nothing downstream re-decides placement. `CC_Fabric` expands masses into
marchable parts, derives the rail runs from the two masses each spans, and publishes a spatial
partition with per-group bounds in the same buffer. `CC_Render` marches with its internal camera
and publishes linear depth in alpha; `CC_Grade` is atmosphere and film.

Study it for the **purely relational record contract** — the clearest case in the collection where
the subject's identity is interlocking rather than position, so randomising coordinates produces
debris and randomising relationships produces buildings. Also for a **scaffold genuinely tailored
to its subject**: a section over an elevation sharing the lateral axis, because the drama is reach
over the void and a front elevation cannot show reach — carrying an interpenetration alarm, a
protected-slot-core alarm, and a **sight line that turns red when there is nowhere in the canyon
the eye can stand**. Its README documents the depth-in-alpha capture trap, unnormalised AO turning
a reach control into a strength control, and why painted joints cannot make a facade brutalist.

Remix seam: take the host/face/offset/bite contract, the guarantee list, and the standability
readout. Do not take the concrete-and-overcast palette or the transcribed parent tree.

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

### KUKA Cell

`KA_Cell` is the plan authority for a floor of six-axis industrial arms: a plan
strip over an elevation strip sharing one metres-per-pixel scale, with an
inspector column, click-select and drag-move, and the Point At target held as a
record so it is dragged on the floor rather than typed. `KA_Pose` reads those
records and runs four independent pattern channels through joint limits and
forward kinematics. `KA_Robot` marches the arms with the native internal camera
and publishes a clean Program plus an annotated Scope from one solve.

Study it for three things it does differently from the other plan-authority
projects. Its randomizer perturbs **lattice parameters** rather than record
coordinates, because an array's identity is its regularity and a free draw per
element reads as debris. Its choreography derives each element's phase from
**where that element actually stands**, so moving one arm changes when it moves
as well as where it is, and the channel split is computed from the layout rather
than stored as a routing table. Its renderer makes forty-eight instances
affordable with **per-tile cooperative culling**: each thread group tests every
instance against its own view cone and compacts the survivors into a groupshared
list.

`KA_Rally` is the fourth node and the reason to read this project even if robots
are irrelevant to you. It keeps a beach ball up between the arms, and it exists
as its own authority because a ball is **one shared object with its own state**
that a crowd of agents responds to — which is a different shape of problem from
a per-agent function of phase, and cannot be expressed as another entry in a
pattern enum. Participation is a channel mode decided in that one place, so half
a cell can play while the other half keeps running its patterns.

Read the README for two failure catalogues: the phantom-bound shading trap,
which will recur in any instanced SDF scene, and the four bugs between "245
serves and zero completed hits" and a 78-touch rally — the last of which was
found only by measuring, because the obvious suspect turned out to change
nothing.

Remix seam: the relational-randomizer question ("what relationships make this the
thing it is?"), the derive-phase-from-placement contract, and the shared-object
authority — not the arm geometry.

### Living Room SDF

`LR_Architecture`, `LR_Furnishings`, `LR_Materials`, and `LR_Lighting` publish
separate scene records. `LR_SDF_Renderer` consumes the construction data and
owns the native camera. `LR_Cinematic_Grade` is the final presentation pass.

Remix seam: preserve separable plans and typed records, then define new object
kinds, relations, materials, lighting, and rendering for the requested space.

### Matik Plate

`MX_Console` is the plan authority: it generates the whole plate layout procedurally and lets
click/drag/keyboard interaction override individual records, publishing one 128-record `Plate`
buffer where `role` separates instrument cells from organism anchors. `MX_Organism` grows
branching molecular trees from those anchors, sizing them from the reserve discs the console
cleared. `MX_Wireframe` rasterizes them as opaque solids with white mesh lines and owns the
internal camera. `MX_Instruments` and `MX_Circuitry` draw the panels and the connective field.
`MX_Composite` stacks the layers, re-deriving panel knockout from the same records, and
`MX_Post` finishes the image.

Remix seam: take the plan-authority and generate-then-override architecture, not the
monochrome technical-plate aesthetic. See `knowledge/reference-build-method.md`.

### Ossuary Bloom

`OB_Plan` is the plan authority and editor over one 96-record `Cast` buffer whose `role`
separates eight families, and it owns the show clock. `OB_Growth` expands those anchors
into the primitives that actually get marched, plus one conservative bounding sphere per
anchor. `OB_Env` authors the studio as a lat-long HDR panorama and light records.
`OB_Render` marches four materials and publishes RGBA16F **with linear depth in alpha**;
`OB_Post` is the macro lens.

Study it for the **acceleration layer riding in the same buffer as the parts** above
`GROUP_BASE`, so one data link carries the whole drawable scene and the marcher can never
be handed parts whose bounds came from a different cook. Also for its **trap catalogue** —
compounding `smin` inflating a phantom shell, a swept section with no longitudinal extent
becoming an infinitely thin surface, a discriminated buffer's bare `else` rendering
bounding volumes as dark spheres, and anisotropy bounds that starve the march. Every one of
them presents as a lighting fault rather than a geometry fault, which is the actual lesson.

Remix seam: take the anchor→parts→bounds expansion and the diagnostic `View` enums. Do not
take the bone/chrome/crimson cast.

### Pink Monolith

`PM_Plan` is the plan authority over a 128-record buffer where `role` separates the
panel architecture from spills, discs, screens, blades, tubes, a figure and props, and
where **paint order is a record field** (`z`) rather than a lane — so a record can be
dragged through the stack and a different renderer draws it without changing what it
is. `PM_Surface` and `PM_Material` are two independent surface libraries addressed as
one flat fill number space (0-15 ruled, 16-31 hand/material). `PM_Ground`,
`PM_Structure` and `PM_Gesture` are three press layers compositing in paint order;
`PM_Accent` derives anime-style action lines from record motion and publishes nothing;
`PM_Effect` is the only layer that touches pixels it did not draw; `PM_Ink` is the
print finish.

Study it for the **entrance/exit lifecycle**: every record carries a drawn pose, a rest
pose and a next-arrangement pose, and the renderers contain no animation code at all —
they draw whatever pose the plan hands them. Also for the **armature**, a set of
beziers derived from the mass along which the sharp families are strung, and whose
tangent becomes each element's heading — so entrance motion follows the armature for
free, because the Slide archetype already travels along a record's own heading.

Remix seam: take the paint-order-as-a-record-field scaffold, the armature, and the
category-weight pattern for making a shape vocabulary steerable. Do not take the hot
pink/violet palette or the transcribed reference coordinates.

### Prism Reliquary

`PR_Plan` is the plan authority AND a direct-manipulation editor: it generates the whole
composition from reference-image coordinates, lets you click-select, drag, and re-material
individual elements over a persistent signature-driven buffer, and owns the show clock.
`PR_Env` authors the studio as a lat-long HDR panorama, so every chrome, glass and fur
highlight in the scene is reading one light rig. `PR_Render` ray-marches the whole cast with
its internal camera and publishes RGBA16F **with linear depth in alpha**. `PR_Post` is the
lens: gather-bokeh defocus, bloom, flare, aberration, grade, ACES, edge AA.

Study it for **filmic quality** — a real thin-film interference model for the refractive
membrane, depth of field with proper bokeh rather than a gaussian, HDR that survives the node
boundary, and an antialiasing strategy that treats three different aliasing sources with
three different tools. Its README documents the traps, including the `working_format` vs
`output_format` distinction that silently kills a depth lane.

Remix seam: take the optics and the plan-authority-as-editor architecture. Do not take the
specific cast of objects.

### Scientific Organism

`Scientific_Seed_Lab` controls the system. `Scientific_Biotic_Source` feeds
`Scientific_Analysis_Proxy` and `Scientific_Features`; temporalized findings
drive the topology, synaptic field, filament memory, spectral archive, relief,
glyph, and final renderer layers. `Scientific_Performance_Deck` shapes the live
system, `Scientific_Final_Grade` finishes it, and
`Scientific_Organism_Output` marks the Scene Group result.

Remix seam: study responsibility boundaries and intermediate previews in a
large graph, not its scientific-instrument aesthetic.

### Skein

`SK_Field` is the plan authority and editor: it owns the airspace, the sun, the wind, a closed
ROUTE of linked waypoints and the SQUADRONS that fly it, over one persistent 32-record buffer
discriminated by `role`. `SK_Flock` is the flock authority — virtual squadron leaders fly the route
and provide the moving frame every formation station is expressed in, while a boids solve with a
forward-only field of view and wingtip UPWASH SEEKING decides where each bird actually is.
`SK_Sky` authors the sky as a lat-long HDR panorama so the renderer gets its background and its
ambient from the same pixels. `SK_Render` marches each bird inside its OWN bounding sphere, fed by
a per-screen-tile bird list, and publishes RGBA16F with linear depth in alpha. `SK_Scope` is a
depth-composited 3D instrument branch; `SK_Grade` is the print.

Study it for the **scaffold that draws its own failure modes**: the plan strip draws a corner
tighter than the coordinated-turn radius as the red fillet arc that does not fit, and the elevation
strip draws a leg steeper than the birds can climb plus the clearance floor. Also for **relational
randomisation** — bird positions are simulated, so `variation` re-draws the waypoint *order*, not
coordinates — and for a **preview framing** lesson: a diagram of flocking cannot be drawn at
airspace scale, and the fix is a subject-following frame with a locator inset.

Remix seam: take the flight-plan-as-plan-authority architecture, the upwash term, and the per-bird
bounding-sphere march. Do not take the goose.

### Soft Vitrine

`VT_Plan` is the plan authority: it owns stage space and the horizon, generates the
whole composition procedurally, and holds click/drag/key overrides in one 64-record
`Plan` buffer where `role` separates flat plates from stroke anchors, mass anchors and
a global stage record. `VT_Stage` draws the cyclorama and reflective floor.
`VT_Growth` expands the anchors into a single `Limbs` buffer — world-space capsule
chains for the sculpted masses, stage-space polylines for the drawn marks — and
publishes a bounding sphere per group so the renderer can cull. `VT_Volumes`
ray-marches the masses across clay/chrome/frost/gloss and owns the internal camera,
`VT_Strokes` draws the marks as lit tubes, and `VT_Plates` renders the flat graphic
family split into back and front layers. `VT_Composite` stacks the four layers and
derives the drop shadow and floor reflection from total coverage; `VT_Post` finishes.

Remix seam: take the hybrid record contract — one buffer, `role` discriminated, with
2D and 3D families living side by side — and the `Variation`/`Seed` randomizer whose
stratified placement and preserved size hierarchy keep a random draw composed. Do not
take the electric-blue toy-plastic palette.

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

