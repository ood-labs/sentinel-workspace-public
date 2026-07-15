# IPC Protocol Reference

All commands use ZeroMQ REQ/REP pattern on `tcp://127.0.0.1:5555`.

**Authoritative discovery**: `GET_CAPABILITIES` returns every command with its accepted args and protocol version. The table below is a curated subset; when in doubt, trust `GET_CAPABILITIES`. Argument validation is strict: unknown keys are rejected with the expected list.

## Available Commands

| Command | Description |
|---------|-------------|
| `GET_CAPABILITIES` | Full command surface: per-command args, schema hashes, protocol_version |
| `PING` | Test connectivity |
| `GET_UI_TREE` | Get full UI hierarchy as JSON |
| `CLICK` | Click window/panel/item by path |
| `KEY` | Send keyboard input (shortcuts, text) |
| `GET_ITEM_INFO` | Get element position and size |
| `SET_SLIDER` | Set slider value directly (no focus needed) |
| `SET_CHECKBOX` | Set checkbox state directly |
| `SET_TREE_STATE` | Expand/collapse tree nodes |
| `SET_TEXT` | Set text input value |
| `SET_COMBO` | Set combo box selection |
| `SET_COLOR` | Set color picker value |
| `GET_PIPELINES` | List active pipelines with stats |
| `GET_PIPELINE_INFO` | Get detailed pipeline info with parameters |
| `GET_TREE` | Get unified state tree |
| `GET_STATE_VALUE` | Get single value by path |
| `SET_STATE_VALUE` | Set value by path |
| `SET_STATE_VALUES` | Set many values in one call (object or ordered array), per-path results |
| `INVOKE_ACTION` | Invoke action by path |
| `LIST_ACTIONS` | List all actions under a path |
| `LIST_VALUES` | List all values under a path |
| `LOAD_PROJECT` | Load project from file path (dirty-state guard with `confirm`; reports `unresolved_project_dirs[]`) |
| `SAVE_PROJECT` | Save current project to file path |
| `NEW_PROJECT` | Create new empty project (dirty-state guard with `confirm`) |
| `IMPORT_PROJECT` | Merge a foreign .sentinel into the live project (id remap, link rebuild, `x_offset`/`y_offset`) |
| `GET_PROJECT_INFO` | Get current project name, path, and `saved_at_ms` |
| `GET_APP_STATUS` | App status including `busy`, `compiling[]`, `dirty`, `window_visible` |
| `FORCE_RELOAD` | Recompile a module from disk with structured report + param diffs |
| `COMPILE_STATUS` | Async compile state: `{state, job_id, progress{done,of}, error{file,line,message}, params[]}` |
| `COMPILE_CHECK` | Offline module validation through the real compiler, no node created |
| `CAPTURE_AT` | One-call stills: overrides + wait_for_compile + settle + capture + restore |
| `SWEEP_RECORD` | Frame-locked parameter sweep to MP4 (`loop_mode`, `restore_baseline`) |
| `ADD_LINK` / `SWITCH_INPUT` / `REMOVE_LINK` / `LIST_LINKS` | Graph wiring; slots accept int index or pin name; SWITCH_INPUT reports `{link_id, replaced, removed_link_id}` |
| `GET_GRAPH` | Graph topology (`summary` arg for the lean shape); see `sentinel_graph` MCP actions for the full geometry/annotation/layout family |
| `RENAME_PIPELINE` / `RENAME_SOURCE` / `RENAME_OUTPUT` | True instance-id re-key with reference rewrite |
| `SET_EXPRESSION` | Set expression on a parameter |
| `GET_EXPRESSION` | Get expression for a parameter |
| `CLEAR_EXPRESSION` | Remove expression from a parameter |
| `LIST_EXPRESSIONS` | List all active expressions |
| `LIST_CONTROL_OUTPUTS` | List control output values for a pipeline |
| `GET_PIPELINE_PARAM` | Get read-only computed value (e.g., loaded_has_controlnet) |

## Example Request/Response

```json
// Set slider value
{"cmd": "SET_SLIDER", "path": "Properties/Parameters/Brightness", "value": 0.5}
// Response: {"status": "ok", "data": {"clampedValue": 0.5}}

// List pipelines
{"cmd": "GET_PIPELINES"}
// Response: {"status": "ok", "data": {"pipelines": [{"id": "colorcorrect_0", ...}]}}

// Get pipeline parameters
{"cmd": "GET_PIPELINE_INFO", "pipeline": "colorcorrect_0"}
// Response: {"status": "ok", "data": {"parameters": [...], "stats": {...}}}

// Set value via StateTree
{"cmd": "SET_STATE_VALUE", "path": "/sentinel/pipelines/colorcorrect_0/parameters/brightness", "value": 0.5}

// Invoke action
{"cmd": "INVOKE_ACTION", "path": "/sentinel/pipelines/colorcorrect_0/actions/relaunch"}

// Load project
{"cmd": "LOAD_PROJECT", "path": "C:/path/to/project.sentinel"}
// Response: {"status": "ok", "data": {"path": "...", "name": "projectname"}}

// Save project
{"cmd": "SAVE_PROJECT", "path": "C:/path/to/project.sentinel"}
// Response: {"status": "ok", "data": {"path": "..."}}

// Get project info
{"cmd": "GET_PROJECT_INFO"}
// Response: {"status": "ok", "data": {"name": "projectname", "path": "...", "hasUnsavedChanges": false}}

// Set expression on parameter (Phase 40)
{"cmd": "SET_EXPRESSION", "path": "/sentinel/pipelines/streamdiff_0/parameters/denoise", "expression": "sin(time*2)*0.3+0.5"}
// Response: {"status": "ok", "data": {"path": "...", "expression": "...", "compiled": true}}

// Get expression
{"cmd": "GET_EXPRESSION", "path": "/sentinel/pipelines/streamdiff_0/parameters/denoise"}
// Response: {"status": "ok", "data": {"path": "...", "expression": "sin(time*2)*0.3+0.5", "has_expression": true}}

// Clear expression
{"cmd": "CLEAR_EXPRESSION", "path": "/sentinel/pipelines/streamdiff_0/parameters/denoise"}

// List all expressions
{"cmd": "LIST_EXPRESSIONS"}
// Response: {"status": "ok", "data": {"expressions": {"/sentinel/...": "sin(time*2)"}, "count": 1}}

// List control outputs for a module pipeline
{"cmd": "LIST_CONTROL_OUTPUTS", "pipeline": "module_0"}
// Response: {"status": "ok", "data": {"control_outputs": {"lfo1": 0.5, "lfo2": -0.3}, "count": 2}}
```

## IPC Client Methods

| Method | Description |
|--------|-------------|
| `connect()`, `disconnect()` | Connection management |
| `reconnect()` | Disconnect and reconnect |
| `wait_for_connection(timeout_ms)` | Wait for app to become available |
| `ping()` | Test connectivity |
| `get_ui_tree()` | Get UI hierarchy |
| `click(path)` | Click element |
| `set_slider(path, value)` | Set slider |
| `set_checkbox(path, value)` | Set checkbox |
| `set_combo(path, index)` | Set combo box |
| `set_text(path, value)` | Set text input |
| `key_press(keys)` | Send keyboard input |
| `get_item_info(path)` | Get element bounds |
| `create_source(type, name, ...)` | Create source object |
| `delete_source(id)` | Delete source |
| `connect_source_object(id)` | Connect source to backend |
| `create_pipeline(type, name)` | Create pipeline |
| `destroy_pipeline(id)` | Destroy pipeline |
| `get_pipelines()` | List all pipelines |
| `get_pipeline_info(id)` | Get pipeline details |
| `set_pipeline_input(pipeline, source_id)` | Route source to pipeline |
| `get_tree(path)` | Get StateTree subtree as JSON |
| `get_state_value(path)` | Get value with metadata |
| `set_state_value(path, value)` | Set value by path |
| `invoke_action(path, **args)` | Invoke action by path |
| `list_values(path)` | List all value paths under node |
| `list_actions(path)` | List all action paths under node |
| `load_project(path)` | Load project from file |
| `save_project(path)` | Save project to file |
| `new_project()` | Create empty project |
| `get_project_info()` | Get project name and path |
| `set_expression(path, expr)` | Set per-frame expression on parameter |
| `get_expression(path)` | Get expression string for parameter |
| `clear_expression(path)` | Remove expression from parameter |
| `list_expressions()` | List all active expressions |
| `list_control_outputs(pipeline)` | List Module control output values |
| `get_pipeline_param(pipeline, param)` | Get read-only computed value |

## Custom Exceptions

```python
from ipc import IPCError, IPCTimeoutError, IPCConnectionError, IPCCommandError

# IPCError - Base class for all IPC errors
# IPCConnectionError - Not connected or connection lost
# IPCTimeoutError - Command timed out (has .command, .timeout_ms)
# IPCCommandError - Command failed on server (has .command, .message)
```

## Per-Command Timeout

```python
# Default timeout is 35 seconds
client = IPCClient(timeout_ms=5000)  # 5 second default

# Override for slow operations
client.send_command("CREATE_PIPELINE", type="streamdiff", timeout_ms=60000)
```

## SET_COMBO Index Reference

**Pipeline Input Slot (InputTile):**
- Index 0: "(Select)" or slot name - no source
- Index 1: "Active Source" (__active__) - for VideoSource slots only
- Index 2+: Actual sources from SourceManager in order

Example: To select first created source, use index 2:
```python
client.set_combo('Facetrack - facetrack_0/Slot0', 2)
```

**Spout/NDI Sender Selection (PropertiesPanel):**
- Index 0: "(none)"
- Index 1+: Available senders in discovery order

## Key Insights

1. **Processing order matters**: `ItemTracker::beginFrame()` before panels render, `AutomationBridge::processCommands()` after
2. **ClientToScreen conversion**: ImGui coordinates are relative to client area
3. **Pending values work in background**: Applied during render loop, no focus needed
4. **Thread safety**: ZMQ listener on background thread, ImGui commands queued for main thread
5. **SET_COMBO uses indices, not values**: Determine correct index from combo list structure
6. **Pending combo values require explicit consumption**: Check panel has automation support
