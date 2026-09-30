# Sentinel Feature Map

This folder is the shipped agent reference for Sentinel. Start here when a user asks what Sentinel can create, how nodes connect, or how one feature can drive another.

Reusable existing-state creative continuation prompts and the hybrid workflow vocabulary live in `knowledge/creative-exploration-goals.md`.
The mandatory internal-camera default for authored 3D, including the narrow external-camera exception and proof contract, lives in `knowledge/internal-camera-template.md`.
For unstable GPU feedback, exact ABAB flicker, runaway driven fields, and persistent-state corruption, use `knowledge/feedback-simulation-troubleshooting.md`.

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

- `audio`: WASAPI loopback, microphone, or paced WAV capture. Emits PCM, Spectrum, and Mel Bands data plus `level` and `peak` control outputs. See `audio-reactivity.md`.
- `mediapipe`: face and hand tracking in one composable node. Emits landmarks plus gesture control outputs.
- `facemesh`: hidden compatibility alias for old face-only projects.
- `features`: model-free blob, corner, and line feature extraction. Emits data ports and control outputs.
- `detection`: YOLOX-S object detections.
- `personseg`: person segmentation masks.
- `pose`: human pose keypoints.
- `depthestimation`: monocular depth maps.
- `matting`: Background Removal.
- `opticalflow`: NVIDIA hardware optical flow.

Geometry:

- `meshsource`: imports OBJ, FBX, GLB, or glTF geometry and publishes one canonical semantic Mesh output. Route that Mesh pin directly into a Module with `mesh_inputs`. See `mesh-import.md`.
- `meshunpack`: specialized zero-copy adapter exposing the semantic Mesh as separate vertex, index, and submesh pins. Normal imported-mesh renderers should consume the semantic Mesh directly.

Shading and generative tools:

- `conductor`:

- Control outputs: `bpm`, `total_beats`, `beat`, `bar`, `beat_phase`, `bar_phase`, `is_downbeat`, `quantum`, `loop_phase`, per-cue `cue_phase`/`enter_phase`/`exit_phase`, macros `energy`/`tightness`/`spread`, and timecode outputs.
- Data port: `Cue Records` for project-authored timeline or cue visualizations.

`atlas`:

- Data port: `Slot Occupancy` records for scene-spawner modules; readbacks report `occupied_count`, per-slot sequences, and cycle state.

`module`: authored multi-pass shader projects with parameters, typed data ports, control outputs, and optional 3D/raster passes.
- `hlslshader`: single HLSL post-process shader, development builds only. Build new work as a Module.
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
- Preset identity derives from the node type and project-local Module (`module:<module-name>`), so presets follow the Module, not the instance. `list` filters by `pipeline` or `identity`.
- `recall` takes the preset name or id plus the target `pipeline` and returns `applied[]` and `skipped[]`. `loose: true` recalls onto a different node by matching parameter names, and errors loudly (`no preset parameters applied`) when nothing matches.

Bundles:

- `bundlepack`: packs a video plus up to eight keyed data or texture rows into one Bundle cable, for producers that are not Modules.
- `bundlesplit`: splits a Bundle into its video and one data output per key, for consumers that are not Modules. Modules publish and take bundles directly with `bundle_outputs` and `bundle_inputs`. See `bundle-links.md`.

Lasers:

- `laserout`: sends a Scan Signal to one laser projector over Simulate (the default, no hardware), Record, Ether Dream, LaserCube or ShowNET, through scanner protection, Frame Lock and Output Delay. Publishes `Sent Stream`. Real output needs the node's arm and the operator's ARM LASERS master. See `laser-output.md`.
- `lasertrace`: traces pixels into ordered, frame-stable Scan Signal paths for Laser Out. See the `laser-trace-tuning` skill.

Scripted control and controllers (Control nodes):

- `script`: sandboxed Luau on the 240 Hz control clock with manifest Signal and Event pins, parameters, reload that keeps state, and a tracked control window that can draw an operator desk. See the `script-node-authoring` skill and `show-control-desk.md`.
- `midiin`, `midiout`: MIDI input with learn, pickup and relative encoders into Signal and timestamped Event outputs; timestamped MIDI output from Event and Signal inputs.
- `push2display`: drives the Ableton Push 2 or Push 3 display from Script draw lists or a video input. See the `controller-surface-authoring` skill.

Lighting and show control (Control nodes, no pixel output):

- `dmxin`: receives DMX universes over Art-Net or sACN (E1.31) into a typed `DMX` data port, up to 1,024 universes, with a universe grid drawn in the node body. See `lighting-and-show-control.md`.
- `dmxout`: sends a `DMX` data port to fixtures over Art-Net or sACN on its own clock, with keepalive, universe masks, and priority.
- `oscout`: sends expression-driven values to any OSC receiver. Starts empty; one `add_message` action creates a message and binds its `ref()` source.
- `artnetin` and `artnetout`: hidden compatibility ids that create the DMX nodes with `protocol=artnet`.

Utility and output:

- Video File sources: `.mp4` and `.mov` clips decoded to BGRA8 when the codec is supported. Current supported lanes are NVDEC H.264/H.265 plus native HAP/HAP Alpha. AV1, audio, HDR/float output, trim/cue, and reverse playback are not supported in this release.
- `vsr`: RTX Video Super Resolution.
- Spout and NDI output objects send graph results to other applications.

Use `list_types` for the authoritative list in the current build.

## DIST Build Type Table

A normal DIST build includes the following; call `list_types` for the exact current list. Dev builds may expose extra experimental or maintainer-only types, which DIST builds intentionally omit.

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
| `meshsource` | yes | Static OBJ, FBX, GLB, or glTF import with one canonical semantic Mesh output. |
| `meshunpack` | yes | Specialized zero-copy breakout from semantic Mesh to three raw data pins. |
| `module` | yes | Authored multi-pass HLSL projects with parameters, data ports, and control outputs. |
| `shaderproject` | hidden | Compatibility alias for shader project/module workflows. |
| `opticalflow` | yes | NVIDIA hardware optical flow. |
| `vsr` | yes | RTX Video Super Resolution. |
| `conductor` | yes | Musical/timecode clocks, cues, macros, quantized triggers as control outputs. Cue sheets load via `sentinel_conductor`. |
| `mux` | yes | Real-time select-1-of-N video switch; `solo_upstream` auto-holds non-selected StreamDiff variants. In `source_mode=Groups` it becomes the Scene Switcher, collecting Scene Groups wirelessly. |
| `groupoutput` | yes | Scene Group output endpoint: marks a group's final texture, resolution, and fit mode for Scene Switcher collection. |
| `atlas` | yes | Multi-pass still bank (color/segmentation/depth/data columns per captured still) with a self-timing capture cycle. |
| `camera` | yes | Wireless fly/orbit camera rig (control node, no pixel output). Camera-capable modules bind via `camera_ref` or through their Scene Group. |
| `camswitch` | yes | Camera Switcher: cut or quaternion-blend between camera nodes, with per-camera OSC triggers (control node). |
| `dmxin` | yes | DMX In over Art-Net or sACN into a typed `DMX` data port; universe preview in the node body (control node). |
| `dmxout` | yes | DMX Out from a `DMX` data port to fixtures over Art-Net or sACN (control sink). |
| `oscout` | yes | OSC Out with a dynamic, expression-driven message list (control node). |
| `artnetin` | hidden | Compatibility id for `dmxin` with `protocol=artnet`. |
| `artnetout` | hidden | Compatibility id for `dmxout` with `protocol=artnet`. |
| `bundlepack` | yes | Packs a video plus keyed data or texture rows into one Bundle output. |
| `bundlesplit` | yes | Splits a Bundle into its video and one data output per key. |
| `laserout` | yes | Laser Out: Scan Signal to a laser projector over Simulate, Record, Ether Dream, LaserCube or ShowNET, with a `Sent Stream` output (control sink). |
| `lasertrace` | yes | Laser Trace: pixels into ordered Scan Signal paths with a preview. |
| `script` | yes | Sandboxed Luau Script node with Signal and Event pins and a control window (control node). |
| `midiin` | yes | MIDI In: Signal and timestamped Event outputs from a MIDI device (control node). |
| `midiout` | yes | MIDI Out: timestamped MIDI from Event and Signal inputs (control sink). |
| `push2display` | yes | Push Display for Ableton Push 2 and Push 3 (control sink). |

## What Nodes Emit

`audio`:

- Data ports: `PCM`, `Spectrum`, and `Mel Bands`.
- Control outputs: `level` and `peak`.
- Spectrum and Mel Bands are timestamped 64-hop rings for chronological GPU Module consumption.
- Connected consumers receive truthful generation, value-count, and hop-capacity metadata for chronological catch-up.
- Device selections persist by endpoint GUID, with automatic default migration and explicit-device hold-and-retry behavior.
- Read-only diagnostics separate endpoint health, packet freshness, retries, and migrations from recent `signal_present` content.

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
- Sentinel 0.5.59+ `execution: on_dirty` for eligible time-independent Modules with retained outputs. See [Module Pipeline](module-pipeline.md).

`meshsource`:

- Data port: one semantic `Mesh` group carrying canonical vertices, indices, and submeshes.
- Supported files: OBJ, FBX, GLB, and glTF.
- Import controls include uniform scale, Y-up or Z-up conversion, winding inversion, normal recomputation, and manual refresh.

`dmxin`:

- Data port: `DMX`, one 2,048-byte record per universe after a header and eight metadata records; read it in Modules through the `tools/templates/module-includes/dmx_schema_v2.hlsli` helper include.
- Control outputs: `packets_per_second`, `active_universes`, `last_packet_age_ms`, `dropped_packets`, and under sACN `sources_active` and `sequence_errors`.

`dmxout`:

- Data input: `DMX` only. Control outputs: `packets_per_second`, `universes_sent`, `readbacks_dropped`, `send_errors`.

`oscout`:

- Control outputs: `active_slots` (enabled message count), `send_errors`, `over_budget`.
- Actions: `add_message`, `remove_message`, `list_messages` under `/sentinel/pipelines/<id>/actions/`, called through `sentinel_state action=invoke`.

## Node Modes

Every node has an operator mode: Normal, Freeze (hold the last output), or Bypass (type-aware passthrough). Set it with `sentinel_pipeline action=set_mode pipeline_id=<id> mode=freeze|bypass|normal` and read it back as `operator_mode` in `info`. Frozen outputs save with the project and restore byte-identical. See `node-modes.md`.

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

The same driver pattern works with model-free `features` outputs: a project can
drive an authored Module parameter from a path such as
`ref("feature_track/control_outputs/largest_size")`.

## Reference Pages

- [UI Interactions and Shortcuts](ui-interactions.md)
- [Graph Wiring](graph-wiring.md)
- [Expressions And Drivers](expressions-and-drivers.md)
- [Audio Reactivity](audio-reactivity.md)
- [Tracking Suite](tracking-suite.md)
- [Module Pipeline](module-pipeline.md)
- [Authored Module UI](ui-authoring.md)
- [Video Source](video-source.md)
- [StreamDiff](streamdiff.md)
- [Scene System: Hold, Atlas, Mux, Group Presets](scene-system.md)
- [Portable Scene Groups](portable-scene-groups.md)
- [Node Modes: Normal, Freeze, Bypass](node-modes.md)
- [Lighting And Show Control: DMX In, DMX Out, OSC Out](lighting-and-show-control.md)
- [Laser Output: Laser Out, Arming, Sync And First Light](laser-output.md)
- [Laser Mapping](laser-mapping.md)
- [Bundle Links: One Cable For Video Plus Data](bundle-links.md)
- [Show Control Desks](show-control-desk.md)
- [Motion Choreography And Sequencing](motion-choreography.md)
- [Precise Construction: Blueprints And SDF Audit](precise-construction.md)
- [First-Run Engines](first-run-engines.md)
