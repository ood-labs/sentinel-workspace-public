---
name: mcp-automation
description: Control Sentinel via MCP automation and IPC. Use when testing UI, automating pipelines, writing automation scripts, debugging IPC communication, setting up test environments, or working with the ZMQ automation bridge.
---

# MCP Automation

Sentinel includes an optional automation layer that enables AI agents (like Claude Code) to control the application via the Model Context Protocol (MCP).

## Architecture

```
┌─────────────┐     ZMQ (5555)     ┌─────────────┐
│  MCP Server │ ◄────────────────► │  Sentinel   │
│  (Rust)     │                    │  (C++)      │
└─────────────┘                    └─────────────┘
      ▲                                   │
      │ stdio                             │ Renders UI
      ▼                                   ▼
┌─────────────┐                    ┌─────────────┐
│ Claude Code │                    │   Screen    │
└─────────────┘                    └─────────────┘
```

## Building with Automation (dev only)

Distribution builds always have automation enabled, so skip this section on the installed Sentinel. For dev builds:

```bash
# With automation enabled (for development/testing)
cmake .. -DENABLE_AUTOMATION=ON
cmake --build . --config Release
```

When `ENABLE_AUTOMATION=ON`:
- ZeroMQ listener starts on port 5555
- ItemTracker captures UI element positions each frame
- Pending value pattern enables background state manipulation

## Launching Sentinel

Sentinel must run in the active interactive Windows desktop session. Never launch `sentinel.exe` from Session 0, a service, SSH background execution, or any headless or non-interactive context. A direct launch from those contexts inherits the wrong session and cannot create the DXGI swap chain.

Before every agent-managed launch, inspect the agent session and any existing Sentinel process:

```powershell
$agentSession = [Diagnostics.Process]::GetCurrentProcess().SessionId
Get-Process -Name sentinel -ErrorAction SilentlyContinue |
    Select-Object Id, SessionId, Path
```

- If the agent is already in the active interactive session, launch from the install directory or dev build directory with `Start-Process`.
- If the agent is in Session 0 or another non-interactive session, reuse a user-launched Sentinel instance or create an explicitly interactive scheduled task with `schtasks /Create ... /IT`, run it, and verify the resulting `sentinel.exe` session ID before testing.
- The MCP `launch` action and ordinary background process creation are forbidden from a non-interactive agent session.

Interactive-session examples:

```powershell
# Distribution install (default)
Start-Process 'C:\Program Files\OODLabs\Sentinel\sentinel.exe'

# Dev build
Start-Process '<repo_root>\build\bin\Release\sentinel.exe'
```

Wait 3-5 seconds for the app to initialize before sending IPC commands.

## MCP Tools (15 multi-action tools)

All tools use an `action` parameter. Examples:

```
# Test connectivity
sentinel_app action="ping"

# Get the full state tree (for discovery)
sentinel_state action="tree" path="/sentinel"

# Create a source and a Module, then wire them
sentinel_pipeline action="create_source" source_type="video" name="Clip" video_path="C:/media/intro_hap.mov"
sentinel_pipeline action="create" type="module" name="Glow" project_dir="C:/shows/demo/modules/glow"
sentinel_pipeline action="compile_status" pipeline_id="Glow"
sentinel_graph action="add_link" from_entity="Clip" to_entity="Glow" to_slot=0

# Read/write state values
sentinel_state action="get" path="/sentinel/pipelines/Glow/parameters/amount"
sentinel_state action="set" path="/sentinel/pipelines/Glow/parameters/amount" value=0.5

# Invoke actions (action arguments go in args)
sentinel_state action="invoke" path="/sentinel/sources/Clip/actions/preroll" args={"time": 0}

# Query pipelines
sentinel_pipeline action="list"
sentinel_pipeline action="info" pipeline_id="Glow"
```

## Core Agent Workflow Patterns

- **Visible graph authoring**: unless the user explicitly requests batch work, author and create exactly one node at a time. Immediately place it relative to the graph, wire it, verify it, call `sentinel_graph focus`, and call `sentinel_pipeline open_window` before starting the next node. Never pre-author the planned graph, parallel-create its nodes, or rely on whole-graph `auto_layout` to repair a pile.
- **Discovery**: `sentinel_app action="capabilities"` returns every IPC command with its accepted args. Unknown args are rejected with the expected list, so typos fail loudly.
- **Honest health**: `list`/`info` report a bridge-computed `healthy` with `health_reasons[]` naming the exact cause (no frames, compile error, unresolved project_dir, zombie) plus a live `statusMessage`. Trust these over raw `loaded_*` flags.
- **One-call module create**: `sentinel_pipeline create type="module" name="X" project_dir="..."` is atomic. A manifest error fails the create at once; otherwise the response carries `compile {state: "compiling", job_id, progress, budget_ms}` and the shaders compile in the background. Poll `compile_status` until `state` is `ok`, when its `params[]` lists the registered parameters, or `error` with `file`, `line` and `message`.
- **Async compiles**: module shaders compile in a separate worker process, so a compiler crash fails that one compile instead of the app. Poll `compile_status` for progress, timing and structured errors; `sentinel_app status` shows `busy` + `compiling[]` after a project load; `force_reload` recovers from a compile-error state; `compile_check` validates a project dir without creating a node (pass the `job_id` it returns as `compile_job_id` to `compile_check_status`). A compile is marked slow after two minutes and overdue past its budget (five minutes by default) but keeps running; `compile_extend` raises the budget and `compile_abandon` (`confirm: true` plus a `reason`) ignores the eventual result.
- **Batch writes**: `sentinel_state set_many` applies many parameter writes in one call with per-path results.
- **One-call review stills**: `sentinel_capture capture_at` applies overrides, waits for compiles, settles, captures, and restores. Use it instead of hand-rolling set / sleep / capture / set-back chains.
- **Deterministic sequence renders**: `sentinel_capture render_sequence` starts an exact fixed-step PNG job; poll `render_status` and use `render_cancel` when needed. Follow the `deterministic-rendering` skill for tracks, Conductor coupling, manifest checks, and determinism claims.
- **Authored panel proof**: for a Module UI, read `sentinel_pipeline info.panel` and verify declared/effective mode, named output, resolution mode, content size, render size, recreation counts, and deferred-resource count. Canvas/follow-panel behavior ships in 0.5.32+. An immediate capture concurrent with a parameter write is not sufficient proof; require a settled frame plus live interaction/readback.
- **Runtime proof**: `sentinel_graph profile` reports frame buckets, per-node wall time, rolling `cook_hz` / `cooks_in_window` / `cook_window_ms`, graph link counts, PipelineStats, and hotspot reasons. Use cook rate when comparing nodes created at different times; lifetime `frames_processed` totals are not cadence measurements. `sentinel_capture proof_bundle` includes `graph_profile.json` plus a Performance section.
- **Project safety**: `load_project`/`new_project` refuse over unsaved changes unless `confirm: true`; `import_project` merges another .sentinel into the live project with id remap.

## Python IPC Client (dev only)

For Python automation scripts in the dev repo, use the IPCClient at `src/ipc/client.py`. Distribution users should drive Sentinel via the MCP tools above (no Python source ships in the installer).

## Pipeline Type IDs

Use these exact strings with `sentinel_pipeline action="create"`. Run `sentinel_pipeline action="list_types"` first: it is the authoritative catalog for the installed build, including engine-pack requirements (`requires_engine_pack`) and hidden aliases. A release build lists 37 types.

Authoring and routing:
- `"module"`: Module (multi-pass YAML projects with typed data ports; every authored visual)
- `"mux"`: Mux (N-way wired input switcher with crossfades, or wireless Scene Group collector)
- `"groupoutput"`: Group Output (Scene Group endpoint for the Scene Switcher)
- `"bundlepack"` / `"bundlesplit"`: pack a video plus keyed data and texture channels into one Bundle cable, and split it again
- `"camera"`, `"camswitch"`: Camera (wireless fly/orbit rig) and Camera Switcher (cut or blend between cameras); control nodes, no pixel output
- `"conductor"`: Conductor (beat/timecode transport, cues, macros; no pixel output)
- `"vsr"`: RTX Video Super Resolution

Generation and analysis (engine packs):
- `"streamdiff"`: StreamDiffusion real-time generation
- `"mediapipe"`: MediaPipe composable tracking (face, hands, gestures)
- `"pose"`: Pose Estimation (OpenPose-18 for ControlNet)
- `"detection"`: Detection (YOLOX)
- `"personseg"`: Person Segmentation (RF-DETR-Seg)
- `"matting"`: Background Removal (BiRefNet / RVM)
- `"depthestimation"`: Depth Anything V2, or FlashDepth from a user-supplied engine
- `"opticalflow"`: Optical Flow (NVOF hardware; no pack needed)
- `"features"`: Geometric Features (model-free Blob/Corner/Line/Edge tracking; no pack needed)

Control, data and show I/O:
- `"audio"`: Audio In (WASAPI loopback, microphone, or paced WAV; PCM, Spectrum and Mel Bands data outputs)
- `"midiin"`, `"midiout"`: MIDI In and MIDI Out on the control clock (`list_devices` names the ports)
- `"script"`: Script (sandboxed Luau with Signal and Event pins, a control window and controller surface bindings)
- `"push2display"`: Push Display for Ableton Push 2 and Push 3 screens
- `"dmxin"`, `"dmxout"`: DMX In and DMX Out (Art-Net or sACN, typed `DMX` data port)
- `"oscout"`: OSC Out (dynamic expression-driven messages)
- `"laserout"`, `"lasertrace"`: Laser Out (Scan Signal to a projector, `Sent Stream` back) and Laser Trace (pixels to ordered laser paths); see the laser skills. `"lasermapping"` is an experimental camera-calibration node; map lasers with the Module chain in `knowledge/laser-mapping.md`
- `"fixturerig"`: Fixture Rig (one GDTF lighting rig, imported from MVR or built in Sentinel; see `knowledge/fixture-import.md`)
- `"meshsource"`, `"meshunpack"`: Mesh Source (OBJ/FBX/GLB import; pass `file_path` on create) and Mesh Unpack

Hidden compatibility ids load old projects and need no new work: `"artnetin"` / `"artnetout"` (DMX nodes), `"atlas"`, `"facemesh"` (use `mediapipe`), `"shaderproject"` (use `module`). Development builds add `hlslshader`, `fluxklein`, `persontrack`, `colorcorrect`, `torchv2v` and test probes; release builds do not have them, so never build shipped work on them.

Use these ids, never display names like "Background Removal".

## Source Types

- `"pattern"`: internal test pattern (auto-connects)
- `"image"`: static image file (`image_path`, `image_fit_mode`)
- `"video"`: video file (`video_path`; HAP, HAP Q, H.264, H.265; see `knowledge/video-source.md` for playback, preroll and clip sequencing)
- `"spout"`: Spout texture sharing (requires `sender_name`)
- `"ndi"`: NDI video stream (requires `sender_name`)
- `"capture"`: webcam or capture card

`set_source_type` rebuilds an existing source as another type and keeps its id, so links and references survive.

## MCP Tools Reference

### `sentinel_app`: Application lifecycle
| Action | Description |
|--------|-------------|
| `ping` | Test connectivity |
| `launch` | Launch Sentinel only from the confirmed active interactive desktop session; forbidden from Session 0 or any headless context |
| `kill` | Terminate app. On 0.6.11 and newer, without `pid` it takes the most recent launch still running |
| `status` | Check running/crashed; also `busy`, `compiling[]`, `dirty`, `window_visible` |
| `logs` | Get stdout/stderr |
| `load_project` | Load .sentinel file (dirty-state guard: pass `confirm` over unsaved changes; response lists `unresolved_project_dirs[]`). On 0.6.11 and newer the path joins Recent Projects |
| `save_project` | Save project; with `path`, a Save As: the open project moves to that path. On 0.6.11 and newer the path joins Recent Projects |
| `new_project` | Blank project (clears pipelines/sources/outputs; same dirty-state `confirm` guard) |
| `import_project` | Merge a foreign .sentinel into the live project (`path`, optional `x_offset`/`y_offset`; collision ids remap, response carries `id_map`) |
| `list_recovery` / `restore_recovery` / `discard_recovery` | Recovery autosave snapshots (list, restore with `confirm`, delete) |
| `diagnostic` | System/GPU/engine report |
| `engine_status` | Engine pack download status |
| `download_pack` / `install_pack` | Queue an official engine pack download (`pack_id`); poll `engine_status` |
| `bug_report` | Bundle logs/crashes/diagnostic into a local zip |
| `submit_bug_report` | Package and submit a bug/crash report (`title` + `narrative` required) |
| `workspace` | Workspace dir, install dir, launch command |
| `layout` | Named window layouts saved in the project, and the default layout new projects start with (`op`: list (default), save, recall, delete, set_default, restore_factory_default; `name` for save/recall/delete) |
| `capabilities` | Machine-readable IPC surface: every command with its accepted args (authoritative discovery) |

### `sentinel_state`: State tree access
| Action | Description |
|--------|-------------|
| `tree` | Get hierarchical tree |
| `get` | Read a value |
| `set` | Write a value |
| `set_many` | Write many values in one call with per-path results (`values`: object `{path: value}` or ordered array `[{path, value}]`) |
| `list_values` | List value paths |
| `list_actions` | List action paths |
| `invoke` | Call an action. Its arguments go in `args` as an object, for example OSC Out's `add_message` with `args={"address": "/live/level", "type": "float", "expr": "..."}` or a video source's `preroll` with `args={"time": 0}`. Unknown top-level fields are rejected |
| `snapshot` | Capture a pipeline's writable params as a typed bundle (`pipeline_id`, optional `bundle_path`); use before throwaway experiments |
| `restore` | Replay a snapshot bundle via set_many (`values` inline or `bundle_path`); per-path results, partial restore is safe |

### `sentinel_pipeline`: Pipeline & source management
| Action | Description |
|--------|-------------|
| `list` | List active pipelines (honest `healthy` + `health_reasons[]`, live `statusMessage`) |
| `list_types` | Build-derived pipeline type catalog (aliases, engine-pack requirements, categories) |
| `list_devices` | MIDI input and output port names (WinMM), for MIDI In/Out and controller profiles |
| `info` | Pipeline params/stats + data/control output summaries |
| `get_param` | Read-only computed value (`pipeline_id`, `param_name`) |
| `set_mode` | Operator mode: `mode` is `normal`, `freeze`, or `bypass`; `info` reports it as `operator_mode` |
| `create` | Create pipeline (sanitized `name` becomes the instance id; for modules pass `project_dir`, applied atomically: the compile runs async, so poll `compile_status`; `meshsource` takes `file_path`; place with `x`/`y` or `relative_to` + `direction` + `gap`) |
| `destroy` | Destroy pipeline |
| `rename` | TRUE rename: re-keys the instance id, rewrites references (graph, expressions, windows); returns `old_id` + final id |
| `force_reload` | Recompile a module from disk, works from compile-error state, returns param-diff report |
| `compile_status` | Poll a live Module compile: state, progress, elapsed/budget/remaining timing, slow/overdue flags, terminal reason, structured `error{file,line,message}` |
| `compile_check` | Offline module validation through the real compiler, no node created (`project_dir`); returns a `job_id` |
| `compile_check_status` | Poll an offline compile (`compile_job_id` = the `job_id` from `compile_check`) |
| `compile_extend` | Raise a running compile's total budget (`timeout_sec` 120-3600; `pipeline_id` + `job_id`, or `compile_job_id`) |
| `compile_abandon` | Ignore a running compile's eventual result (`confirm: true`, non-empty `reason`) |
| `set_input` | Connect source (video slots; data-port slots route via `sentinel_graph add_link`) |
| `list_sources` | List sources |
| `create_source` | Create source: `source_type` pattern/image/video/spout/ndi/capture, plus `video_path`, `image_path`, `sender_name`, `width`/`height` as the type needs (sanitized `name` becomes the instance id) |
| `delete_source` | Delete source |
| `rename_source` | TRUE rename of a source instance id |
| `set_source_type` | Rebuild a source as another backend type, keeping its id (`source_id`, `source_type`) |
| `create_output` | Create Spout/NDI output |
| `delete_output` | Delete output |
| `rename_output` | TRUE rename of an output instance id |
| `get_data_schemas` | Typed data port schemas (fields, element counts) |
| `capture_data_port` | Read back structured buffer data as JSON (GPU readback; `pipeline_id`, `port_name`); set `max_elements` explicitly to reach later records such as DMX universes |
| `capture_events` | Newest timestamped Event records on an Event port, with overflow and missed counts (`pipeline_id`, `port_name`, `max_records`) |
| `open_window` | Open pipeline preview/properties window |
| `close_window` | Close pipeline preview/properties window |

### `sentinel_graph`: Node graph wiring, inspection, placement, annotations
| Action | Description |
|--------|-------------|
| `get` | Full graph: nodes, links, bounds, annotation containment. `summary: true` returns the token-light shape (under half the size) |
| `get_selection` | Entity ids selected in the graph right now (`selected_entity_ids`, `count`) |
| `profile` | Live frame breakdown + per-node wall-clock timing, PipelineStats, link counts, and hotspot reasons |
| `inspect` | Bounded neighborhood around one node (`entity_id`, `direction` upstream/downstream/both, `depth`, `max_nodes`, `include_pins`, `include_geometry`). Prefer over `get` on large graphs |
| `list_links` | All links as lean slot tuples, no node data |
| `add_link` | Connect nodes. `from_slot`/`to_slot` accept an int index OR a pin name (exact name wins; errors list every pin with slot + type). Idempotent re-add returns `created: false` |
| `switch_input` | Replace whatever feeds an input slot in one call; reports `{link_id, replaced, removed_link_id}`, restores the old link if the new one fails |
| `remove_link` | Disconnect (`link_id` or entity pair + `to_slot`) |
| `clear_links` | Remove all links |
| `auto_layout` | Arrange the whole graph left-to-right. Reserve for explicit batch work or smoke tests; visible authoring uses `place_relative`/`layout_neighborhood`. Needs `confirm: true` past 10 positioned nodes |
| `layout_neighborhood` | Arrange only the neighborhood around one node (`entity_id`, `direction`, `depth`, `anchor`, `dry_run`). Leaves the rest untouched |
| `focus` | Center/zoom the graph view on one node |
| `set_view` | Put the graph view at an exact `zoom` and `pan_x`/`pan_y` for reproducible captures (`get` reports the current view) |
| `get_node_geometry` | One node's position, bounds, containment. Nodes with a body add `body_width`/`body_height` (grid units, 0 = automatic), `body_size_set` and `body_image_rect` (screen-space preview image) |
| `set_node_geometry` | Move a node, resize an annotation frame, or size a node body box (`x`/`y`, `width`/`height` 80-4096 by 45-4096, `reset_size: true`). Validated before any write; body resizes are undoable. Previews letterbox inside the box |
| `place_relative` | Place a node next to an anchor with spacing + collision avoidance (`relative_to`, `direction`, `gap`, `within`) |
| `move_nodes` | Move a node set as one rigid unit (`entity_ids[]` + `dx`/`dy` or `x`/`y` or `relative_to`) |
| `add_annotation` / `update_annotation` / `delete_annotation` | Annotation boxes (`title`, `body`, `color`, geometry) |
| Scene Groups | `list_scene_groups`, `scene_group_info`, `convert_to_scene_group`, `revert_to_annotation`, `switch_to_scene_group`, `set_scene_group_enabled`, `expose_scene_group_parameter`, `remove_scene_group_parameter`, `save_scene_group_preset`, `recall_scene_group_preset` (control-only groups; `entity_id` of the group annotation) |
| `export_scene_group` | Write a Scene Group as a portable `.sentinel` project (`entity_id`, `path`); the response reports every boundary crossing. Import it elsewhere with `sentinel_app import_project` |
| `set_panel_presentation` | A Module panel's presentation (`entity_id`, `mode`: follow_module, standard, canvas) |
| `set_panel_resolution_mode` | A Module panel's render resolution (`entity_id`, `mode`: follow_module, pipeline, follow_panel, follow_panel_half, follow_panel_quarter, follow_panel_double) |
| `set_output_fit_mode` | How a pipeline output fits its window (`pipeline_id`, `fit_mode` 0 Letterbox, 1 Fit Outside, 2 Stretch) |

### `sentinel_capture`: GPU texture readback & recording
| Action | Description |
|--------|-------------|
| `source` | Capture source texture to PNG |
| `pipeline` | Capture pipeline output to PNG (`slot` for multi-output nodes) |
| `capture_at` | One-call review still(s): apply `overrides` `{param: value or [values]}`, wait for in-flight compile, settle, capture, restore. Lists zip; `combo_mode: "cartesian"` for the product (cap 64). Optional `slot`, `region` `{x,y,w,h}`, `max_width` |
| `proof_bundle` | User-facing proof folder: graph, links, graph profile, pipeline health, expressions, output capture, window screenshot, optional image diff |
| `checkpoint` | One call: save project (bundling Module folders), capture pipeline output, record graph profile into a timestamped folder |
| `record_pipeline` | Record pipeline output: `mode` video (NVENC MP4) or png_sequence; optional WASAPI audio via `capture_audio` + `audio_source` (loopback/microphone) + `audio_endpoint` |
| `record_pipeline_input` | Record the texture going INTO a pipeline at slot N |
| `record_source` | Record a source texture |
| `record_window` | Record the rendered Sentinel client area to MP4 |
| `stop_recording` | Finalize; returns frames written/dropped, output path |
| `list_recordings` | Active + recently finalized recordings |
| `list_audio_devices` | Active render-loopback and microphone endpoints with IDs and default flags |
| `session_start` / `session_stop` / `session_marker` / `session_status` | Capture Session: frame-aligned window recording with input/event JSONL, layout control, `chroma_format` |
| `sweep_record` | Frame-locked parameter sweep recorded to MP4, blocking; for motion eval (see `motion-eval` skill). `loop_mode`: trim_wrap (default when loops > 1) / pingpong / none; `restore_baseline` (default true) |
| `render_sequence` | Start an asynchronous fixed-step PNG job. Requires `pipeline_id`, `fps`, and `frame_count`; accepts `slot`, `start_time`, `format`, `filepath`, `use_conductor`, and `tracks`; returns `job_id`. `pipeline_ids` (with optional `slots`) renders several outputs from one pass, each to `<filepath>/<pipeline id>` |
| `render_status` | Poll stepped, accepted, encoded, in-flight, manifest, and terminal fields for `job_id` |
| `render_cancel` | Request cancellation of `job_id` after its in-flight frame; poll status until terminal |

### `sentinel_screenshot`: Screen capture (inline image)
| Action | Description |
|--------|-------------|
| `window` | Full window screenshot |
| `element` | Specific UI panel |

### `sentinel_ui`: ImGui widget interaction
| Action | Description |
|--------|-------------|
| `get_tree` | Get UI widget tree |
| `get_info` | Element bounds/value |
| `click` | Click element |
| `set` | Set widget value (auto-detects type) |
| `send_key` | Keyboard shortcut or key. On 0.6.11 and newer, keypad keys are `numpad0`-`numpad9`, `numpad_enter`, `numpad_decimal` and `numpad_subtract`, and `period` and `minus` are the main-row keys. A focused Module panel receives them as key events |
| `get_panels` | List all panels and visibility |
| `set_panel` | Show/hide a panel |
| `terminal_read` | Read embedded-terminal grid lines, cursor, and child status without injecting input |
| `drag_at` | Press, move, release at client coordinates (`start_x`/`start_y`/`end_x`/`end_y`, or `phase` begin/update/end with modifiers held by `send_key shift_down`) |
| `hover_at` | Park the pointer at client coordinates so tooltips show |
| `click_at` | Click at client coordinates (`start_x`, `start_y`, `button`, `modifiers` such as `["ctrl"]` held through the click) |
| `double_click` | Double-click a tracked path (rect center) or `start_x`/`start_y`. Resolve rects with `get_info` first when a header carries buttons |
| `viewport_control_drag` | Drive an authored Module viewport control through begin/update/end (`pipeline`, `control`, `phase`, `x`/`y` in 0-1 control space, `steps`) |

Installs at 0.5.48 or newer deliver `click` (method `mouse`), drags, and `send_key` as synthetic events injected directly into the ImGui event queue: the user's hardware cursor, keyboard state, and window focus stay untouched while automation drives the UI, and mouse-path responses report `client_pos` in main-viewport client space. Older installs drive the real OS mouse for these paths and can move the user's cursor (including across monitors), so on those builds prefer `method: button` or `select` and the `set` action, which have always been injection-free.

### `sentinel_preset`: Identity-aware node presets
`list` / `save` / `recall` / `update` / `delete` / `rename` / `bundle` / `copy_to_library`. Presets are keyed by node identity, discoverable by pipeline or identity, saved to library or project scope (plus a bundled scope for presets that travel with a show), and support grouped compound-safe param selection, `include_engine_params`, and strict or loose recall onto compatible nodes.

### `sentinel_expression`: Typed ref() parameter drivers
`set` / `get` / `clear` / `list` for expression drivers, and `set_bind` / `list_binds` / `clear_bind` for bidirectional parameter binds. Always use this for expression drivers; `sentinel_state set` with a literal `=ref(...)` string writes a value without registering the expression engine binding. A bind (`set_bind` with `path` + `peer_path`, or `endpoints[]`) links two or more pipeline parameters so writing any one moves the others; it saves with the project. See `knowledge/expressions-and-drivers.md`.

### `sentinel_conductor`: Cue sheets and transport
`load_sheet` / `bake_sheet` / `status` / `fire` / `jump` / `set_tempo` / `transport`. Compiles cue-sheet YAML into sheet params and generated expressions on a Conductor node.

### `sentinel_blueprint`: Precise construction compiler
`validate` / `solve_report` / `compile` / `audit`. Registry-backed relational blueprints compiled into PNode-record Modules. See the `procedural-geometry-authoring` skill.

### `sentinel_module`: Module authoring helpers
`scaffold_from_ports` / `bundle` / `extract` / `import` / `bake_defaults`. Scaffold a module from an upstream data-port schema, bundle or move modules between shows, and write live values back into manifest defaults.

### `sentinel_fixture`: GDTF, MVR and Fixture Rig editing
Read files offline: `inspect` / `scene` / `validate` / `orientation` / `library` / `export_type` / `diff` (absolute `path`s, `library_dir`). Edit a Fixture Rig node's rig (`pipeline`): `import_mvr` / `add_fixtures` / `edit_fixtures` / `duplicate_fixtures` / `remove_fixtures` / `auto_patch` / `bind_type` / `export_mvr` / `collect` / `refine`. See `knowledge/fixture-import.md` and the `fixture-refinement` skill.

### `sentinel_viewport`: Authored viewport inspection and transactions
`info` / `objects` / `selection` (with `selection_action` get/set/clear; `set` needs `ids`) / `pick` (`x`/`y` normalized; the async result is polled for you) / `edit` (`object_id` plus a target `x`/`y` runs a begin/preview/commit move transaction with auto-cancel; pass `phase` for manual control) / `state` (durable state-buffer inventory). Every action takes `pipeline`. `pick` returns the hit `object_id` one frame later, and an `edit` commit lands in the Module's bound parameters, including `hidden: true` gesture parameters. Requires Sentinel 0.5.31 or newer.

### `sentinel_vision`: AI visual review
`status` / `configure` / `models` / `eval` / `compare` / `eval_pipeline`. Evaluates captures through OpenAI-compatible vision providers; `eval_pipeline` captures and evaluates one pipeline output in a single call. First-time key setup edits the workspace `vision.json` (never pass API keys in chat or tool args).

## Crash Detection

```python
# Via MCP
sentinel_app action="status"
# Returns: Status: crashed, PID: ..., Exit Code: ..., Recent stderr: ...

# Via Python IPC client
status = get_app_status()
if status['status'] == 'crashed':
    print(f"Exit code: {status['exit_code']}")
```

## Additional Resources

- See [ipc-reference.md](ipc-reference.md) for full IPC command reference
- See [state-tree.md](state-tree.md) for StateTree API
- See [item-tracking.md](item-tracking.md) for adding automation to new panels
