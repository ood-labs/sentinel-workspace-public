# Sentinel Feature Map

This folder is the shipped agent reference for Sentinel. Start here when a user asks what Sentinel can create, how nodes connect, or how one feature can drive another.

## Discover The Current Build

Use live discovery before assuming a pipeline exists:

- `sentinel_pipeline action=list_types` returns the build-derived pipeline catalog. DIST builds intentionally omit dev-only types.
- `sentinel_pipeline action=info pipeline_id=<id>` reports a node's parameters, data outputs, control outputs, health, preview availability, output format, and stats.
- `sentinel_app action=engine_status` reports GPU architecture, installed packs, active engine downloads, and queued downloads.
- `sentinel_app action=capabilities` reports every raw IPC command and its accepted arguments.

If an engine-backed pipeline is missing engines on a fresh install, call `sentinel_app action=download_pack pack_id=<pack>` or `sentinel_app action=install_pack pack_id=<pack>`, then poll `engine_status` until the pack is `complete`.

## Signal Flow

Sentinel graphs combine four kinds of signal:

- Video textures: sources feed pipeline video inputs; pipeline outputs feed other video inputs or Spout/NDI outputs.
- Data ports: structured buffers such as landmarks, detections, blobs, corners, and module-emitted records. Wire these with graph data links, not `set_input`.
- Control outputs: scalar values published under `/sentinel/pipelines/<id>/control_outputs/<name>`.
- Expressions: per-frame formulas set with `sentinel_expression action=set`; expressions can read control outputs using `ref("node_id/control_outputs/name")`.

Use `sentinel_pipeline set_input` for video inputs. Use `sentinel_graph add_link` for data-port wiring. Use `sentinel_expression action=set` when one node should drive another node's parameter over time.

## Common Workflow

1. Create or select a source: pattern, image, video file, Spout, NDI, or capture device.
2. Create one or more pipelines with `sentinel_pipeline create`.
3. Wire video inputs with `sentinel_pipeline set_input`.
4. Wire data ports with `sentinel_graph add_link` when a pipeline exposes typed data inputs.
5. During visible creative authoring, place, focus, open, and verify each node before creating the next one. Use whole-graph `auto_layout` only for explicit batch work or smoke tests.
6. Inspect each important node with `sentinel_pipeline info`.
7. Check runtime cost with `sentinel_graph profile summary=true sort_by=wall_time_ms`.
8. Capture proof with `sentinel_capture proof_bundle`, `capture_at`, `pipeline`, `source`, or recording actions.

## Pipeline Roles

AI generation:

- `streamdiff`: real-time SDXL image-to-image generation with IP-Adapter and optional ControlNet engines. Supports `hold` (freeze diffusion while live) and `render_one` single-still triggers; variants sharing engine files share loaded engines.

Tracking and analysis:

- `mediapipe`: face and hand tracking in one composable node. Emits landmarks plus gesture control outputs.
- `facemesh`: hidden compatibility alias for old face-only projects.
- `features`: model-free blob, corner, and line feature extraction. Emits data ports and control outputs.
- `detection`: YOLOX-S object detections.
- `personseg`: person segmentation masks.
- `pose`: human pose keypoints.
- `depthestimation`: monocular depth maps.
- `matting`: Background Removal.
- `opticalflow`: NVIDIA hardware optical flow.

Shading and generative tools:

- `conductor`:

- Control outputs: `bpm`, `total_beats`, `beat`, `bar`, `beat_phase`, `bar_phase`, `is_downbeat`, `quantum`, `loop_phase`, per-cue `cue_phase`/`enter_phase`/`exit_phase`, macros `energy`/`tightness`/`spread`, and timecode outputs.
- Data port: `Cue Records` for the `timeline_hud` module.

`atlas`:

- Data port: `Slot Occupancy` records for scene-spawner modules; readbacks report `occupied_count`, per-slot sequences, and cycle state.

`module`: authored multi-pass shader projects with parameters, typed data ports, control outputs, and optional 3D/raster passes.
- `hlslshader`: single HLSL post-process shader.
- `shaderproject`: hidden compatibility alias for module-style shader projects.

Scene system and sequencing:

- `conductor`: musical and timecode clocks, cues, macros, and quantized triggers published as control outputs. Loads cue sheets through `sentinel_conductor`. See `motion-choreography.md`.
- `mux`: real-time select-1-of-N video switch (`selected`), with `solo_upstream` auto-holding non-selected StreamDiff variants. In `source_mode=Groups` it becomes the Scene Switcher, collecting Scene Groups wirelessly with cuts, crossfades, and OSC look triggers. See `scene-system.md`.
- `groupoutput`: Scene Group endpoint node that marks a group's final texture and resolution/fit for Scene Switcher collection. See `scene-system.md`.
- `atlas`: multi-pass still bank collecting aligned color/segmentation/depth/data columns per captured still, with a self-timing capture cycle and a `Slot Occupancy` data pin. See `scene-system.md`.
- `camera`: wireless fly/orbit camera rig (control node). Camera-capable modules bind via `camera_ref` or through their Scene Group. See `scene-system.md`.
- `camswitch`: Camera Switcher cutting or blending between camera nodes, with per-camera OSC triggers. See `scene-system.md`.

Presets: the `sentinel_preset` tool (0.5.29+) saves, recalls, and manages identity-aware per-node presets in library, project, or bundled scope. Verified call shapes:

- `save` REQUIRES an explicit selection: `{"action":"save","pipeline":"<id>","name":"<name>","scope":"library","params":["decay","splat_gain"]}` (params and/or groups; there is no save-everything default).
- Preset identity derives from the node type and module project (`module:click_ripples`), so presets follow the module, not the instance. `list` filters by `pipeline` or `identity`.
- `recall` takes the preset name or id plus the target `pipeline` and returns `applied[]` and `skipped[]`. `loose: true` recalls onto a different node by matching parameter names, and errors loudly (`no preset parameters applied`) when nothing matches.

Utility and output:

- Video File sources: `.mp4` and `.mov` clips decoded to BGRA8 when the codec is supported. Current supported lanes are NVDEC H.264/H.265 plus native HAP/HAP Alpha. AV1, audio, HDR/float output, trim/cue, and reverse playback are not supported in this release.
- `vsr`: RTX Video Super Resolution.
- Spout and NDI output objects send graph results to other applications.

Use `list_types` for the authoritative list in the current build.

## What Nodes Emit

`mediapipe`:

- Data ports: `Face Landmarks`, `Hand Landmarks`.
- Control outputs: `pinch_primary`, `pinch_left`, `pinch_right`, `fist_*`, `open_palm_*`, `point_*`, finger curls, hand position, and index direction.

`features`:

- Data ports: `Blobs`, `Corners`, `Lines`.
- Control outputs include blob count, largest blob position/size, corner count, strongest corner position, line count, dominant angle, and line coverage.

`detection`:

- Data port: `Detections` records with boxes, score, and class data.

`pose`:

- Data port: `Keypoints`, including person index and person track id where available.

`module`:

- User-authored data inputs, data outputs, texture outputs, and control outputs declared by the module manifest.
- Authored viewport controls, events, persistent state, object selection, spline editors, and transform gizmos.
- Sentinel 0.5.32+ full-bleed Canvas panels and optional `follow_panel` render resolution. See [Authored Module UI](ui-authoring.md).

## Driving A Parameter From A Hand Pinch

The correct mechanism is:

1. Create a `mediapipe` node and enable Hands.
2. Create the target shader/module node with a parameter to drive, such as `pinch_drive`.
3. Set an expression on the target parameter using `sentinel_expression action=set`.
4. Reference the MediaPipe control output with `ref()`.

Example MCP command shape:

```json
{
  "action": "set",
  "path": "/sentinel/pipelines/pinch_ripple/parameters/pinch_drive",
  "expression": "ref(\"hand_track/control_outputs/pinch_primary\")"
}
```

The expression itself is:

```text
ref("hand_track/control_outputs/pinch_primary")
```

Do not use a plain StateTree `set` with a string beginning with `=ref(...)`. That only writes a value string and does not activate the expression engine. `sentinel_expression action=set` compiles and registers the per-frame driver.

The shipped example `examples/tracking_ripple.sentinel` uses the same driver pattern with the model-free `features` tracker: `feature_track/control_outputs/largest_size` drives the `Tracking Ripple` module parameter `track_drive` through `ref("feature_track/control_outputs/largest_size")`.

## Reference Pages

- [Graph Wiring](graph-wiring.md)
- [Expressions And Drivers](expressions-and-drivers.md)
- [Tracking Suite](tracking-suite.md)
- [Module Pipeline](module-pipeline.md)
- [Authored Module UI](ui-authoring.md)
- [Video Source](video-source.md)
- [StreamDiff](streamdiff.md)
- [Scene System: Hold, Atlas, Mux, Group Presets](scene-system.md)
- [Motion Choreography And Sequencing](motion-choreography.md)
- [Precise Construction: Blueprints And SDF Audit](precise-construction.md)
- [First-Run Engines](first-run-engines.md)
