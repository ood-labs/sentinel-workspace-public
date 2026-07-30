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

## Default Creative Direction And Planning

When the user does not specify an aesthetic, default to a technical monochrome scientific-instrument look: black field, white and gray geometry, crisp thin strokes, legible measurement or tracking overlays, restrained typography, and one sparingly used warm accent. Prefer hard digital structure, contour lines, cells, quantization, registration marks, and precise HUD composition. Do not default to cyan/magenta/purple gradients, blue glow, soft neon bloom, glassy panels, or vague atmospheric effects unless the user asks for them.

Before an ambitious creative graph, establish a short direction plan covering source semantics, analysis tasks, data-to-visual mappings, motion language, palette, interaction contract, and proof criteria. An explicitly exploratory run may stay loose, but it must still choose a meaningful source and state what each analysis or interaction node is supposed to contribute before building downstream.

Every number or label must derive from real live state and remain attached to what it describes. Every authored interaction must cause an immediate, legible, creatively useful change that is meaningfully better than an ordinary Properties control. Do not add stage drags, momentary buttons, fake telemetry, or decorative controls merely to make a composition appear interactive; remove controls that prove weak, redundant, or unclear.

## Sentinel Launch Safety

Sentinel must run in the active interactive Windows desktop. Never launch `sentinel.exe` from Windows Session 0, a service, SSH background execution, or any headless or non-interactive context. Check the agent process session ID before every launch. Reuse a user-launched Sentinel instance in the active desktop session, or use an explicitly interactive `/IT` scheduled task and verify the resulting process session ID before testing. MCP and raw localhost IPC can connect across sessions after the interactive app is running.

## First-Run Engine Setup

Some pipelines need TensorRT engine packs. A fresh install may have none.

1. Call `sentinel_app action=engine_status`.
2. Pick the needed pack for the user's GPU architecture.
3. Call `sentinel_app action=download_pack pack_id=<pack>` or `sentinel_app action=install_pack pack_id=<pack>`.
4. Poll `engine_status` until the pack is `complete`.
5. Create the pipeline, wire input, and inspect health.

For a quick first proof, install pack `auxiliary`, create `depthestimation`, connect a meaningful live/user source or an authored generator Module, and verify `stats.healthy=true` with `framesProcessed` climbing. Never use the built-in Pattern source or diagnostic test imagery for this proof.

License activation is deliberately manual in the app UI.

## Pipeline Types In DIST Builds

Call `list_types` for the exact current list. A normal DIST build includes:

| Type | Visible | Role |
| --- | --- | --- |
| `streamdiff` | yes | Real-time SDXL image generation. Requires StreamDiff engine packs. |
| `mediapipe` | yes | Composable face and hand tracking, landmarks, gesture control outputs. |
| `facemesh` | hidden | Compatibility alias for old face-only projects. Prefer `mediapipe`. |
| `features` | yes | Model-free blob, corner, and line feature extraction. |
| `audio` | yes | Audio In for WASAPI loopback, microphone, or paced WAV sources, with PCM, Spectrum, and Mel Bands data outputs. |
| `detection` | yes | YOLOX-S object detections. Requires `auxiliary-detection`. |
| `personseg` | yes | Person segmentation masks. Requires personseg engines. |
| `pose` | yes | Human pose keypoints. Requires pose engines. |
| `depthestimation` | yes | Monocular depth maps. Pack `auxiliary` is the small first-run proof pack. |
| `matting` | yes | Background Removal. |
| `module` | yes | Authored multi-pass HLSL projects with parameters, data ports, and control outputs. |
| `hlslshader` | yes | Single HLSL post-process shader. |
| `shaderproject` | hidden | Compatibility alias for shader project/module workflows. |
| `opticalflow` | yes | NVIDIA hardware optical flow. |
| `vsr` | yes | RTX Video Super Resolution. |
| `conductor` | yes | Musical/timecode clocks, cues, macros, quantized triggers as control outputs. Cue sheets load via `sentinel_conductor`. |
| `mux` | yes | Real-time select-1-of-N video switch; `solo_upstream` auto-holds non-selected StreamDiff variants. In `source_mode=Groups` it becomes the Scene Switcher, collecting Scene Groups wirelessly. |
| `groupoutput` | yes | Scene Group output endpoint: marks a group's final texture, resolution, and fit mode for Scene Switcher collection. |
| `atlas` | yes | Multi-pass still bank (color/segmentation/depth/data columns per captured still) with a self-timing capture cycle. |
| `camera` | yes | Wireless fly/orbit camera rig (control node, no pixel output). Camera-capable modules bind via `camera_ref` or through their Scene Group. |
| `camswitch` | yes | Camera Switcher: cut or quaternion-blend between camera nodes, with per-camera OSC triggers (control node). |

Dev builds may expose extra experimental or maintainer-only types. DIST builds intentionally omit them.

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

Do not use whole-graph `auto_layout` to repair a pile of bulk-created nodes. Preserve the graph's evolving layout with `place_relative`, explicit geometry, or `layout_neighborhood`. A whole-graph `auto_layout` is appropriate when the user explicitly requests it or when later topology surgery inserts, removes, or replaces nodes and the graph no longer reads in signal-flow order. Treat that as a layout-only checkpoint: inspect the graph first, run `auto_layout`, verify the new order, then refocus and reopen the active node. Never use it to hide bulk creation.

Generator, plan, layout, assembly, and data-transform nodes must provide a meaningful visual preview of their own intermediate state. Show active records and their spatial structure, direction, grouping, weight, or type as appropriate. A downstream renderer and `capture_data_port` are additional proof, not substitutes for an inspectable node preview.

For authored 3D, the renderer's native internal camera is the mandatory default; read `knowledge/internal-camera-template.md` before writing or modifying a 3D renderer. A normal 3D Module must declare `features: [camera]` and `viewport.interactions: [camera]`, keep `camera_ref` empty, construct every camera-dependent pass from the injected matrices and `_CameraPos`, save Fly as the default, and prove real viewport movement in the open renderer preview. Never create a `camera`/`camswitch` for a single renderer, multiple passes inside one Module, or a renderer plus post-processing, and never invent a shader-local orbit or parallel ray equation. Use an explicit external camera only when multiple separate camera-capable 3D renderer nodes genuinely require one synchronized viewpoint or show-level camera switching, and state that justification before creating it. Never promote camera parameters onto a Scene Group or other top-level surface.

Keep Scene Group control surfaces deliberately small. Start with roughly four to eight high-impact creative or construction controls, counting a color or XY compound as one control. Do not mirror internal implementation parameters. After exposure, open the Scene Group Properties and test every exposed control; remove controls that are redundant, inactive, confusing, or too low-level.

## Health And Proof

Trust live health, frames, and captures.

Use `sentinel_pipeline action=info` and check:

- `stats.healthy`
- `stats.health_reasons`
- `stats.statusMessage`
- `stats.framesProcessed`
- `stats.has_preview_srv`
- output resolution and output format

Use `sentinel_graph action=profile summary=true sort_by=wall_time_ms` to see the latest frame breakdown, per-node wall time, rolling `cook_hz` / `cooks_in_window` / `cook_window_ms`, PipelineStats, link counts, and hotspot reasons. Use rolling cook rate for cadence comparisons because `frames_processed` is a lifetime total. This is a lightweight CPU wall-clock profiler for graph triage, not a deep GPU timestamp profiler.

Use `sentinel_capture action=capture_at` for still review with temporary parameter overrides. It can wait for compiles, settle frames, capture, and restore baseline values in one action.

Use `sentinel_capture action=proof_bundle` for user-facing creative proof. It writes a folder with graph JSON, link summary, graph profile, pipeline health, active expressions, output capture, a full Sentinel window screenshot, and an optional before/after image-diff percentage.

Use `sentinel_capture action=sweep_record` when you need a short motion proof across a parameter range. For normal stills or recordings, prefer the capture/record actions exposed by `sentinel_app action=capabilities`.

Use `sentinel_state action=snapshot` / `action=restore` to bracket experiments that mutate many parameters, and `sentinel_capture action=checkpoint` to bundle a capture with the state snapshot so a look can be recovered exactly.

Use `sentinel_vision action=eval_pipeline pipeline_id=<id> preset=render_quality` for one-call AI visual review of a live pipeline. It captures `<workspace>/captures/vision_<timestamp>/output.png`, evaluates it through the configured OpenAI-compatible provider, and returns `_meta.captured_png`. For first-time setup, run `sentinel_vision action=status`, open the returned `config_path`, paste the provider key into the selected provider profile's `api_key` field, then rerun `status` until `key_present` and `key_ok` are true. Environment setup is also supported with `SENTINEL_VISION_API_KEY` or `OPENROUTER_API_KEY` set before launching Codex/MCP. Never ask the user to paste API keys into chat or pass them as tool arguments; `sentinel_vision action=configure` only edits provider metadata. See `knowledge/vision-eval.md` for the full setup flow.

For local diagnostics or support handoff, use `sentinel_app action=bug_report`. Use `sentinel_app action=submit_bug_report` only when the user explicitly wants to submit the report.

## Features Performance Discipline

Treat the model-free `features` node as performance-sensitive. Threshold extremes can produce dense candidate sets and abrupt CPU cost, especially with corners, lines, or edges at large input resolutions. Never sweep several feature tasks blindly or enable every task at once.

Start from a measured baseline, enable and tune one task at a time, and run `sentinel_graph action=profile summary=true sort_by=wall_time_ms` before and after material changes. Keep counts bounded and use conservative thresholds: avoid very low corner quality with small minimum distance, permissive line/edge thresholds, short minimum line lengths, and blob settings that fragment most of the frame. If wall time, frame cadence, or UI responsiveness regresses sharply, immediately revert the last setting before continuing downstream.

For quick creative builds, keep the canonical visible chain at 1280x720 or a comparable 720p resolution. When Features is too expensive, insert an explicit analysis proxy branch that downsamples only the Features input (for example to 480x270) while the full-resolution source bypasses it into the renderer. The Features preview and coordinates then use the analysis resolution; downstream consumers must normalize with that exact size. This is an external workaround until the live node advertises a verified internal analysis scale. Preview the real Features node while tuning, inspect output counts and schemas, and require the agreed performance target before adding another node. See `knowledge/tracking-suite.md` and `knowledge/performance-proof.md`.

## Scaled-Pass Coordinate Discipline

When a Module pass writes to a texture buffer with `scale` below `1.0`, do not assume `_Resolution` is the scaled target extent. Derive simulation bounds, UVs, and aspect from the actual input or feedback texture with `GetDimensions`, or from another verified pass-local extent. Using the root pipeline resolution for a half-resolution field can multiply normalized positions and make only one corner of the control domain effective.

Prove the effect-producing pass itself. A later full-resolution overlay can draw a marker at the correct data coordinate while an upstream scaled simulation responds somewhere else. Capture the raw field or intermediate output and test records on both sides of `0.5` on each axis before declaring producer/consumer coordinates aligned.

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

Audio In is pipeline type `audio` on builds whose live `list_types` response includes it. Published builds at or below 0.5.48 may omit this feature, so discover the running catalog before creating the node.

Use `source_mode=Device` for live WASAPI capture or `source_mode=File` for deterministic paced PCM WAV playback. Device flow `Loopback` captures a Windows playback endpoint, while `Microphone` captures a recording endpoint. For a virtual audio cable, route the producing application's playback into the cable and select the corresponding endpoint under the appropriate flow.

For beat, onset, and drum-driven work, use the project-local Audio Bands implementation
in `projects/cloth_lab/modules/cloth_bands` as the maintained reference: wire Audio
In's `Spectrum` port into it, then drive parameters from its control outputs. Bundle
an owning-project copy instead of linking a new show to another project's files. Use
the monotonic `kick_count` / `snare_count` /
`hat_count` for per-hit edges and `kick` / `snare` / `hat` for 0-1 envelopes; its
per-lane dB thresholds gate internally, so the counters need no extra signal gate.
`Threshold Mode` defaults to Fixed. Superseded `pulse2_*` and `cryo_pulse`
experiments are not part of the curated public module library; do not recreate
or build new work on them. Worked example: `projects/cloth_lab/`.

Audio In publishes three typed data ports:

- `PCM`: circular stereo waveform history for oscilloscopes and time-domain processing.
- `Spectrum`: a 64-hop ring of linear FFT magnitudes for exact frequency-bin analysis.
- `Mel Bands`: a 64-hop ring of 138 perceptual bands for musical analysis and onset detection.

Scalar `level` and `peak` control outputs can drive parameters directly. Stock audio Modules provide kick, snare, hi-hat, band-energy, count, spectrum-bar, oscilloscope, and starter-reactive behavior.

The WASAPI capture, format conversion, FFT, Mel aggregation, timestamps, and ring maintenance run on CPU threads. D3D11 structured buffers carry the completed rings to GPU HLSL Modules for detection and rendering.

Default endpoint selections migrate when the Windows default changes. Explicit endpoint selections stay pinned by device GUID. If a pinned device disappears, Audio In publishes timestamped silence and retries that endpoint until it returns. Use `Rescan Devices` to refresh the dropdown after adding hardware; an unrelated new device never replaces the active selection automatically.

Connected Module data inputs receive `_DataN_Generation`, `_DataN_ValueCount`,
and `_DataN_HopCapacity`. Use them for chronological ring catch-up. Spectrum
and Mel Bands have no standalone header record, so element zero cannot serve as
the latest-generation source.

Audio In diagnostics separate capture health from content presence. Inspect
`capture_state`, `endpoint_active`, `last_packet_age_ms`, retry and migration
counters, `signal_present`, and `silence_seconds`. Adaptive onset detectors
also need a signal-presence gate so steady noise cannot accumulate confident
false triggers.

See `knowledge/audio-reactivity.md` for wiring recipes, frozen data contracts, hot-plug behavior, virtual-cable routing, authoring helpers, and proof guidance.

## Creative Module Authoring

For a data-driven custom visual, prefer `sentinel_module action=scaffold_from_ports` after creating or inspecting the upstream tracker. It creates a user-writable starter Module, copies the upstream data schema into `data_inputs`, generates HLSL accessors, and includes modern controls (`color`, `point2D`, grouped toggles, and `enum` button grids). Save and bundle the owning show so its final copy lives under `projects/<project>/modules/<name>/`; do not leave a reusable-looking root module behind.

Use `sentinel_pipeline action=get_data_schemas` before wiring data. The response includes the graph pin name and slot when available, so use that pin name with `sentinel_graph action=add_link`.

Modules can declare viewport behavior in a manifest `viewport:` block: a `hint` string plus `interactions` from `mouse`, `pan_zoom`, `camera`, `events`, and `selection`. Declaring `events` with a `viewport.input` interest list and `bindings` help entries delivers ordered pointer/keyboard/gesture events to the module's shaders (installs at 0.5.30 or newer). Installs at 0.5.31 or newer also support `param_gestures`, shader-rendered `controls`, durable `state_buffers`, and host-owned object selection/picking through `sentinel_viewport`. Installs at 0.5.32 or newer support `panel: { mode: canvas, output: UI, resolution: follow_panel }` for full-bleed authored panels whose real render size follows the dock content. See `knowledge/module-pipeline.md` and `knowledge/ui-authoring.md`.

## Direct-Manipulation UI Architecture

Do not build authored Canvas panels that merely duplicate Properties sliders. Keep exact numeric shaping, colors, toggles, and ordinary enums in Properties. Use viewport UI for interactions Properties cannot express well: selecting and moving objects, editing points and splines, painting fields, manipulating regions and falloffs, camera/gizmo work, spatial triggers, and performance gestures. Keep telemetry compact and contextual.

Separate the canonical Program renderer from the flexible editor Canvas. The renderer keeps an intentional output such as 1280x720. A `follow_panel` editor displays an aspect-correct fitted or cropped Program preview, remaps pointer coordinates into that stage rectangle, owns durable interaction state, and publishes structured control data for the renderer. Do not make the final renderer inherit an arbitrary dock aspect and do not stretch a canonical image to fill the panel. Use unused panel space for contextual tools or gutters. Prove click, drag, selection, clear, and other primary gestures with real viewport input. See `knowledge/ui-authoring.md`.

## Choreography And Sequencing

For staggered entrances, beat-locked motion, cue-driven shows, and timecoded sequences, create a `conductor` node and use the `sentinel_conductor` tool (`load_sheet`, `bake_sheet`, `status`, `fire`, `jump`, `set_tempo`, `transport`). Cue sheets compile into live expressions plus tweakable sheet parameters; `bake_sheet` writes live tweaks back to the YAML. Module motion uses the shared vocabulary described in `knowledge/motion-choreography.md` (matching ExprTk functions `spring`, `spring_v`, `stagger`, `anticipate`, `loop_noise`); never hand-roll springs, integrate phase for anything rate-driven, and bundle any HLSL helper with the owning project.

StreamDiff nodes support `hold` (freeze diffusion while staying live) and `render_one`/`render_count` one-shot stills; a `mux` node switches variants live and its `solo_upstream` keeps only the visible variant diffusing; an `atlas` node banks aligned stills for 3D scene spawning. The focused examples under `projects/streamdiff_workflows/` cover feedback zoom, depth parallax, direct Mux switching, video depth conditioning, and procedural warp maps; open one at a time to avoid unnecessary engine-memory spikes. See `knowledge/streamdiff.md` and `knowledge/scene-system.md`.

To mix whole looks instead of single streams, author each look as a Scene Group containing exactly one `groupoutput` node and set a Mux to `source_mode=Groups`. The switcher collects the groups wirelessly, fully freezes non-selected looks, and offers hard cuts or `fade_time` crossfades plus one `select/<slug>` OSC trigger per look; `allowed_groups` filters the collection and accepts a string `ref()` expression. Only when multiple separate camera-capable 3D renderer nodes genuinely require one synchronized viewpoint or show-level switching should `camera` nodes own a shared fly/orbit rig through `camera_ref` (or their containing Scene Group), with `camswitch` cutting or blending between those justified external cameras. See `knowledge/scene-system.md`.

## Precise 3D Construction

When a 3D scene is objects with real dimensions and relationships (tucked chairs, seated appliances, clear aisles), author a YAML blueprint and use the `sentinel_blueprint` tool (`validate`, `compile`, `audit`, `solve_report`) instead of hand-placing coordinates. Blueprints resolve relations against an explicit project-specific kind registry, relax under-constrained layouts with warm-start stability, and compile to a generated project-local Module publishing `PNodes` records. Audit sidecars assert measured dimensions against the live distance field. Author relations first, dimensions second. Reference blueprints and registry: `examples/blueprints/`; complete renderer reference: `projects/living_room_sdf/`. See `knowledge/precise-construction.md` and the `procedural-geometry-authoring` skill.

## Scene Groups

Scene Groups organize graph regions and expose selected controls without flattening the graph. Use `sentinel_graph` Scene Group actions when available in `capabilities`; inspect the live command schema before calling them.

Group presets snapshot every parameter of every contained pipeline plus per-node bypass state automatically, with innermost-wins nested membership and preset-of-presets recall (an outer preset can pick each inner group's preset then apply overrides). Use them as the scene-state layer under live switching.

Scene Groups can also expose selected member parameters as first-class group controls. Exposed parameters keep their authored defaults, enums, and source sections, render as normal full-width Properties rows with reset, OSC, expressions, range editing, and undo, and authored color and XY compounds expose as one complete swatch or pad unit.

Curate exposed controls as a compact user-facing interface rather than a mirror of node internals. Default to four to eight high-impact controls and verify every one in the open Scene Group Properties panel. Never expose camera ownership, binding, mode, position, orbit, target, FOV, or other camera controls there; keep camera operation on the actual owning renderer preview or `camera` node.

Over MCP, use `sentinel_graph expose_scene_group_parameter` with the group's annotation `entity_id`, the member `pipeline_id`, and a `param_name`. Compound parameters live in StateTree as flattened components (`main_color_r/_g/_b`, `center_x/_y`); pass a COMPONENT name (the compound base name errors with parameter-not-found) and the whole compound promotes at once, returning every exposed path under `/sentinel/groups/<id>/parameters/`. Writes to a group path flow to the member parameter and back.

Scene Groups are for control and organization. They do not replace video/data wiring, and they should not be used to hide whether a graph is healthy.

## Node Presets

The `sentinel_preset` tool (`list`, `save`, `recall`, `update`, `delete`, `rename`, `bundle`, `copy_to_library`) provides identity-aware per-node presets in library, project, or bundled scope, with grouped compound-safe parameter selection and strict or loose Recall Onto compatible nodes. Installs at 0.5.29 or newer carry it; if the tool is absent from the live tools list, presets remain available through the Properties preset strip in the UI.

`save` requires an explicit `params` array and/or `groups` selection; there is no save-everything default. Identity derives from the node type and module project (for example `module:click_ripples`), so presets follow the module across instances and projects. `recall` returns `applied[]` and `skipped[]` and fails loudly when nothing applies. See `knowledge/FEATURE-MAP.md` for verified call shapes.

## Outputs

Create Spout or NDI outputs with `sentinel_pipeline action=create_output`, then wire or route graph output as needed. Use `sentinel_pipeline info`, capture actions, and output object commands to verify frames are actually moving.

OSC receive configuration is available through StateTree. Read or set `/sentinel/osc/receive_port`, then verify the OSC section in `sentinel_app action=diagnostic` or by sending a real OSC message.

## Reference Docs

Start with:

- `knowledge/FEATURE-MAP.md`
- `knowledge/first-run-engines.md`
- `knowledge/graph-wiring.md`
- `knowledge/expressions-and-drivers.md`
- `knowledge/audio-reactivity.md`
- `knowledge/tracking-suite.md`
- `knowledge/module-pipeline.md`
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
