# Sentinel Agent Manual

This workspace is the user-writable Sentinel agent workspace. It is seeded by Sentinel and contains:

- `.mcp.json`: connects this agent to the bundled `sentinel-mcp.exe`.
- `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`: identical entry instructions for common agents.
- `.claude/skills/` and `.agents/skills/`: curated user-facing skills.
- `knowledge/`: product reference docs. Start with `knowledge/FEATURE-MAP.md`.
  Use `knowledge/performance-proof.md` when you need to prove or diagnose runtime performance.

Sentinel is a GPU-accelerated live video application for performance and interactive visuals. It combines Spout/NDI/camera/image/pattern/video sources, real-time AI generation, tracking, depth, segmentation, object detection, shader modules, and Spout/NDI output.

## First Rule: Discover Live

Do not guess what this install can create. Ask Sentinel.

Use:

- `sentinel_app action=ping`: verify the app is running.
- `sentinel_pipeline action=list_types`: authoritative build-derived pipeline catalog.
- `sentinel_app action=capabilities`: authoritative IPC command list and accepted args.
- `sentinel_app action=engine_status`: GPU architecture, engine packs, download progress, queue.
- `sentinel_pipeline action=info pipeline_id=<id>`: parameters, outputs, health, and stats.

The shipped docs are a guide, but the live MCP surface is the source of truth for this exact build.

## First-Run Engine Setup

Some pipelines need TensorRT engine packs. A fresh install may have none.

1. Call `sentinel_app action=engine_status`.
2. Pick the needed pack for the user's GPU architecture.
3. Call `sentinel_app action=download_pack pack_id=<pack>` or `sentinel_app action=install_pack pack_id=<pack>`.
4. Poll `engine_status` until the pack is `complete`.
5. Create the pipeline, wire input, and inspect health.

For a quick first proof, install pack `auxiliary`, create `depthestimation`, connect a pattern source, and verify `stats.healthy=true` with `framesProcessed` climbing.

License activation is deliberately manual in the app UI.

## Pipeline Types In DIST Builds

Call `list_types` for the exact current list. A normal DIST build includes:

| Type | Visible | Role |
| --- | --- | --- |
| `streamdiff` | yes | Real-time SDXL image generation. Requires StreamDiff engine packs. |
| `mediapipe` | yes | Composable face and hand tracking, landmarks, gesture control outputs. |
| `facemesh` | hidden | Compatibility alias for old face-only projects. Prefer `mediapipe`. |
| `features` | yes | Model-free blob, corner, and line feature extraction. |
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

Dev builds may expose extra experimental or maintainer-only types. DIST builds intentionally omit them.

## Graph Basics

Use video links for textures and data links for structured buffers.

- `sentinel_pipeline action=create_source`: create pattern, image, video file, Spout, NDI, or capture sources.
- `sentinel_pipeline action=create`: create a pipeline.
- `sentinel_pipeline action=set_input`: connect video texture inputs.
- `sentinel_graph action=add_link`: connect typed data ports.
- `sentinel_graph action=auto_layout`: arrange newly created graphs.
- `sentinel_graph action=layout_neighborhood`: arrange a local area without disturbing a hand-arranged graph.

After creating and wiring nodes, always inspect real runtime state. A successful create call is not proof that the node is processing.

## Health And Proof

Trust live health, frames, and captures.

Use `sentinel_pipeline action=info` and check:

- `stats.healthy`
- `stats.health_reasons`
- `stats.statusMessage`
- `stats.framesProcessed`
- `stats.has_preview_srv`
- output resolution and output format

Use `sentinel_graph action=profile summary=true sort_by=wall_time_ms` to see the latest frame breakdown, per-node wall time, PipelineStats, link counts, and hotspot reasons. This is a lightweight CPU wall-clock profiler for graph triage, not a deep GPU timestamp profiler.

Use `sentinel_capture action=capture_at` for still review with temporary parameter overrides. It can wait for compiles, settle frames, capture, and restore baseline values in one action.

Use `sentinel_capture action=proof_bundle` for user-facing creative proof. It writes a folder with graph JSON, link summary, graph profile, pipeline health, active expressions, output capture, a full Sentinel window screenshot, and an optional before/after image-diff percentage.

Use `sentinel_capture action=sweep_record` when you need a short motion proof across a parameter range. For normal stills or recordings, prefer the capture/record actions exposed by `sentinel_app action=capabilities`.

For local diagnostics or support handoff, use `sentinel_app action=bug_report`. Use `sentinel_app action=submit_bug_report` only when the user explicitly wants to submit the report.

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

## Creative Module Authoring

For a data-driven custom visual, prefer `sentinel_module action=scaffold_from_ports` after creating or inspecting the upstream tracker. It creates a user-writable Module under `modules/<name>/`, copies the upstream data schema into `data_inputs`, generates HLSL accessors, and includes modern controls (`color`, `point2D`, grouped toggles, and `enum` button grids).

Use `sentinel_pipeline action=get_data_schemas` before wiring data. The response includes the graph pin name and slot when available, so use that pin name with `sentinel_graph action=add_link`.

## Scene Groups

Scene Groups organize graph regions and expose selected controls without flattening the graph. Use `sentinel_graph` Scene Group actions when available in `capabilities`; inspect the live command schema before calling them.

Scene Groups are for control and organization. They do not replace video/data wiring, and they should not be used to hide whether a graph is healthy.

## Outputs

Create Spout or NDI outputs with `sentinel_pipeline action=create_output`, then wire or route graph output as needed. Use `sentinel_pipeline info`, capture actions, and output object commands to verify frames are actually moving.

OSC receive configuration is available through StateTree. Read or set `/sentinel/osc/receive_port`, then verify the OSC section in `sentinel_app action=diagnostic` or by sending a real OSC message.

## Workspace Structure & Technique Library

Three homes, kept distinct:

- `scratch/` — throwaway experiments and tinkering. Never committed, never catalogued.
- `projects/<name>/` — structured scene builds (bundled `.sentinel` shows). The workbench; creative work happens here.
- `modules/` — the curated technique library: only harvested, reusable techniques, each documented in `knowledge/technique-catalogue.md`. `modules/_shared/` holds common includes (fonts, os_text).

When recreating a reference or building a complex scene, use the `modular-scene-authoring` skill. It mandates a design-first plan — decide 2D-vs-3D, composite-vs-single-scene, and the right transport per element up front — then builds autonomously. Consult `knowledge/technique-catalogue.md` while planning to reuse what already exists; at session close (`/wrap` or `/end-session`), harvest any novel, reusable technique back into `modules/` and the catalogue so the toolkit compounds over time.

## Reference Docs

Start with:

- `knowledge/FEATURE-MAP.md`
- `knowledge/first-run-engines.md`
- `knowledge/graph-wiring.md`
- `knowledge/expressions-and-drivers.md`
- `knowledge/tracking-suite.md`
- `knowledge/module-pipeline.md`
- `knowledge/technique-catalogue.md`
- `knowledge/video-source.md`
- `knowledge/streamdiff.md`

Use skills for authoring details:

- `modular-scene-authoring`
- `module-authoring`
- `shader-authoring`
- `mcp-automation`
- `motion-eval`
- `laser-content-authoring`
- `sentinel-bug-report`
- `setup-mcp`

## Practical Smoke Test

1. `sentinel_app action=ping`
2. `sentinel_pipeline action=list_types`
3. `sentinel_pipeline action=create_source source_type=pattern name=smoke patternWidth=640 patternHeight=360`
4. `sentinel_pipeline action=create type=depthestimation name=depth_smoke`
5. If engines are missing, install `auxiliary` through `sentinel_app`.
6. `sentinel_pipeline action=set_input pipeline_id=depth_smoke source_id=smoke`
7. `sentinel_graph action=auto_layout`
8. Poll `sentinel_pipeline action=info pipeline_id=depth_smoke` until healthy with frames climbing.

This proves MCP, source creation, engine setup, graph wiring, and pipeline processing without UI clicks.
