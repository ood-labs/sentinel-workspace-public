# Sentinel Agent Manual

This workspace is the user-writable Sentinel agent workspace. It is seeded by Sentinel and contains:

- `.mcp.json`: connects this agent to the bundled `sentinel-mcp.exe`.
- `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`: identical entry instructions for common agents.
- `.claude/skills/` and `.agents/skills/`: curated user-facing skills.
- `knowledge/`: product reference docs. Start with `knowledge/FEATURE-MAP.md`.
  Use `knowledge/performance-proof.md` when you need to prove or diagnose runtime performance.

Sentinel is a GPU-accelerated live video application for performance and interactive visuals. It combines Spout/NDI/camera/image/pattern/video sources, real-time AI generation, tracking, depth, segmentation, object detection, shader modules, and Spout/NDI output.

## Workspace Ownership

The default Sentinel workspace mirrors the installed application version. Refresh Workspace resets its managed manuals, knowledge, and skills to the installed copies. A custom workspace path is fully user-owned. Sentinel seeds an empty custom workspace once and leaves every non-empty custom workspace unchanged. Ask your agent to use the `update-workspace` skill when you want to bring a custom workspace up to date from the public workspace repository.

## First Rule: Discover Live

Do not guess what this install can create. Ask Sentinel.

Use:

- `sentinel_app action=ping`: verify the app is running.
- `sentinel_pipeline action=list_types`: authoritative build-derived pipeline catalog.
- `sentinel_app action=capabilities`: authoritative IPC command list and accepted args.
- `sentinel_app action=engine_status`: GPU architecture, engine packs, download progress, queue.
- `sentinel_pipeline action=info pipeline_id=<id>`: parameters, outputs, health, and stats.

The shipped docs are a guide, but the live MCP surface is the source of truth for this exact build.

## Never Use Diagnostic Test Imagery As Creative Input

Never create or use Sentinel's built-in Pattern source, color bars, checkerboards, test cards, or other diagnostic test imagery as input to Features, tracking, AI, or any authored visual chain. This prohibition includes temporary scaffolding and technical data-contract proofs: diagnostic imagery must not appear in visible construction, intermediate previews, captures, or final proof.

When a creative build needs a source, use a meaningful user-provided or live source (camera, video, image, Spout, or NDI), or author a visually intentional generator Module as the first semantic node. If no meaningful source is available, author that generator before creating or testing downstream analysis. A technically convenient test signal is not an acceptable substitute for the requested creative composition.

## Problem-Led Creative Direction And Planning

Do not impose a house aesthetic when the user has not specified one. Derive the
visual language from the subject, source material, venue, interaction, and
desired emotional effect. Make a concrete choice of composition, palette,
typography, material, and motion that fits that problem; avoid generic neon,
glow, glass, HUD chrome, or any other fashionable default unless it genuinely
serves the work.

Before an ambitious creative graph, establish a short direction plan covering source semantics, analysis tasks, data-to-visual mappings, motion language, palette, interaction contract, and proof criteria. An explicitly exploratory run may stay loose, but it must still choose a meaningful source and state what each analysis or interaction node is supposed to contribute before building downstream.

Every number or label must derive from real live state and remain attached to what it describes. Every authored interaction must cause an immediate, legible, creatively useful change that is meaningfully better than an ordinary Properties control. Do not add stage drags, momentary buttons, fake telemetry, or decorative controls merely to make a composition appear interactive; remove controls that prove weak, redundant, or unclear.

## Ambitious Builds From A Reference

When the job is to build a specific ambitious result from a reference image or brief, read `knowledge/reference-build-method.md` first. Before writing code, inventory every visual element in the reference and name the node decomposition and data contract; hybrid references are normal and unify under one record buffer with a `role` discriminator.

Elect one plan-authority node that owns placement; downstream nodes derive from its records and never re-decide them. Whenever the composition has an arrangement worth randomizing or exploring — most reference work — that plan authority must be DIRECTLY MANIPULABLE, not a seed and a variation slider: select an element, move it, and change the two or three properties that actually define it, over a persistent signature-driven record buffer so edits survive. "The brief was an image, not an editor" does not exempt it, and neither does the fact that injected input cannot machine-prove the gestures — build them and report what needs exercising by hand. A generative node must generate a complete result procedurally and let interaction override individual records, so it is useful before it is edited. Build exploration axes as shipped `enum` presets: sweep them, bake the winner as the default, and repair the losers instead of deleting them. Bake tuned values into manifests before the final save, and state plainly whatever you could not verify.

**Design the scaffold for the subject. The plan authority is a CONTRACT, not a template.** What is fixed is single authority, persistent records, direct manipulation, and an honest preview. What is wide open — and what you are expected to be inventive about — is the projection, the verbs, and the readouts. Ask what a draughtsman would actually draw for *this* thing, then build that. One front elevation is the right answer for a frontal collage and the wrong answer for anything whose depth, height, or extent along a path carries the composition; a single view that cannot show the axis the subject is organised along is a scaffold that hides its own subject. Reach for a second or third projection, a section scrubbed along a path, a timeline, a network view, or a spatial readout with a correctness check built in, whenever the subject is organised that way. `projects/sunward_corridor/modules/SC_Plan` is the bar for tailoring: a draughtsman's plan-over-elevation sharing one z axis, where the plan strip owns lateral drift and the elevation strip owns rise from the same handle, plus a flight-path line that turns red where the corridor bends through its own wall. `projects/soft_vitrine/modules/VT_Plan` is the bar for editing flexibility and for randomness that still composes. Study both; copy neither.

**Ship narrow-scoped node presets as part of the build, not as an afterthought.** A preset that saves everything is a snapshot; a preset that saves one concern is a tool. Save each to project scope with an explicit `params` list, and give every ambitious build at least these two families:

- **A frame contract** on the renderer, scoped to the camera parameters ALONE — the pose you composed to. The internal camera is meant to be flown, so the composed viewpoint is lost the first time anyone explores, and it is not recoverable from anything else in the project. Save it as soon as the pose is chosen, and recall it before any final capture.
- **A quality ladder** on any node heavy enough to be worth trading, scoped to the quality parameters ALONE, roughly Draft / Live / Beauty / Hero. The manifest defaults must be a rung you can comfortably *work* in — never the top rung; a project that opens too heavy to touch is a broken deliverable. Make the top rung genuinely capture-only and say so in its name or the README, because at some cost it stops being slow and starts making the whole application unusable. Measure each rung, publish the numbers as ratios rather than absolutes, and state what else was running: identical presets measured 3-5x apart depending only on how many node previews were open.

Extend the same idea wherever a build has separable concerns worth recalling independently — a look, a palette, a motion feel. Narrow scope is the whole point: recalling the camera must not disturb the look, and recalling a quality rung must not disturb the framing.

**Decide what a re-roll means while you are still inventorying, not after the build.** Randomizable arrangement is a layout-time design decision, so name the exploration handles alongside the node decomposition and data contract. Then randomize whatever actually carries the subject's identity: for a scatter that is coordinates, but for anything whose identity is RELATIONAL — interlocking, containment, attachment, adjacency, periodicity — drawing fresh coordinates per record destroys the very relationships that make it the thing it is, and every seed reads as debris no matter how well stratified the draw is. Randomize the relationships instead, and give the draw explicit guarantees (see `knowledge/reference-build-method.md`) so an arbitrary seed is presentable by construction rather than by luck. Once the reference is transcribed and proven, push past it: the transcription is the floor, not the ceiling.

## Examples Are References, Not A Stock Module Library

Choose references in proportion to the problem. Start with the smallest useful
evidence set, then widen it when each additional reference answers a specific
unresolved question about architecture, data contracts, visual language, or
proof. A familiar single-node operation may need only its matched skill fixture.
A novel or ambitious system may justify several examples. Do not enumerate or
recursively read the project collection by default. Stop browsing when the
design and proof plan are clear enough to begin authoring, then return to
references if implementation reveals a real gap.

When project-level reference is useful, use `knowledge/EXAMPLE-MAP.md` to select
the strongest match before opening project files. Inspect only the relevant
graph, README sections, data contracts, and proof strategy, then invent the
implementation that best fits the current user's problem. Do not copy
project-bundled generators, renderers, layouts, palettes, controls, or
compositors into a new project unless the user explicitly asks to fork, remix,
or extend that exact example.

Reusing a module already authored in the user's current project is normal when
it remains the right abstraction. Generic infrastructure with no creative
identity of its own—licensed font tables, low-level math helpers, or the neutral
`tools/templates/module-ui/` scaffold—may also be vendored into the owning
project. Preserve licenses, copy only the recursive dependency closure, and
never link one project to another project's Module directory. See
`knowledge/example-authoring.md`.

## Sentinel Launch Safety

Sentinel must run in the active interactive Windows desktop. Never launch `sentinel.exe` from Windows Session 0, a service, SSH background execution, or any headless or non-interactive context. Check the agent process session ID before every launch. Reuse a user-launched Sentinel instance in the active desktop session, or use an explicitly interactive `/IT` scheduled task and verify the resulting process session ID before testing. MCP and raw localhost IPC can connect across sessions after the interactive app is running.

## First-Run Engine Setup

Some pipelines need TensorRT engine packs, and a fresh install may have none. Call `sentinel_app action=engine_status`, pick the needed pack for the user's GPU architecture, call `download_pack` or `install_pack`, and poll `engine_status` until the pack is `complete`. See `knowledge/first-run-engines.md`.

For a quick first proof, install pack `auxiliary`, create `depthestimation`, connect a meaningful live/user source or an authored generator Module, and verify `stats.healthy=true` with `framesProcessed` climbing. Never use the built-in Pattern source or diagnostic test imagery for this proof.

License activation is deliberately manual in the app UI.

## Pipeline Types In DIST Builds

Call `list_types` for the exact current catalog; DIST builds intentionally omit dev-only and experimental types. The full DIST type table — roles, visibility, engine-pack requirements, and the compatibility aliases (`facemesh`, `shaderproject`) — lives in `knowledge/FEATURE-MAP.md`.

Orientation: `module` (authored multi-pass HLSL projects) and `hlslshader` for authored visuals; `streamdiff` for real-time generation; `mediapipe`, `features`, `detection`, `pose`, `depthestimation`, `personseg`, `matting`, and `opticalflow` for tracking and analysis; `meshsource` for static 3D import; `audio` for WASAPI/WAV audio data; `vsr` for upscaling; `conductor`, `mux`, `groupoutput`, `atlas`, `camera`, and `camswitch` for choreography and the scene system.

## Graph Basics

Use video links for textures and data links for structured buffers.

- `sentinel_pipeline action=create_source`: create pattern, image, video file, Spout, NDI, or capture sources.
- `sentinel_pipeline action=create`: create a pipeline.
- `sentinel_pipeline action=set_input`: connect video texture inputs.
- `sentinel_graph action=add_link`: connect typed data ports.
- `sentinel_graph action=auto_layout`: arrange a whole graph only for explicit batch work or smoke tests.
- `sentinel_graph action=layout_neighborhood`: arrange a local area without disturbing a hand-arranged graph.

After creating and wiring nodes, always inspect real runtime state. A successful create call is not proof that the node is processing.

## Visible, One-Node-at-a-Time Construction

When building or extending a live creative graph, work one semantic node at a time so the user can watch and evaluate the graph as it takes shape. Do not pre-author every planned Module, issue concurrent node-creation calls, hide multiple creations in a batch or loop, or create the whole graph before showing it. Only use a batch/background workflow when the user explicitly requests one. This live-authoring rule overrides general tool-call parallelization guidance for node authoring and graph mutation; parallel read-only discovery is allowed only when it does not obscure the visible sequence.

Complete this entire cycle before authoring or creating the next node:

1. Author or select only the current node and any unavoidable shared prerequisite. Compile-check a custom Module before creating it.
2. Create only that node. Immediately place it near its neighbor with create-time `relative_to` placement or `sentinel_graph action=place_relative`, then add its currently known links.
3. Wait for compilation and inspect health, frames, schemas, and data counts as applicable.
4. Call `sentinel_graph action=focus`, then `sentinel_pipeline action=open_window` so the node and its live preview/Properties are visibly presented to the user.
5. Exercise the node's important controls and confirm that the preview changes as intended. Capture the intermediate output or data port when useful.
6. Fix a blank, constant, generic, misleading, or illegible preview before continuing downstream. `stats.has_preview_srv=true` proves only that a texture exists.

Continue through the cycle without requiring approval after every node unless the user asks for checkpoints. The requirement is visible incremental construction, not stop-and-confirm gating.

Preserve the graph's evolving layout with `place_relative`, explicit geometry, or `layout_neighborhood`; never use whole-graph `auto_layout` to repair or hide bulk creation. Whole-graph `auto_layout` is appropriate only when the user explicitly requests it or when topology surgery leaves the graph unreadable in signal-flow order — treat that as a layout-only checkpoint: inspect the graph first, run it, verify the new order, then refocus and reopen the active node.

Generator, plan, layout, assembly, and data-transform nodes must provide a meaningful visual preview of their own intermediate state, showing active records and their spatial structure, direction, grouping, weight, or type as appropriate. A downstream renderer and `capture_data_port` are additional proof, not substitutes for an inspectable node preview.

For authored 3D, the renderer's native internal camera is the mandatory default; read `knowledge/internal-camera-template.md` before writing or modifying a 3D renderer and follow its manifest, shader, and proof contract exactly. Use an explicit external camera only when multiple separate camera-capable 3D renderer nodes genuinely require one synchronized viewpoint or show-level camera switching, and state that justification before creating it. Never promote camera parameters onto a Scene Group or other top-level surface.

Keep Scene Group control surfaces deliberately small — roughly four to eight high-impact controls, each tested in the open Scene Group Properties (see Scene Groups below).

## Health And Proof

Trust live health, frames, and captures.

Use `sentinel_pipeline action=info` and check `stats.healthy`, `stats.health_reasons`, `stats.statusMessage`, `stats.framesProcessed`, `stats.has_preview_srv`, and output resolution and format.

Use `sentinel_graph action=profile summary=true sort_by=wall_time_ms` for the latest frame breakdown, per-node wall time, rolling `cook_hz`, PipelineStats, link counts, and hotspot reasons. Use rolling cook rate for cadence comparisons because `frames_processed` is a lifetime total. This is a lightweight CPU wall-clock profiler for graph triage, not a deep GPU timestamp profiler.

Proof tools:

- `sentinel_capture action=capture_at`: still review with temporary parameter overrides; waits for compiles, settles, captures, and restores baseline values in one action.
- `sentinel_capture action=proof_bundle`: user-facing creative proof folder with graph JSON, link summary, profile, health, expressions, output capture, window screenshot, and optional before/after diff.
- `sentinel_capture action=sweep_record`: short motion proof across a parameter range. For normal stills or recordings, prefer the capture/record actions exposed by `sentinel_app action=capabilities`.
- `sentinel_capture action=render_sequence` / `render_status` / `render_cancel`: exact fixed-step PNG8 or PNG16 sequence rendering with optional parameter tracks and Conductor time. Follow the `deterministic-rendering` skill for preflight, polling, manifests, restoration, and determinism claims.
- `sentinel_state action=snapshot` / `action=restore`: bracket experiments that mutate many parameters. `sentinel_capture action=checkpoint` bundles a capture with the state snapshot so a look can be recovered exactly.
- `sentinel_vision action=eval_pipeline pipeline_id=<id> preset=render_quality`: one-call AI visual review of a live pipeline. First-time provider setup and key handling: `knowledge/vision-eval.md`. Never ask the user to paste API keys into chat or pass them as tool arguments.

For local diagnostics or support handoff, use `sentinel_app action=bug_report`. Use `submit_bug_report` only when the user explicitly wants to submit the report.

## Features Performance Discipline

Treat the model-free `features` node as performance-sensitive: threshold extremes can produce dense candidate sets and abrupt CPU cost, especially with corners, lines, or edges at large input resolutions. Never sweep several feature tasks blindly or enable every task at once. Start from a measured baseline, enable and tune one task at a time, and run `sentinel_graph action=profile summary=true sort_by=wall_time_ms` before and after material changes. Keep counts bounded with conservative thresholds; if wall time, frame cadence, or UI responsiveness regresses sharply, immediately revert the last setting before continuing downstream.

For quick creative builds, keep the canonical visible chain at 1280x720 or a comparable 720p resolution. When Features is too expensive, insert an explicit analysis proxy branch that downsamples only the Features input (for example to 480x270) while the full-resolution source bypasses it into the renderer; downstream consumers must normalize with that exact analysis size. See `knowledge/tracking-suite.md` and `knowledge/performance-proof.md`.

## Scaled-Pass Coordinate Discipline

When a Module pass writes to a texture buffer with `scale` below `1.0`, do not assume `_Resolution` is the scaled target extent — derive bounds, UVs, and aspect from the actual texture with `GetDimensions`, and prove the effect-producing pass itself rather than trusting a full-resolution overlay. Full discipline: `knowledge/module-pipeline.md`.

## Demand-Driven Module Execution

Static and event-driven Modules should declare `execution: on_dirty` only when
every pass is explicitly `time_dependent: false`, the Module has no video
inputs, and its resolution does not follow a panel or missing video input.
Parameter, structured-data, viewport, camera, resolution, and recompile changes
wake eligible Modules while their last texture and data outputs remain valid.
Keep simulations, feedback, video processors, audio-rate analysis, and any
shader reading `_Time` or `_DeltaTime` on the default `every_frame` policy.
Prove each adoption with near-zero idle `cook_hz`, then one prompt cook and a
changed retained output after a real input change. See
`knowledge/module-pipeline.md` and the `module-authoring` skill.

## Async Compile

Module creates with `project_dir` are atomic, but shader compilation can continue asynchronously.

Use:

- `sentinel_pipeline action=compile_status pipeline_id=<id>`
- `sentinel_pipeline action=compile_check project_dir=<dir>`
- `sentinel_pipeline action=force_reload pipeline_id=<id>`

Do not assume a module is ready until compile status is `ok` and the pipeline health/stats confirm it.

## Control Outputs And Expressions

Tracking and module nodes can publish scalar control outputs under:

```text
/sentinel/pipelines/<id>/control_outputs/<name>
```

To drive another parameter from a control output, use `sentinel_expression action=set` and `ref()`.

Example expression:

```text
0.2 + ref("hand_track/control_outputs/pinch_primary") * 2.0
```

Do not use a plain StateTree `set` to write `=ref(...)`. Use the expression command so the driver is compiled and evaluated every frame. See `knowledge/expressions-and-drivers.md`.

## Audio Reactivity

Audio In is pipeline type `audio` on builds whose live `list_types` response includes it; published builds at or below 0.5.48 may omit it. Use `source_mode=Device` for live WASAPI capture (flow `Loopback` for a playback endpoint, `Microphone` for a recording endpoint) or `source_mode=File` for deterministic paced PCM WAV playback. Audio In publishes three typed data ports — `PCM` (stereo waveform history), `Spectrum` (64-hop linear FFT ring), and `Mel Bands` (64-hop, 138 perceptual bands) — plus scalar `level` and `peak` control outputs that can drive parameters directly.

For beat, onset, and drum-driven work, inspect the Audio Bands architecture in `projects/cloth_lab/modules/cloth_bands` and reimplement the needed analysis in the owning project unless the user explicitly requests a Cloth Lab remix. Use the monotonic `kick_count` / `snare_count` / `hat_count` for per-hit edges and `kick` / `snare` / `hat` for 0-1 envelopes; its per-lane dB thresholds gate internally. Superseded `pulse2_*` and `cryo_pulse` experiments are not part of the curated public module library; do not recreate or build new work on them.

Ring catch-up contracts (`_DataN_Generation`, `_DataN_ValueCount`, `_DataN_HopCapacity`), device hot-plug and endpoint-pinning behavior, capture-versus-content diagnostics (`capture_state`, `signal_present`, `last_packet_age_ms`), virtual-cable routing, wiring recipes, and authoring helpers: `knowledge/audio-reactivity.md`.

## Creative Module Authoring

For a data-driven custom visual, prefer `sentinel_module action=scaffold_from_ports` after creating or inspecting the upstream tracker. It creates a user-writable starter Module, copies the upstream data schema into `data_inputs`, generates HLSL accessors, and includes modern controls. Save and bundle the owning show so its final copy lives under `projects/<project>/modules/<name>/`; do not leave a reusable-looking root module behind.

Use `sentinel_pipeline action=get_data_schemas` before wiring data. The response includes the graph pin name and slot when available, so use that pin name with `sentinel_graph action=add_link`.

Modules can declare viewport behavior in a manifest `viewport:` block: interaction hints, ordered pointer/keyboard/gesture events, `param_gestures`, shader-rendered `controls`, durable `state_buffers`, host-owned selection/picking, and full-bleed `panel: canvas` presentation with `follow_panel` resolution. Availability is version-gated; see `knowledge/module-pipeline.md` and `knowledge/ui-authoring.md`.

## Direct-Manipulation UI Architecture

Do not build authored Canvas panels that merely duplicate Properties sliders. Keep exact numeric shaping, colors, toggles, and ordinary enums in Properties. Use viewport UI for interactions Properties cannot express well: selecting and moving objects, editing points and splines, painting fields, manipulating regions and falloffs, camera/gizmo work, spatial triggers, and performance gestures. Keep telemetry compact and contextual.

Follow Interaction Lab's Style Authority contract for every `point2D` or `xypad`. The host parameter is the single source of truth and remains unmodified in state, data, and control outputs. Declare a plain non-inverted control rectangle; render through the project-local `sui3PadPoint` helper and invert through `sui3PadValue` when needed. Never hand-roll pad coordinate arithmetic, never add `1.0 - value.y` outside that shared helper, and never publish a flipped copy. Before accepting any XY control, drive the real pad at top and bottom and prove that the stored value, published value, readout, and rendered reticle all agree. Reference: `projects/interaction_lab/modules/Style_Authority/`.

Separate the canonical Program renderer from the flexible editor Canvas: the renderer keeps an intentional output such as 1280x720, while a `follow_panel` editor displays an aspect-correct fitted Program preview, remaps pointer coordinates into that stage rectangle, owns durable interaction state, and publishes structured control data. Do not stretch a canonical image to fill the panel. Prove click, drag, selection, clear, and other primary gestures with real viewport input. See `knowledge/ui-authoring.md`.

### Plan And Editor Canvases Are Instruments: Mostly Monochrome

A plan authority's canvas is read, not admired. Style every plan, editor, console and diagnostic canvas from the shared instrument palette in `tools/templates/module-ui/shared/plan_theme.hlsli` — vendor that file into the owning project's `modules/_shared/` and include it from there. It matches Interaction Lab's `sui3` theme, so diagrams and UI stations read as one family: a near-black **neutral** ground (a blue ground reads as "screen", a neutral one reads as "instrument"), a grey value ladder, and a reserved accent.

**Mostly monochrome. Hue only where it carries information.** Keep the ground, panel fills, hairlines, ticks, grids, frames, captions and any ordinal ramp (kind, rank, weight — use `ptRamp`) grey. Spend hue only on things a value genuinely cannot say, and be able to name every use:

1. **Accent** (`PT_ACCENT`, amber) — reserved for the active selection and an established live reading such as a playhead. Never hover, never decoration, never idle chrome.
2. **Alarm** (`PT_ALARM`, red) — the one state meaning the composition is broken. Deliberately not amber so it cannot be confused with a selection.
3. **Identity** (`ptId`) — a small closed unordered set the viewer must tell apart at a glance: which of three walls, which lane, which axis. Four members at most; beyond that use the ramp.
4. **A record's own colour** (`ptSampleColour`) — when the record stores a colour the user chose, showing it is information. Always pass it through the helper: it pulls toward grey and flattens luminance so a saturated record cannot outshine the accent or impersonate it.

Route any real image the canvas previews (a generated plate, a material chip) through `ptInset` — it is data rather than chrome, so it keeps its colour, but at full strength it outranks every readout in the frame.

Both failure modes are real. A saturated diagram competes with the program image it exists to explain; a fully monochrome one turns three identical grey curves into a tangle and throws away colour the records already hold. Judge from a capture, and check that the accent is still the first thing the eye lands on.

## Choreography And Sequencing

For staggered entrances, beat-locked motion, cue-driven shows, and timecoded sequences, create a `conductor` node and use the `sentinel_conductor` tool (`load_sheet`, `bake_sheet`, `status`, `fire`, `jump`, `set_tempo`, `transport`). Cue sheets compile into live expressions plus tweakable sheet parameters. Module motion uses the shared vocabulary in `knowledge/motion-choreography.md` (matching ExprTk functions `spring`, `spring_v`, `stagger`, `anticipate`, `loop_noise`); never hand-roll springs, integrate phase for anything rate-driven, and bundle any HLSL helper with the owning project.

StreamDiff nodes support `hold` (freeze diffusion while staying live) and `render_one`/`render_count` one-shot stills; a `mux` switches variants live with `solo_upstream`; an `atlas` banks aligned stills for 3D scene spawning. To mix whole looks, author each look as a Scene Group containing exactly one `groupoutput` and set a Mux to `source_mode=Groups` (the Scene Switcher, with cuts, `fade_time` crossfades, and per-look OSC triggers). The focused examples under `projects/streamdiff_workflows/` cover one routing pattern each; open one at a time to avoid engine-memory spikes. See `knowledge/streamdiff.md` and `knowledge/scene-system.md`.

## Precise 3D Construction

When a 3D scene is objects with real dimensions and relationships (tucked chairs, seated appliances, clear aisles), author a YAML blueprint and use the `sentinel_blueprint` tool (`validate`, `compile`, `audit`, `solve_report`) instead of hand-placing coordinates. Blueprints resolve relations against an explicit project-specific kind registry, relax under-constrained layouts with warm-start stability, and compile to a generated project-local Module publishing `PNodes` records. Audit sidecars assert measured dimensions against the live distance field. Author relations first, dimensions second. Reference blueprints and registry: `examples/blueprints/`; complete renderer reference: `projects/living_room_sdf/`. See `knowledge/precise-construction.md` and the `procedural-geometry-authoring` skill.

## Imported 3D Meshes

Use `meshsource` for static OBJ, FBX, GLB, or glTF files. Inspect its live data
schemas, then connect the source's single semantic `Mesh` pin directly to a
renderer Module that declares `mesh_inputs`. This keeps vertices, indices, and
submeshes on one atomic graph cable. Leave Mesh Unpack out of the normal path;
use it only when a specialized graph truly needs three separate raw data pins.
See `knowledge/mesh-import.md`.

## Scene Groups

Scene Groups organize graph regions and expose selected controls without flattening the graph. Use `sentinel_graph` Scene Group actions when available in `capabilities`; inspect the live command schema before calling them.

Group presets snapshot every parameter of every contained pipeline plus per-node bypass state automatically, with innermost-wins nested membership and preset-of-presets recall. Use them as the scene-state layer under live switching.

Exposed member parameters render as normal full-width Properties rows with reset, OSC, expressions, range editing, and undo; authored color and XY compounds expose as one complete swatch or pad unit. Curate exposed controls as a compact user-facing interface rather than a mirror of node internals: default to four to eight high-impact controls and verify every one in the open Scene Group Properties panel. Never expose camera ownership, binding, mode, position, orbit, target, FOV, or other camera controls there.

Over MCP, use `sentinel_graph expose_scene_group_parameter`; compound parameters must be addressed by component name, and writes to a group path flow through to the member. Exact call shape and paths: `knowledge/scene-system.md`.

Scene Groups are for control and organization. They do not replace video/data wiring, and they should not be used to hide whether a graph is healthy.

## Node Presets

The `sentinel_preset` tool (`list`, `save`, `recall`, `update`, `delete`, `rename`, `bundle`, `copy_to_library`) provides identity-aware per-node presets in library, project, or bundled scope. Installs at 0.5.29 or newer carry it; otherwise presets remain available through the Properties preset strip. `save` requires an explicit `params` and/or `groups` selection; identity follows the node type and Module project; `recall` returns `applied[]` and `skipped[]` and fails loudly when nothing applies. Verified call shapes: `knowledge/FEATURE-MAP.md`.

## Outputs

Never create a Spout output, NDI output, output node, or external sender as a default finishing step. A request to make a complete graph, composition, scene, project, capture, or proof does not authorize an output node. Create one only when the user explicitly asks for Spout, NDI, an external sender, or an output node. When explicitly requested, use `sentinel_pipeline action=create_output`, wire or route it, and verify that frames are actually moving. Otherwise finish at the final processing or renderer pipeline and use its preview/capture for proof.

OSC receive configuration is available through StateTree. Read or set `/sentinel/osc/receive_port`, then verify the OSC section in `sentinel_app action=diagnostic` or by sending a real OSC message.

## Reference Docs

Start with:

- `knowledge/FEATURE-MAP.md`
- `knowledge/EXAMPLE-MAP.md`
- `knowledge/example-authoring.md`
- `knowledge/reference-build-method.md`
- `knowledge/first-run-engines.md`
- `knowledge/graph-wiring.md`
- `knowledge/expressions-and-drivers.md`
- `knowledge/audio-reactivity.md`
- `knowledge/tracking-suite.md`
- `knowledge/module-pipeline.md`
- `knowledge/mesh-import.md`
- `knowledge/ui-authoring.md`
- `knowledge/video-source.md`
- `knowledge/streamdiff.md`
- `knowledge/scene-system.md`
- `knowledge/motion-choreography.md`
- `knowledge/precise-construction.md`
- `knowledge/gpu-cloth-and-xpbd.md`

Use skills for authoring details:

- `module-authoring`
- `module-ui-authoring`
- `modular-scene-authoring`
- `procedural-geometry-authoring`
- `shader-authoring`
- `mcp-automation`
- `deterministic-rendering`
- `motion-eval`
- `laser-content-authoring`
- `sentinel-bug-report`
- `setup-mcp`

## Practical Smoke Test

1. `sentinel_app action=ping`
2. `sentinel_pipeline action=list_types`
3. Select a meaningful existing camera, video, image, Spout, or NDI source, or author and prove a generator Module first. Never use the built-in Pattern source or diagnostic test imagery.
4. `sentinel_pipeline action=create type=depthestimation name=depth_smoke`
5. If engines are missing, install `auxiliary` through `sentinel_app`.
6. Connect the selected meaningful source or authored generator to `depth_smoke`.
7. `sentinel_graph action=auto_layout`
8. Poll `sentinel_pipeline action=info pipeline_id=depth_smoke` until healthy with frames climbing.

This proves MCP, source creation, engine setup, graph wiring, and pipeline processing without UI clicks.
