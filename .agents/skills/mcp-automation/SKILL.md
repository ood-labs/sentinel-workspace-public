---
name: mcp-automation
description: Control Sentinel via MCP automation and IPC. Use when testing UI, automating pipelines, writing automation scripts, debugging IPC communication, setting up test environments, or working with the ZMQ automation bridge.
distribution: true
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

Distribution builds always have automation enabled — skip this section if you're on the installed Sentinel. For dev builds:

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

**ALWAYS use Bash to launch Sentinel**, not the MCP tool. Launch from the install directory (or dev build directory):

```bash
# Distribution install (default)
start "" "C:\Program Files\OODLabs\Sentinel\sentinel.exe"

# Dev build
start "" "<repo_root>/build/bin/Release/sentinel.exe"
```

Wait 3-5 seconds for the app to initialize before sending IPC commands.

## MCP Tools (7 multi-action tools)

All tools use an `action` parameter. Examples:

```
# Test connectivity
sentinel_app action="ping"

# Get the full state tree (for discovery)
sentinel_state action="tree" path="/sentinel"

# Read/write state values
sentinel_state action="get" path="/sentinel/pipelines/colorcorrect_0/parameters/brightness"
sentinel_state action="set" path="/sentinel/pipelines/colorcorrect_0/parameters/brightness" value=0.5

# Invoke actions
sentinel_state action="invoke" path="/sentinel/pipelines/streamdiff_0/actions/relaunch"

# Create pipeline and source
sentinel_pipeline action="create_source" type="pattern"
sentinel_pipeline action="create" type="colorcorrect"
sentinel_pipeline action="set_input" pipeline_id="colorcorrect_0" source_id="source_0"

# Query pipelines
sentinel_pipeline action="list"
sentinel_pipeline action="info" pipeline_id="colorcorrect_0"
```

## Core Agent Workflow Patterns

- **Discovery**: `sentinel_app action="capabilities"` returns every IPC command with its accepted args. Unknown args are rejected with the expected list, so typos fail loudly.
- **Honest health**: `list`/`info` report a bridge-computed `healthy` with `health_reasons[]` naming the exact cause (no frames, compile error, unresolved project_dir, zombie) plus a live `statusMessage`. Trust these over raw `loaded_*` flags.
- **One-call module create**: `sentinel_pipeline create type="module" name="X" project_dir="..."` is atomic; the response carries `compile_ok`/`compile_error` and the registered params.
- **Async compiles**: module shaders compile on a worker thread. Poll `compile_status` for progress and structured errors; `sentinel_app status` shows `busy` + `compiling[]` after a project load; `force_reload` recovers from a compile-error state; `compile_check` validates a project dir without creating a node.
- **Batch writes**: `sentinel_state set_many` applies many parameter writes in one call with per-path results.
- **One-call review stills**: `sentinel_capture capture_at` applies overrides, waits for compiles, settles, captures, and restores. Use it instead of hand-rolling set / sleep / capture / set-back chains.
- **Runtime proof**: `sentinel_graph profile` reports frame buckets, per-node wall time, graph link counts, PipelineStats, and hotspot reasons. `sentinel_capture proof_bundle` includes `graph_profile.json` plus a Performance section.
- **Project safety**: `load_project`/`new_project` refuse over unsaved changes unless `confirm: true`; `import_project` merges another .sentinel into the live project with id remap.

## Python IPC Client (dev only)

For Python automation scripts in the dev repo, use the IPCClient at `src/ipc/client.py`. Distribution users should drive Sentinel via the MCP tools above (no Python source ships in the installer).

## Pipeline Type IDs

Use these exact strings with `sentinel_pipeline action="create"`:
- `"colorcorrect"` — Color Correction
- `"streamdiff"` — StreamDiffusion
- `"facemesh"` — Face Mesh (468 landmarks, includes face detection)
- `"depthestimation"` — Depth Anything V2 depth estimation
- `"matting"` — RobustVideoMatting background removal
- `"pose"` — Pose Estimation (YOLO11-Pose → OpenPose-18)
- `"module"` — Module pipeline (multi-pass YAML projects, compute-first 3D)
- `"hlslshader"` — HLSL Shader (Notch HLSL post-processing)
- `"torchv2v"` — Torch V2V
- `"fluxklein"` — FLUX.2 Klein V2V
- `"detection"` — Detection (ONNX Runtime YOLOX)
- `"personseg"` — Person Segmentation (RF-DETR-Seg)
- `"opticalflow"` — Optical Flow (NVOF hardware accelerator)
- `"vsr"` — RTX Video Super Resolution
- `"samtrack"` — SAMTrack (experimental)

NOT display names like "Color Correction" — those won't work.

## Source Types

- `"pattern"` - Internal test pattern (auto-connects)
- `"image"` - Static image file
- `"spout"` - Spout texture sharing (requires `sender_name`)
- `"ndi"` - NDI video stream (requires `sender_name`)
- `"capture"` - Webcam/capture card

## MCP Tools Reference

### `sentinel_app` — Application lifecycle
| Action | Description |
|--------|-------------|
| `ping` | Test connectivity |
| `launch` | Launch Sentinel |
| `kill` | Terminate app |
| `status` | Check running/crashed; also `busy`, `compiling[]`, `dirty`, `window_visible` |
| `logs` | Get stdout/stderr |
| `load_project` | Load .sentinel file (dirty-state guard: pass `confirm` over unsaved changes; response lists `unresolved_project_dirs[]`) |
| `save_project` | Save project |
| `new_project` | Blank project (clears pipelines/sources/outputs; same dirty-state `confirm` guard) |
| `import_project` | Merge a foreign .sentinel into the live project (`path`, optional `x_offset`/`y_offset`; collision ids remap, response carries `id_map`) |
| `diagnostic` | System/GPU/engine report |
| `engine_status` | Engine pack download status |
| `bug_report` | Bundle logs/crashes/diagnostic into a local zip |
| `submit_bug_report` | Package and submit a bug/crash report (`title` + `narrative` required) |
| `workspace` | Workspace dir, install dir, launch command |
| `capabilities` | Machine-readable IPC surface: every command with its accepted args (authoritative discovery) |

### `sentinel_state` — State tree access
| Action | Description |
|--------|-------------|
| `tree` | Get hierarchical tree |
| `get` | Read a value |
| `set` | Write a value |
| `set_many` | Write many values in one call with per-path results (`values`: object `{path: value}` or ordered array `[{path, value}]`) |
| `list_values` | List value paths |
| `list_actions` | List action paths |
| `invoke` | Call an action |

### `sentinel_pipeline` — Pipeline & source management
| Action | Description |
|--------|-------------|
| `list` | List active pipelines (honest `healthy` + `health_reasons[]`, live `statusMessage`) |
| `info` | Pipeline params/stats + data/control output summaries |
| `get_param` | Read-only computed value (`pipeline_id`, `param_name`) |
| `create` | Create pipeline (sanitized `name` becomes the instance id; for modules pass `project_dir` for an atomic create whose response carries `compile_ok`/`compile_error` + registered params; optional `enabled`, `x`/`y`) |
| `destroy` | Destroy pipeline |
| `rename` | TRUE rename: re-keys the instance id, rewrites references (graph, expressions, windows); returns `old_id` + final id |
| `force_reload` | Recompile a module from disk, works from compile-error state, returns param-diff report |
| `compile_status` | Poll async module compile: `{state, progress{done,of}, error{file,line,message}, params[]}` |
| `compile_check` | Offline module validation through the real compiler, no node created (`project_dir`) |
| `set_input` | Connect source (video slots; data-port slots route via `sentinel_graph add_link`) |
| `list_sources` | List sources |
| `create_source` | Create source (sanitized `name` becomes the instance id) |
| `delete_source` | Delete source |
| `rename_source` | TRUE rename of a source instance id |
| `create_output` | Create Spout/NDI output |
| `delete_output` | Delete output |
| `rename_output` | TRUE rename of an output instance id |
| `get_data_schemas` | Typed data port schemas (fields, element counts) |
| `capture_data_port` | Read back structured buffer data as JSON (GPU readback) |
| `open_window` | Open pipeline preview/properties window |
| `close_window` | Close pipeline preview/properties window |

### `sentinel_graph` — Node graph wiring, inspection, placement, annotations
| Action | Description |
|--------|-------------|
| `get` | Full graph: nodes, links, bounds, annotation containment. `summary: true` returns the token-light shape (under half the size) |
| `profile` | Live frame breakdown + per-node wall-clock timing, PipelineStats, link counts, and hotspot reasons |
| `inspect` | Bounded neighborhood around one node (`entity_id`, `direction` upstream/downstream/both, `depth`, `max_nodes`, `include_pins`, `include_geometry`). Prefer over `get` on large graphs |
| `list_links` | All links as lean slot tuples, no node data |
| `add_link` | Connect nodes. `from_slot`/`to_slot` accept an int index OR a pin name (exact name wins; errors list every pin with slot + type). Idempotent re-add returns `created: false` |
| `switch_input` | Replace whatever feeds an input slot in one call; reports `{link_id, replaced, removed_link_id}`, restores the old link if the new one fails |
| `remove_link` | Disconnect (`link_id` or entity pair + `to_slot`) |
| `clear_links` | Remove all links |
| `auto_layout` | Arrange the whole graph left-to-right. Run after wiring via MCP, nodes spawn at (0,0). Needs `confirm: true` past 10 positioned nodes |
| `layout_neighborhood` | Arrange only the neighborhood around one node (`entity_id`, `direction`, `depth`, `anchor`, `dry_run`). Leaves the rest untouched |
| `focus` | Center/zoom the graph view on one node |
| `get_node_geometry` | One node's position, bounds, containment |
| `set_node_geometry` | Move a node; resize annotations (`x`/`y`, `width`/`height`) |
| `place_relative` | Place a node next to an anchor with spacing + collision avoidance (`relative_to`, `direction`, `gap`, `within`) |
| `move_nodes` | Move a node set as one rigid unit (`entity_ids[]` + `dx`/`dy` or `x`/`y` or `relative_to`) |
| `add_annotation` / `update_annotation` / `delete_annotation` | Annotation boxes (`title`, `body`, `color`, geometry) |

### `sentinel_capture` — GPU texture readback & recording
| Action | Description |
|--------|-------------|
| `source` | Capture source texture to PNG |
| `pipeline` | Capture pipeline output to PNG (`slot` for multi-output nodes) |
| `capture_at` | One-call review still(s): apply `overrides` `{param: value or [values]}`, wait for in-flight compile, settle, capture, restore. Lists zip; `combo_mode: "cartesian"` for the product (cap 64). Optional `slot`, `region` `{x,y,w,h}`, `max_width` |
| `proof_bundle` | User-facing proof folder: graph, links, graph profile, pipeline health, expressions, output capture, window screenshot, optional image diff |
| `record_pipeline` | Record pipeline output: `mode` video (NVENC MP4) or png_sequence; optional WASAPI loopback audio via `capture_audio` |
| `record_pipeline_input` | Record the texture going INTO a pipeline at slot N |
| `record_source` | Record a source texture |
| `stop_recording` | Finalize; returns frames written/dropped, output path |
| `list_recordings` | Active + recently finalized recordings |
| `sweep_record` | Frame-locked parameter sweep recorded to MP4, blocking; for motion eval (see `motion-eval` skill). `loop_mode`: trim_wrap (default when loops > 1) / pingpong / none; `restore_baseline` (default true) |

### `sentinel_screenshot` — Screen capture (inline image)
| Action | Description |
|--------|-------------|
| `window` | Full window screenshot |
| `element` | Specific UI panel |

### `sentinel_ui` — ImGui widget interaction
| Action | Description |
|--------|-------------|
| `get_tree` | Get UI widget tree |
| `get_info` | Element bounds/value |
| `click` | Click element |
| `set` | Set widget value (auto-detects type) |
| `send_key` | Keyboard shortcut |
| `get_panels` | List all panels and visibility |
| `set_panel` | Show/hide a panel |

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
