---
name: script-node-authoring
description: Write and run Luau logic in Sentinel's Script node (`script`). Covers the manifest (Signal, Event and Display pins plus typed parameters), the callbacks, the host bindings (`sentinel`, `state`, `log`, `time`, `ui`, `require`, `preset`, `osc`, `windows_audio`), Event records, the tracked control window, project-saved snapshots and the startup restore barrier, budgets, memory and performance, hot reload and packages, and MCP setup and proof. Use when writing a `.luau` script, wiring a Script into a graph, routing MIDI or Module events through script logic, receiving OSC, building a script control panel, persisting script state across save and reopen, or debugging a Script that shows ERR, runs out of memory, misses its budget or stops reloading. For MIDI controllers and the Push 2 panel use `controller-surface-authoring`.
---

# Script Node Authoring

The Script node (`script`) runs one sandboxed Luau VM on Sentinel's 240 Hz
control clock. A script file declares its pins and parameters in a manifest
and implements callbacks. The node is a Control-category node: it has no
pixel output and it never touches the GPU.

Use a Script for control logic: mapping, sequencing, gating, state machines,
note generation, parameter links between nodes, controller surfaces and small
operator panels. Use a Module for anything that produces pixels or runs per
pixel or per particle.

## File layout

Put scripts in the saved project folder:

```
my_show/
  my_show.sentinel
  scripts/
    my_logic.luau
    sentinel.d.luau        # editor declarations, copied by Sentinel
    .luaurc                # optional aliases
    packages/
      scale.luau           # require("scale")
      util/init.luau       # require("util")
```

Set the node's `script_path` to `scripts/my_logic.luau` (relative to the
saved project). Save the project before authoring so relative paths resolve.

The first Script in a saved project copies `sentinel.d.luau` into `scripts/`
when it is absent. Point your editor's Luau definition-file setting at it for
completion and type checking. It is a declaration file: never `require` it.

## The smallest script

```lua
local script = {}
script.manifest = {
    name = "Gain",
    inputs = {{name = "value", type = "signal"}},
    outputs = {{name = "scaled", type = "signal"}},
    params = {{name = "gain", type = "float", default = 1, min = 0, max = 2}},
}
function script.control_process(node, ctx)
    node.outputs.scaled:set(node.inputs.value:get() * node.params.gain)
end
return script
```

The file returns a table with `manifest` and optional callbacks. Sentinel
evaluates the top level once in a disposable VM with no host bindings to read
the manifest, so keep the top level free of `sentinel.*`, `midi.*`,
`require` and other host calls. Do that work in `init` or later callbacks.

## Manifest

| Field | Contract |
| --- | --- |
| `name` | Nonempty display string |
| `inputs` | Up to 32 pins, each `{name, type}` with `signal` or `event` |
| `outputs` | Up to 32 pins with `signal`, `event` or `display` |
| Pin names | Identifiers, unique across inputs and outputs |
| `params` | Up to 64 declarations |
| Param `type` | `float`, `int`, `bool`, `string` or `enum` |
| `default`, `min`, `max` | Typed default and numeric bounds; ints must be integral |
| `values` | Enum only: nonempty array of unique strings; `default` names one |
| `transient` | Optional bool; the value is left out of project saves |

Reserved names: host parameters (`script_path`, `reload`, the budget
parameters, `pins_json`) and the host telemetry outputs (`tick_us`,
`tick_us_p99`, `gc_us`, `heap_kb`, `budget_misses`, `skipped`, `errors`,
`reloads`, `health`). Pick other names.

Manifest parameters are ordinary StateTree parameters. They save with the
project, work with presets, show in Properties and accept `ref()`
expressions. They are the place for durable state.

Pins match across reloads by name and type. Renaming a pin or changing its
type drops the cables attached to it; adding or reordering pins keeps them.

## Callbacks

| Callback | When it runs |
| --- | --- |
| `init(node)` | Once after the script loads or reloads |
| `control_process(node, ctx)` | Every admitted control tick. `ctx.tick` is the tick index, `ctx.dt` the period in seconds, `ctx.time` seconds since app start |
| `render(node, ui)` | At most once per UI frame while the node's control window is open |
| `render_display(node, d)` | When a connected Push 2 Display asks for a frame |
| `restore(node)` | Twice a second while a `state.begin_restore()` barrier is open; 50 ms budget, one miss errors (see Startup) |
| `serialize(node)` | Before a reload and on every project save; returns a plain table |
| `deserialize(node, saved)` | On the new VM before `init`, after a reload or a project reopen (50 ms budget) |
| `stop(node)` | Before the VM retires, including after errors |

`node.state` is a free script table. It survives reload and project
save/reopen only when you carry it with `serialize`/`deserialize`:

```lua
function script.serialize(node) return {version = 1, data = node.state} end
function script.deserialize(node, saved)
    if saved.version == 1 then node.state = saved.data end
end
```

The packet holds finite numbers, booleans, strings and nested tables (number,
string or boolean keys) up to 64 KiB and 32 levels. Functions, userdata,
cycles and NaN or infinity are rejected. On save, Sentinel asks the running VM
for a fresh capture (50 ms deadline; the save frame waits for it) and stores it
in the hidden `script_snapshot_json` parameter. A serializer that throws
refuses the save and keeps the last good packet; a save while init or reload
is still pending is refused too.

- Version the table and upgrade old shapes in `deserialize`. Adding a durable
  record without an upgrade path is a common reload failure.
- Never serialize a half-started runtime as if it were complete. If startup
  has not finished, return the packet you received instead.
- Values that mirror state owned elsewhere (another node's parameter, a
  preset bank) go stale in a snapshot. Re-read the owner after restore instead
  of trusting the saved copy.
- Keep `serialize` cheap. It runs inside the save frame.

Use `serialize` for a script's working state as a whole. Use manifest
parameters for values an operator edits in Properties or presets, and
`state.register` for per-value durable state with a shape decided at run time.

Node modes apply as usual: Freeze holds every output, Bypass drains Event
inputs without running `control_process`, Disable marks outputs unavailable.

## Bindings

### Pins and parameters

| Call | Result |
| --- | --- |
| `node.inputs.x:get()` | Latest Signal value (number) |
| `node.inputs.x:stale()` | True when the Signal is unavailable or stale |
| `node.inputs.x:age()` | Input age in ticks |
| `node.inputs.x:read_events()` | Consumes and returns the pending Event records |
| `node.outputs.x:set(v)` | Stages a finite Signal value |
| `node.outputs.x:emit(event)` | Stages one Event |
| `node.params.name` | Typed parameter value for this tick |
| `node.params.name = v` | Queues a write to the node's own parameter |

Staged outputs commit only when the callback returns without error.
Parameter reads come from one snapshot per tick, so a write you make shows up
on a later tick.

### Events

An emitted event is `{event_type = n, timestamp_ns = t?, payload = {...}?}`
with at most four finite payload floats. Omit `timestamp_ns` to stamp the
current tick. Types: Trigger 1, NoteOn 2, NoteOff 3, CC 4, Impact 5,
PitchBend 6, Aftertouch 7.

A received record adds `source_id`, `sequence`, `timestamp_ns`,
`intra_frame_offset` and `payload_len`. MIDI In events carry
`{number, raw value, channel, status byte}` in the payload. MIDI Out accepts
NoteOn, NoteOff and CC with `payload = {number, value}` and uses its own
`channel` parameter.

```lua
for _, e in node.inputs.events:read_events() do
    if e.event_type == 2 then
        node.outputs.notes:emit({event_type = 2, timestamp_ns = e.timestamp_ns,
                                 payload = {e.payload[1] + 12, e.payload[2]}})
    end
end
```

Keep `timestamp_ns` when you transform an event so MIDI Out schedules it
against the original time; its `latency_ms` must cover the upstream delay.

### StateTree access

```lua
sentinel.subscribe("/sentinel/pipelines/Bounce/control_outputs/contact_count")
local v = sentinel.get("/sentinel/pipelines/Bounce/control_outputs/contact_count")
sentinel.set("/sentinel/pipelines/Blur/parameters/radius", 12)
sentinel.invoke("/sentinel/pipelines/Other/actions/reload")  -- reload another Script
```

Find action paths and their arguments with `sentinel_state action=list_actions`.

- `sentinel.get` reads only subscribed paths (up to 256). An unsubscribed or
  missing path returns nil and logs once. Subscribing every tick is cheap and
  idempotent; subscriptions last until reload.
- `sentinel.set` and `sentinel.invoke` queue work for the main thread and
  return false when the 1,024-entry queue is full. Several writes to one path
  in a frame collapse to the last one. A write reaches the target before its
  next cook, so read-then-write chains take up to two render frames.
- Script writes are tagged as automation writes and stay out of the undo
  history.
- Values are numbers, booleans or strings. Action arguments are plain JSON
  tables.

### Dynamic owned state

`state.register(relative, default)` creates a persisted value under the
script's own root (`state.root()`, which is `/sentinel/pipelines/<node>/state`),
for data whose shape is decided at run time, such as per-page settings. Read
and write it with `state.get(path)` and `state.set(path, value)` using the full
path (`state.root() .. "/key"`). These values save with the project
independently of manifest parameters.

`state.get/set` reach only the script's own root. Read another node's values
with `sentinel.subscribe` + `sentinel.get` and write them with `sentinel.set`.

Per-Script limits: 1,024 registered values, 1,024 queued state writes and 256
`sentinel.subscribe` paths. A large surface can reach these. Write only
values that changed. When a write is refused because the queue is full, keep
the latest value per path and retry a bounded number per tick. Do not mark a
refused write as sent. For big per-item data, pack it into fewer string
values instead of one path per item.

### Startup restore barrier

A script with heavy startup (registering hundreds of values, waiting for a
preset bank, building a surface) should not do it all in `init` or in a
1 ms display callback. Open a barrier and finish in `restore`:

```lua
local ready = false
function script.init(node)
    state.begin_restore(true)   -- keep registered values from the saved project
    -- register values, request banks, build the runtime ...
end
function script.restore(node)
    -- advance startup a bounded step; runs every 0.5 s with a 50 ms budget
    if not ready and everything_loaded() then
        state.complete_restore()
        ready = true
    end
end
```

Hold the barrier until every dependency is ready, not just the first one.
Keep `render_display` drawing nothing (`d.skip()`) until `ready` is true.

### Presets, OSC and Windows audio

These namespaces exist on current builds. Check `sentinel.d.luau` in the
project's `scripts/` folder for exact signatures.

| Namespace | Calls | Notes |
| --- | --- | --- |
| `preset` | `read_snapshot`, `save`, `recall`, `active`, `list`, `create`, `recall_confirmed`, `programmer` | Asynchronous. `save` takes explicit `paths` and `merge_existing`. Queue acceptance is not storage: poll `create`, `recall_confirmed` and `programmer` with the same request until a receipt arrives |
| `osc` | `listen(name, port, enabled)`, `receive(name, max?)`, `input_status(name)` | Up to 4 listeners per Script, 512 queued messages, 128 per `receive`. `listen` returning true means only that the request was accepted: check `input_status(name).healthy` and `last_error` |
| `windows_audio` | `define`, `status`, `set_volume`, `set_mute` | Up to 8 named targets; redefining a target needs a reload. Writes only confirm the request was queued. Read `status(name).sessions` for the real result. A missing app reports no session |

Call all of these from callbacks, never at the top level.

### Logging, time and packages

- `log.info(msg)`, `log.warn(msg)`, `log.error(msg)` write to the Sentinel log
  with the node id prefixed.
- `time.now()` is seconds since application start (high resolution).
- `require("name")` loads `scripts/packages/name.luau` or
  `scripts/packages/name/init.luau`. Call it inside `init` or a callback,
  never at the top level. Packages are compiled once per VM and must be
  stateless by convention. Aliases in `scripts/.luaurc` resolve within the
  project folder only:

  ```json
  {"aliases": {"show": "./show", "vendor": "./vendor/mylib/src"}}
  ```

  Then `require("@show/tempo")` loads `scripts/show/tempo.luau`.
- A required module is cached and shared by every file that requires it in
  that VM. Keep its top level free of host calls and mutable singletons. Have
  it return a factory, and pass bindings in:
  `require("@show/audio")({osc = osc, state = state, log = log})`. This also
  lets offline tests pass mocks.

The sandbox has no `os`, `debug`, filesystem or network access, and no
Roblox globals (`game`, `Instance`, `Vector3`).

## Control window and `ui`

Open the node's window with the header Window toggle or
`sentinel_pipeline action=open_window`. `render(node, ui)` records widgets
into it:

```lua
function script.render(node, ui)
    ui.text("title", "Drop control")
    if ui.button("fire", "Fire") then
        node.outputs.fire:emit({event_type = 1})
    end
    local changed, gain = ui.slider_float("gain", "Gain", node.params.gain, 0, 1)
    if changed then node.params.gain = gain end
end
```

Every widget takes a unique id first (no slash, up to 63 bytes) and returns
`(changed, value)` from the previous frame's input. Widgets: `text`, `button`,
`slider_float`, `slider_int`, `checkbox`, `combo` (one-based index, 1 to 32
labels), `input_text`, `same_line`, `separator`. Drawing: `line`, `rect`,
`rect_filled`, `circle`, `circle_filled`, `text_at`, `polyline`, with
positions relative to the window content origin and colors packed as
`0xAABBGGRR`. A frame holds at most 4,096 commands and 8,192 points.

Use `ui.get(id)` in `control_process` to consume a widget change when the
window is closed or you want the logic on the control tick.

Each widget is a tracked automation element at `Script: <node>/<id>`, so
`sentinel_ui click` and `sentinel_ui set` can drive it for proof.

## Budgets, errors and health

| Host parameter | Default | Range |
| --- | --- | --- |
| `tick_budget_us` | 500 | 100 to 2,000 |
| `render_budget_us` | 1,000 | 100 to 2,000 |
| `display_budget_us` | 1,000 | 100 to 2,000 |
| `memory_limit_mb` | 64 | 8 to 512 |
| `error_after_misses` | 8 | 1 to 1,024 |

A callback that runs past its budget is interrupted and counted as a miss.
Eight consecutive misses (by default) put the node into error; one successful
tick resets the streak. All Script nodes also share one aggregate per-tick
budget, and nodes that no longer fit are skipped and counted in `skipped`.
Render and display failures disable only that callback; control processing
continues.

Errors show the file and line in the node body, the Scripts panel and the
node header (ERR badge). A compile or manifest error on reload keeps the old
VM running and reports the failing line. Fix the file and it reloads.

Keep ticks cheap: avoid building large tables every tick, cap history
arrays, and skip work when inputs are stale.

### Performance lessons from large surfaces

- **Allocation churn is the usual cause of memory failures.** Thousands of
  short-lived small tables per second, or deep-cloning a big table for every
  encoder event (for example to build undo), will fill the 64 MB VM. Reuse
  buffers. Cap undo by entry count and bytes. Merge one continuous encoder turn
  into a single undo entry: close it after about 300 ms without input or when
  the target changes. A healthy full surface holds a few MB of heap in a soak.
- **Don't raise a budget to hide a slow path.** Move the work. Cache
  looked-up paths, ranges and memberships. Use indexed tables, not linear
  scans. Ask for deltas instead of full state. Coalesce continuous input.
- **Keep file and bank I/O off the musical tick.** A `preset.save` can cost
  over 1 ms. Run it from `render`, or spread it across ticks. A debounce
  limits how often a save runs, but not how much each save costs.
- **Spread multi-stage jobs across ticks in proportion to the work.** Don't
  service them only every Nth tick. Skip empty stages, merge rapid requests
  instead of dropping them, and commit only once a job is fully staged. In one
  case, moving from "service every 4th tick" to this pattern cut a preset
  recall from about 950 ms to about 130 ms.
- **Display misses are separate from control health.** When the display
  callback overruns its budget repeatedly, the display is disabled while
  `health` still reads 1. Watch the display miss counter too.

### Recovering an out-of-memory VM

The old VM needs memory to serialize, so reloading straight after an OOM loses
its state. First raise `memory_limit_mb` temporarily (for example to 128), and
set the hidden dev-only `enabled_in_error` to true. Then fix the script and
reload. The old VM can now hand over its snapshot. Afterwards, put both
settings back.

## Reload

Sentinel polls the script file every 30 render frames and reloads after two
agreeing observations of a new time and size. Invoke
`/sentinel/pipelines/<node>/actions/reload` (or the Reload button) to force
it. If the file goes missing, the node keeps its pins and parameters, shows
`file not found`, and recovers on Reload once the file is back.

## MCP workflow

1. Save the project, write `scripts/<name>.luau`.
2. `sentinel_pipeline action=create type=script name=Logic`.
3. `sentinel_state action=set path=/sentinel/pipelines/Logic/parameters/script_path value=scripts/<name>.luau`.
4. Check `sentinel_pipeline action=info` for `healthy`, the status message
   and the new pins.
5. Wire with `sentinel_graph add_link` by pin name, then
   `sentinel_graph layout_neighborhood` (or `auto_layout` on a fresh graph).
6. Prove behavior, not load state:
   - Signal outputs publish at
     `/sentinel/pipelines/<node>/control_outputs/<pin>`; read them with
     `sentinel_state get` and watch them change.
   - `sentinel_pipeline capture_events` with `pipeline_id`, `port_name` and
     `max_records` shows the records an Event pin actually sent.
   - Read the target parameter the script writes and screenshot the
     downstream output that parameter drives.
   - Drive window widgets with `sentinel_ui` and screenshot the window.
   - Check `tick_us_p99`, `budget_misses` and `errors`.
   - For a long-running script, soak it for 20 to 60 seconds with its window
     closed. Record `heap_kb`, `errors`, `budget_misses` and the display
     counters at the start and end. Compare the deltas, not lifetime totals.
   - Label input you injected (MCP, `sentinel_ui`, the virtual surface) as
     injected. It proves the logic, not the hardware.
   - MCP calls often return before the change lands. Poll until the target
     settles before you read it.

## Recipes

**Parameter link.** Subscribe to a control output, scale it, write a
parameter on another node:

```lua
local script = {manifest = {name = "Link", params = {
    {name = "source", type = "string", default = "/sentinel/pipelines/Audio/control_outputs/bass"},
    {name = "target", type = "string", default = "/sentinel/pipelines/Glow/parameters/intensity"},
    {name = "scale", type = "float", default = 1, min = 0, max = 4},
}}}
function script.control_process(node, ctx)
    sentinel.subscribe(node.params.source)
    local v = sentinel.get(node.params.source)
    if type(v) == "number" then sentinel.set(node.params.target, v * node.params.scale) end
end
return script
```

A plain `ref()` expression is simpler when the mapping is a formula. Use a
Script when the mapping needs state, timing, events or conditions.

**Clocked notes.** Accumulate `ctx.dt` into a phase and emit NoteOn, then
NoteOff on a later tick, into a MIDI Out node. Keep the held note in
`node.state` and carry it through `serialize`.

**Module events to MIDI.** A Module with `event_outputs` (for example
collision contacts) feeds a Script Event input; the script maps each contact
to a note, keeps the contact's `timestamp_ns`, and emits into MIDI Out.

## Gotchas

- Host calls at the top level of the file fail the manifest evaluation.
- `sentinel.get` returns nil until the path is subscribed.
- Output `set` values must be finite. A NaN raises an error.
- `node.state` persists only through `serialize`. If a script has no
  serializer, put its durable data in manifest parameters or `state.register`.
- `ui.combo` indexes are one-based. Act only when the returned `changed` flag
  is true. Acting on the value every frame re-applies it on every render.
- Read another node's current value (for example the start pose of a glide)
  before writing its new target. A queued write lands a frame or two later.
- A Display output accepts exactly one Push 2 Display consumer; it cannot feed
  Signal, Event or Video inputs.
- Script node writes are queued; never assume a write is visible in the same
  tick.
