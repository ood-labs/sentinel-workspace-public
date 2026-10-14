# Interaction Lab v2 - working plan

Working document for the rebuild (the shipped README is written at the end). Target: Sentinel
0.6.3. Built in `projects/interaction_lab_v2`; renamed to `interaction_lab` once proven.

## Direction

The lab is the example set agents learn Sentinel's interaction surface from. Three tiers on one
shared foundation, every station self-contained, every interaction with a visible consequence.
Look: technical instrument, refined rather than raw - graphite ground, IBM Plex Sans Condensed +
Plex Mono as SDF type, hairlines, amber only for selection / live readings, red only for broken.

## Foundation (`modules/_shared/ui/`)

| File | Role |
| --- | --- |
| `il_core.hlsli` | palette (on `plan_theme.hlsli`), rect + SDF helpers, coverage, ILCtx (ui scale from the smaller axis) |
| `il_type_metrics.hlsli` | GENERATED: atlas geometry + per-face advances (`tools/il_type.py atlas`) |
| `il_draw.hlsli` | the GPU draw list: layout pass records commands; text deferred and expanded by 64 threads; parallel batches (`dlBatch` / `dlSync` / `dlAt`) for record-heavy drawing |
| `il_ui.hlsli` | widgets on the draw list (pane, chip, segmented, slider, fader, toggle, knob, meter, XY pad authority, keycap, show pad) |
| `il_raster.hlsli` | generic tiled rasterizer (16x16 tiles, groupshared command bitmask, painter's order) |
| `il_events.hlsli` | ordered events consumed once by sequence; watermark reset; wheel notches; latches |
| `il_pane.hlsli` | splitters + per-pane views (zoom about cursor, frame, nice steps) |
| `il_text.hlsli` | per-pixel SDF text for program renderers that need a few labels |

Per module: `labels.txt` -> `_labels.generated.hlsli` (kerned label tables + host control rects)
via `tools/il_type.py labels <Module>`. Station pass shape: `reduce` (events -> durable state, 1
thread) -> `layout` (draw list, 64 threads) -> `raster` (generic). Offline compile timing:
`tools/fxc_check.py <Module> <pass>`.

## Findings (measured on this build)

- Per-pixel UI with many text call sites: 104 s compile. Draw list: layout 6.4 s at O3, 1.7 s with
  `compile_optimization: fast_compile` for the whole Kit.
- Kit GPU at 1579x1162: 1.13 ms (prefix-sum binning + 1-thread text) -> 0.24 ms at O3 (bitmask
  binning + 64-thread text expansion); 0.35 ms with fast_compile. Decision: UI modules use
  fast_compile (cold open 4x faster), program renderers stay O3.
- asfloat(small uint) is a denormal; FXC constant-folds it to a flushed literal. Store integer
  fields as exact float values (< 2^24); pack colours as 24-bit RGB (RGBA8 with a=255 is NaN).
- FXC compile time grows superlinearly with one big inlined body: put repeated widgets in
  data-driven loops (six pads through one call site halved layout compile time). Branchless
  dlPut/dlTextReq help too.
- Includes resolve from the module folder: shared headers include `../_shared/...`.
- An asset may live in `../_shared/type/` (the Kit loads the atlas from there).
- Shader cache keys on the main file: after include-only edits clear `.sentinel/shader_cache`
  and force_reload (the file watcher may also start a reload by itself).
- Host controls: `_ViewportControlState[i]` = flags (hover/active/held/lit), host-normalized
  value(/value2), rgba feedback, fade, label length, pad state, mode; labels in `_PanelLabels`.
  `pad` needs `mode` (radio needs `value`); `readout` binds no param; pads/faders need a param
  unless `viewport.panel: true`.
- `sentinel_ui viewport_control_drag` (begin/update/end) drives host controls through the real
  path; y is control-local top-to-bottom (the host converts to the Y-up value).
- Module event ports: `event_inputs` (max 4, `EventIn<N>` + `_EventIn<N>_Count`) and
  `event_outputs` (max 7, `AppendStructuredBuffer<GPUEventRecord> EventOut<N>` at u1..u7).
- The host re-delivers the event ring on every cook until newer events displace it: Touch's
  "stale repeats skipped" climbs by thousands a minute. Rule 1 (consume by sequence) is not
  theoretical - without it every click is applied ~60 times a second.
- Event encodings seen live: click = GESTURE code 1 phase END after BUTTON press/release;
  double-click = BUTTON phase DOUBLE then GESTURE code 2 (preceded by the first click's
  gesture); drag = GESTURE code 3 begin/update/end around BUTTON press/release; keys: letters
  1-26, digits 32-41, Space 51, Backspace 52; key events carry no position.
- `state_buffers` survive a module reload (Touch's ink kept its strokes through force_reload);
  plain persistent buffers that change size are recreated empty.
- Injection: `drag_at` phased = one drag update per call; unphased with `duration_ms` = dense
  updates (a 300 ms drag gave 19 ink points). `send_key` reaches the focused viewport. There is
  no wheel injection (no IPC command): wheel behaviour is exercised by hand.
- A capture issued right after an injected action can precede its processing; catch
  transients (ripples) with `record_pipeline mode=png_sequence` (~10 fps at 1579x1162).
- Translucent capsules bead at every joint of a polyline: fade a stroke's colour toward the
  background and draw it opaque.
- Thread-0 recording serialises each record's buffer reads; record-heavy layers (ink points,
  keys, steps) go in a parallel batch: thread 0 reserves the slots in painter's order, all 64
  threads fill them. Text works in batches too (glyph ranges reserved with a groupshared
  atomic); `dlAtSpan(b, i, k)` gives record i k consecutive slots. Touch's 36-row log: layout
  0.48 -> 0.31 ms.
- `param_gestures` (measured with real drags + readback): vec2 position = top-down normalized
  image coordinates; the grab test is a Euclidean circle of `radius` IN NORMALIZED UV (an
  ellipse on 16:9, 64 x 36 px at 1280x720 for radius 0.05: engine bug, filed as sentinel-bugs
  #174; Handles draws round rings of radius x height, the round part of the grab area, and
  lights them by the host's metric); left-drag puts the handle under the pointer
  (an off-centre grab jumps) and follows; right-drag turns `rotation_param` by horizontal
  motion (rightward = clockwise, ~0.25 deg per image px) without moving it; commit on release.
- A canvas panel STRETCHES a fixed-resolution output to the panel's shape (circles became
  ellipses). Canvas is for `follow_panel`; a fixed-frame program hit-tested in image
  coordinates belongs in a standard panel (letterboxed, Space+drag pans, plain wheel taken).
- An injected unphased `drag_at` blocks the main loop: pipelines process ~2 frames during it,
  so mid-drag output is frozen (live preview cannot be machine-verified; commits can). Phased
  drags never engage param_gestures. Real hands see NO live preview either (reported by hand on
  2026-10-02): see "Engine bug: param gestures show nothing until release" below.
- `ray_query` selection: the host fills `_ViewportPickRayOrigin/Direction.w` with the clicked
  image position (u, v); their xyz is a generic screen ray ((u, v, -1), +z), NOT the module's
  camera. Build the ray from the internal camera in the pick pass. The host asks only on a
  click (never on a drag); Shift-click adds; a miss clears.
- A click that the pick answers with a gizmo handle still selects that object: the host ignores
  `sub_element_id`, and has no "leave the selection alone" answer (an id no descriptor carries
  clears the selection). So a plain click on a handle narrows a multi-selection to the active.
- Escape during pointer capture never arrives as a key: the router cancels the capture and the
  module receives a CAPTURE event and a DRAG gesture, both phase 8 with flag CAPTURE_CANCEL (8),
  and `_ViewportButtons` reads 0 from then on. The release that follows is turned into a CLICK
  (the host selects whatever is under the pointer). `ilIsCancel` covers all of it.
- Declaring `right` in `input.pointer` hands RMB to the module and the host camera stops
  looking: camera modules keep RMB out of their pointer interests. Injected keys (W/A/S/D)
  fly the camera; injected RMB look cannot be driven (phased right-drags never register the
  button, unphased ones freeze the frame loop) - look is a hand test.
- `_ViewportCaptureFlags` read 0 during a captured drag and after its cancel: no use as a
  capture signal on 0.6.3. Event flags seen: SYNTHETIC 2 on injected input, HOST_CONSUMED 4 on
  presses/clicks the host also used, plus an undocumented 16.
- Never issue phased `drag_at` calls in parallel: the update can run before the begin's
  pending steps and the pair degrades into a click.
- Event record ABI (no shipped example uses Module event ports): `GPUEventRecord {uint
  event_type; float4 payload; uint sub_step; float sub_step_fraction; uint sub_step_count;}`
  appended to `EventOut<N>`; `GPUEventInputRecord {uint event_type; float4 payload; float
  intra_frame_offset; uint timestamp_lo, timestamp_hi;}` read from `EventIn<N>` (t110+N here),
  count in `_EventIn<N>_Count`. Like viewport events, an input record is handed over on more
  than one cook: carry a sequence number in the payload and apply each once.
- The graph is acyclic for events too: a Script cannot answer the module that fed it ("type
  mismatch or cycle detected"). The answer goes one node downstream, into a module that takes
  the first one's Program as a video input and its records as a data input (Pulse -> Pulse Bus
  -> Resonance). Module video input: `inputs: [{name, slot}]`, read in a pass as `source:
  "input:0"` (host-declared `_Tex0`); data input: `data_inputs: [{name, slot, schema}]`, read
  as `source: "data:0"`.
- `_Time` is per node (it accumulates from when that node started), so a stamp means nothing in
  another module's clock. Publish the writer's clock in its data (Pulse's `W_HEAD.d`) and time
  everything downstream against that. The cbuffer also carries `_DeltaTime`, `_Mouse`, `_Frame`,
  `_BlendAmount`.
- An Event output nobody consumes fills to capacity (`capture_events` shows the overflow).
- Script: received `timestamp_ns` is host monotonic ns on its own epoch (not `ctx.time`); keep it
  on the notes you derive so MIDI Out schedules against the strike. MIDI Out `late_ms` sat at
  ~1.0 ms with `latency_ms` 40 and 60 alike: scheduler jitter, not a budget shortfall, so 40
  stays. Pulse strike -> Script -> Resonance echo measures 18-31 ms (25 smoothed) at 60 fps.
- Script control window: draw coordinates are window-content pixels; widgets (pads) stack from
  the top, so drawing below them starts at a fixed offset. Pads are tracked automation elements
  (`Script: <node>/<id>`): `sentinel_ui click` drives them through `ui.next_edge()` and
  `sentinel_screenshot element="Script: <node>"` captures the window alone.
- Script window layout: widgets, grid cells AND drawn text scale with the UI (~1.45 here), draw
  positions are raw pixels, and no call reports the scale (`ui.text`/`separator`/`same_line`
  return `(false, 0)`). So drawn content and widgets never share a row, and drawn text never sits
  beside other drawn text: draw a band first, then a spacer grid of the same height in widget
  units (exact at 100%, a gap above it). `ui.grid_cell` is 1-based; a pad in a grid cell takes
  the cell's width; a phased `drag_at` begin/end holds a momentary pad (proven on Gate).
- Modules have no Signal pins (no `signal_inputs` in the binary). A Script's Signal outputs are
  control outputs; a module follows one through a `ref()` expression on a parameter, evaluated
  once per frame - the value can be up to one control tick (4 ms) old, visible as a slight
  wobble on a slope in the Scope.
- A module's `_Time` survives `force_reload`, and so do same-size persistent buffers (the Scope
  kept its held trace and ring through four reloads). A `follow_panel` canvas reaches its buffer
  passes' `_Resolution` a few frames after the panel opens: the first capture can show a
  1280x720 layout in a larger image.
- `drag_at` cannot carry modifiers (`key: shift` is ignored): every Shift gesture needs a plain
  path too (the Scope's 1 / 2 keys choose the cursor a drag places).
- The shared rasterizer tests every command's box per tile, so its cost scales with the command
  count, empty batch slots included: Scope traces at 192 columns x 13 slots cost 1.34 ms raster at
  1579x1162, at 128 columns 0.93 ms.
- A cursor attached to data time scrolls out of a rolling trace within one window (it read 0 by
  the time a readback arrived): placing a cursor holds the trace, as stopping a scope does.
- `panel_feedback` is the one event back-edge the graph accepts: Desk.panel -> Script ->
  Desk.panel_feedback links without complaint (phage_stage wires the same loop), while any other
  event cycle is refused.
- Panel colour feedback (12) takes 0..1 per channel; 0..255 saturates every pad to 0xFFFFFFFF.
  The host packs it into `_ViewportControlState[i].rgba` (RGBA8, R in the low byte) and keeps
  lit, state, fade, value and `panel.label` text until told otherwise, across a Desk reload.
- Script `log.info` lands in sentinel.log as `[Script <id>] ...`, flushed some seconds late. A
  one-line cue log on every transition is how timing gets proven: injected actions take seconds to
  round-trip, so a 3 s fade finished before a capture could see it (a 10 s fade was caught at
  mix 0.662), and two GO presses only landed inside one fade when logged 67 ms apart.
- An unphased `drag_at` that barely moves, with `duration_ms`, is a held press: 1200 ms held the
  BLACKOUT pad past its 0.65 s guard.

- Only `state_buffers` reach the project file, node presets and undo payloads; `persistent: true`
  alone survives a reload and nothing else. The first `max_elements` records are saved; the
  records after them are working state the host never restores.
- Keep the event watermark (and drag state, view, undo snapshot) OUTSIDE the saved range: a
  preset recall or undo restores the saved records, and a restored watermark replays every event
  still in the ring. Proven on Touch: recall brought back 4 strokes while the 5th stroke's events,
  still in the ring, stayed unapplied (watermark in record 1027, past the 1027 saved). Curve Desk
  keeps its keys in records 0-48 and everything else after them.
- Presets select a durable buffer as `state:<buffer>` (group "State" takes them all); a state-only
  preset recalls as `applied: [durable_state, state:<buffer>]` and leaves every parameter alone.
- A drag GESTURE begins where the drag was recognised, past the threshold - not at the press. A
  pen that starts at the begin loses its first pixels (190 px on an injected jump): take the
  start from the left BUTTON press (Touch). A stroke that leaves the surface should lift at the
  edge crossing; clamping the point makes it crawl along the border.
- `drag_at button=2` produces middle-button DRAG gestures (`middle` in `input.pointer`,
  `middle_drag` in bindings). The keyboard vocabulary has no Delete key: Backspace removes.
- Readbacks lag injected input too: a data-port read straight after a key can show the state
  before it (Curve Desk's Z looked broken until read again ~2 s later). Wait ~2 s, then read.
- `fast_compile` behaves like /Od: Curve Desk layout 3.5 s against 19.7 s at /O3. `uniform` is a
  reserved HLSL word (a function argument named that fails to compile). `tools/il_type.py` needs scipy only
  for `atlas`; `labels` runs without it.

- `dlBatch(count, tag)` hands out batch ids in RESERVATION order; `dlGetBatch(id)` takes that index,
  not the tag. Reserve in painter's order and fetch by the order reserved (Path Desk reserves the
  comb, then the paths, then the strip).
- **Module passes run in REVERSE manifest order** (0.6.3, measured with a probe module, since
  deleted). Four passes each took a ticket from one atomic counter: listed delta, alpha, charlie,
  bravo, they took tickets bravo 7777, charlie 7778, alpha 7779, delta 7780. A declared buffer
  input does not reorder them: a reader listed after its writer ran before it, and one listed
  before it ran after it. This explains station 08's pencil (a clear pass listed before the
  stamping pass ran after it and wiped every stamp; a counter the plan pass wrote was read a cook
  stale). Consequences:
  - A time-dependent chain still works, one cook late per stage: reduce -> sample -> layout ->
    raster shows input three cooks (~50 ms) late.
  - A `time_dependent: false` chain goes STALE. Dirtiness flows only along execution order within a
    cook. After a parameter change p3, p2 and p1 each ran once (p3 and p2 copying old data) and the
    node went idle with the old value at the end. Listed in reverse, the same chain carried the new
    value in one cook and then slept.
  - Robust on any order: one-pass nodes, and `time_dependent: false` only on passes that read no
    other pass of the same node (a reducer reading events and its own buffer; a single-pass
    consumer reading `data:N`). Station 09 is built this way. Keep a pass's working state inside its
    own output buffer (the Plotter's pencil keeps its own cook number and stamps
    `(cook << 8 | coverage)` with a compare-exchange loop, so nothing is cleared).
- FXC folds `isnan()` to false without /Gis (a warning says so): test the exponent bits instead,
  `(asuint(v) & 0x7F800000) == 0x7F800000`.
- Pass inputs bind in list order. A `data:N` input at position k is a buffer the shader declares
  itself (`StructuredBuffer<float4> W : register(tk)`); a texture at position k is the
  host-declared `_Tex<k>`; a structured-buffer output is `u0`.
- A persistent texture buffer (`format: RGBA16F, persistent: true`) is read-modify-written in one
  pass by listing it as both an input and the output: read `_Tex<k>.Load`, write `OutputUAV`.
  The Plotter's sheet accumulates and fades ink this way.
- Readback lag reaches well past 2 s for captures as well as data ports: an immediate capture
  after an edit showed the state before it. Confirm with `capture_data_port`, read again if stale.
- Injected pointer and keys go to the FRONT tab of a dock, and the user may switch tabs while you
  work (Curve Desk, Desk and Pulse each caught stray clicks). Call `open_window` before each
  input cluster, never in parallel with the input; `openAndFocusPipelineWindow` log lines
  without `AutomationBridge` are the user's own clicks.
- A consumer can talk back to its editor through expressions: Plotter control outputs drive Path
  Desk parameters through `ref()`. Expressions are not links, so this back edge is accepted where
  a data or event cycle is refused.

- What wakes a `time_dependent: false` pass / an `execution: on_dirty` node (measured on station 09):
  a parameter change, a reload, the panel size, a durable-state restore (a state-only preset recall
  ran the reducer exactly once), an upstream data generation change, and viewport input - every
  event, pointer moves included (an injected hover dirtied the reducer every frame it lasted). The
  profile shows a skipped pass as `executed: false`; an idle on_dirty node as `cook_hz 0`,
  `healthy_idle: true`, `idle_reason: on_dirty`.
- A data port's generation moves each time its writing pass EXECUTES, whatever it wrote: a consumer
  cannot be shielded from an upstream pass that ran and changed nothing (Relief renders while the
  pointer moves over the Ramp Desk). Publish a content revision (the Palette carries a hash of its
  stops: equal revision, equal palette) so a consumer with real work can skip it. Engine wish: a
  pass able to say "unchanged", or content-compared generations for small buffers.
- Hover belongs in the layout pass, read from `_ViewportPointerPosition` (any pass, any thread),
  never written into a buffer that is published.
- A per-pixel swatch pass writing a `scale: 1.0` texture, shown through `DL_IMAGE` at uv = rect /
  extent, gives a draw-list UI exact colour fields (each pixel sampled at its own centre). A colour
  instrument draws them exact; the theme's inset toning is for previews, not for colour readings.
- `_labels.generated.hlsli` must be included BEFORE `il_text.hlsli` (it defines IL_LABEL_COUNT,
  which turns the label functions on). `out` is a reserved HLSL word. FXC warns "potentially
  uninitialized" on a function with an early return and an out parameter: give it one exit.
- **`matrix` is a reserved HLSL word** (a type, like `vector`): a struct field named `matrix` is a syntax error. Likewise `out` (above).
- **FXC evaluates both sides of `?:`**: `i < 4 ? S[a][i] : S[b][i - 4]` with a LITERAL `i` (an unrolled or analysed loop) trips "array index out of bounds" on the side not taken. Index so neither side can overrun - `S[a + i / 4][i % 4]` with the records adjacent.
- **A dynamic write into a float4 component inside a `[loop]`** (`rec[head % 4] = v`) plus a dynamically indexed local array made FXC demand an unroll it could not do ("can't unroll loops marked with loop attribute"). Write with a vector select instead: `bool4 at = uint4(0,1,2,3) == (head % 4).xxxx; S[r] = at ? v.xxxx : S[r];`.
- **A state buffer that is not a data output cannot be read back over MCP** (`capture_data_port` needs a port; `sentinel_viewport state` gives sizes, not values). Prove such a module through its control outputs (StateTree reads are immediate) and its own canvas, which prints every number it holds.
- **Expressions survive a module force_reload** (same parameter set): seven `ref()` drivers were still registered after reloading the Bloom.

- **A label longer than 63 characters aborts `il_type.py labels`**, and the layout pass then fails on
  the missing `_labels.generated.hlsli`. `dlLabelFit` draws nothing when a label does not fit its width:
  split a long caption over two labels rather than lengthening one.
- **Compile time grows with the call sites of a heavy function** (FXC inlines every call): the
  Timeline's layout took 128 s and its reducer 88 s at /O3 with `tlValue` (a key loop plus the ease
  shapes) called from a dozen places. Evaluate at ONE call site into a table - the layout fills a
  groupshared job table cooperatively (every value it draws), the reducer fills `g_now[20]` once per
  event, `frameValues` runs once after the events behind reframe flags - and keep shape functions
  closed form (the ease is `u^a / (u^a + (1 - u)^b)`, no bisection): 71 s and 37 s at /O3, ~8 s at
  /Od. `fxc_check.py --Od` predicts the live (`fast_compile`) time; /O3 runs about 5x longer.
- **A click never arrives as a drag**: a press released under the drag threshold is a click event
  only. Every target documented as "click or drag" needs both handlers (the ruler scrubbed only on
  a drag until it got a click case).
- **A channel's last key has no segment, but it lends its mode to the segment appended after it**:
  a default that ends on a hold makes the first key a user adds jump instead of move. End every
  default channel on an ease.
- **Motion blur over few samples steps** (8 hard copies of an edge). Evaluate a fixed table of
  instants once per group into groupshared and let each pixel take one instant per stratum, offset
  by interleaved gradient noise: the steps become a fine dither at the same cost.
- **One node's GPU time without the whole profile**: `proof_bundle` writes `graph_profile.json`
  (the profile under `data`); read the node from the file instead of pulling 20 nodes into context.
- **Long bash heredocs got truncated** mid-edit. Write edit scripts to the scratchpad and run them,
  asserting each replacement matches exactly once.

- **FXC's `fmod(x, y)` is `frac(x / y) * y`: never use it (or `t - n * floor(t / n)`) for whole-number
  arithmetic.** By step ~3,400 the quotient is a few 1e-5 out, a 3.99997 truncates to 3, and a lane
  played its previous step a second time in the next step's place (A4: three hits a cycle instead of
  two). The grid read the step records and looked right; only the event stream and the tape showed
  it. Indices, parity, wraps and countdowns go through `uint` `%` and `/` (whole-number floats are
  exact below 2^24). The shared number formatter had the same flaw - a digit count from
  `log10 + 1e-4` gives 9998 and 9999 five digits, and `floor(x / 10 + 1e-5)` loses its guard above
  ~1,000 - and is now integer throughout, 10^e built from e's bits (a `static const` array becomes
  per-thread indexable registers at /Od; a loop warns X3557 wherever it folds to a constant).
- **An event input takes ONE link**: a second `add_link` into it replaces the first (outputs fan out).
  Two note streams into one MIDI Out need a merge Script (MIDI Merge re-emits every record unchanged,
  timestamps kept).
- **Musical events are sent ahead, never placed on frames**: a 16.7 ms frame is a tenth of a
  sixteenth at 96 bpm. The reducer sends each hit 100 ms early with "due in" over the window
  [sent, now + lookahead), advanced by whole cooks (stop and restart reset `sent` to now); a Script
  stamps `timestamp_ns + due in`; MIDI Out schedules it: +-0.6 ms of the grid.
- **`capture_events` reads GPU EventOut ports and Script ports alike**, newest records first with host
  timestamps: count hits per lane per window against the pattern - that is what caught the double
  steps - and check stamps against the grid.
- **A readout of a rate should count, not smooth**: an average of `played / dt` swings +-50 % on hits
  that clump on the beat and drifts with the tick rate (the Pattern Bus showed 11.2 notes/s against
  14.1 measured). Hits in the last bar from the history, notes in the last 4 s from a ring: steady
  and true.
- **`dlAtSpan` clears and resets the slot cursor**: call it once per item; a second call mid-item
  wipes what the item already drew.
- **The file watcher reloads every module that includes a changed `.hlsli`**: an edit to
  `_shared/ui/` queues all twenty lab modules (offline `fxc_check` timings taken meanwhile run slow).
  A Script reloads when its `.luau` is saved (`control_outputs/reloads` counts).
- **MIDI Out's `record` writes `<project>/.sentinel/midi-records/midi.jsonl`** (found at the wrap-up;
  first reported missing because we looked beside the node): one JSON line per message with
  `scheduled_ns`, `actual_ns`, `submitted_ns`, `origin_ns`, `type`, `channel`, `number`, `value` -
  `actual_ns - scheduled_ns` is the lateness of every note. `capture_events` on the bus remains
  the way to check what was sent against the pattern.
- **Injected input strictly one call at a time**: drags issued in parallel landed here twice, but
  nothing orders them.

- **An enum option labelled with a bare numeral catches numeric writes**: a number written to an
  enum matches an option LABEL before an index. `rays` had options "1" and "4", so writing 1 chose
  the option labelled "1" - index 0 - and the Hero rung measured exactly like one ray. Label
  options with words ("One ray", "Four rays (capture only)").
- **Module outputs are displayed exactly as written** - nothing encodes them on the way out. The
  instrument palette is display values (PT_FIELD 0.0055 shows as RGB 1, 1, 2); a renderer that
  works in linear light writes `pow(tonemap(lin), 1 / 2.2)`; colours that must match across an
  editor and its program (the Score's cards) are stored as display values and taken to linear
  (`pow 2.2`) only to composite.
- **FXC evaluates both sides of `?:`**: a call on each side compiles and runs both (a function
  holding a loop doubles the compile time and warns X3551 / X3557), and a "none" sentinel on one
  side still indexes a table at compile time (X3504, out of bounds). Calls and sentinels go in
  `if` / `else`.
- **A runtime loop count is a constant bound with an early break**:
  `for (uint i = 0u; i < 64u; i++) { if (i >= steps) break; ... }`. A function needed twice
  compiles once inside a two-iteration loop: the Score's layout went from 21 - 25 s to 14.6 s
  (/Od) by looping its fields, segmented rows, the time pair, both cards and the readouts.
- **GPU timestamps arrive 10 - 14 frames late**: straight after a quality change the profile still
  reports the old rung. Settle (take a capture) before `profile` or `proof_bundle`, and read the
  sample age.
- **`camera_fov` is the VERTICAL field of view in degrees**, proven by registration: the Score's
  schematic VIEW, projected with a vertical fov, lies on the Program's render within a pixel.
- **A live value outlives a changed manifest default**: after `reflect_steps`' default went from 0
  to 40 and the module reloaded, the node kept 0. Set the live value too (or recall a preset)
  whenever a default changes.
- **Shadow rays should not see the floor**: marched from a floor point toward a low sun, the
  floor's own plane streaked the shadows. The field skips the floor for shadow rays (nothing lies
  under it), and the improved soft-shadow estimate, started a per-pixel distance along the ray,
  turns what banding remains into grain.
- **Light the room you built**: a physically low dusk sun put the whole floor in the 6 m walls'
  shadow - correct and useless. The dusk sun comes in through the open end of the hall instead,
  raking down the nave.

- **Scene Group membership is geometric and live**: a node lying inside the frame belongs to the
  group, one moved out leaves it (the Synth sat inside 04's frame until moved). Frames sized from
  the node bounds `sentinel_graph get` reports (plus 24 units) did NOT contain the drawn nodes at a
  working zoom (~0.4): the user had to extend every station frame 70 - 170 units downward. Size
  frames generously (a module node needs ~325 units below its top at that zoom) and check them at
  the zoom people actually use.
- **What a Scene Group cannot expose**: Button parameters ("Button parameters cannot be exposed")
  and transient ones (MIDI Out's `device`). A Script's parameters carry no display label (the
  Luau `Parameter` type has none), so their group rows read as raw names (`fade_s`, `gate_ms`).
- **Group Properties rows are sectioned by source**: a module parameter under its manifest group,
  a Script parameter under the Script's manifest name ("Control Atoms"), MIDI Out under "MIDI
  Out"; widget paths read `Properties/Exposed Parameters/<section>/##<exposed name>`. A write to
  `/sentinel/groups/<id>/parameters/<name>` flows to the member (and through a Script: the Desk
  group's master reached the Stage as 0.55 via the Cue Brain).
- **Driving the open Properties with `sentinel_ui set`**: an int row needs `widget_type: slider`
  (otherwise it is treated as a combo and silently ignored); an enum row ignores `set` entirely -
  click it open (`click` with `method: mouse`) and click the option (popup rows ~30 px apart, the
  first ~51 px below the combo's centre); a whole-number float written as `3.0` arrived as 0 - send
  integers or non-round values. A path-based `click` on a graph node does not select it; a
  coordinate click on its title bar does, once a `focus` animation has finished.
- **`set_node_geometry` did not stick on a MIDI Out node** (it snapped back to the old position a
  frame later); `move_nodes` with a delta worked for every node.
- **A node preset recalled onto expression-driven parameters keeps the expressions** (they win the
  next frame): the Program's camera frame contract is inert while the Score drives the camera and
  takes over once the six camera expressions are cleared.

- **The release tooling predates what this lab needs**: `tools/promote-public.ps1` copies a
  project's README* / LICENSE* files, its `assets`, `cues`, `images` and `tools` folders, its
  active modules and `modules/_shared` - so `scripts/` (the five Luau Scripts) and `PLAN.md` are
  not promoted. `tools/validate-official-examples.ps1` follows only manifest `shader:` entries and
  `#include`, so the type atlas every module loads as a texture (`_shared/type/il_type.png`) and
  any font licence but Scientifica's read as unused shared files. A module that declares manifest
  `controls:` needs `_ui.generated.hlsli` stamped `manifest-sha256:`; `tools/il_type.py` now writes
  the host controls there (the stamp is the validator's hash: UTF-8, line endings folded to LF).

## Engine bug: param gestures show nothing until release (0.6.3, open)

Filed 2026-10-03 as sentinel-bugs #173. Reported by hand on 2026-10-02 and measured the same day;
re-measured 2026-10-03 with real drags (the parameter held for the whole of every hold and
changed at the first poll after button-up, eight drags out of eight). Station 02 (Handles) is the test case:
its manifest is the documented `viewport.param_gestures` example (`interactions: [events]`,
`input: { pointer: [left, right], gestures: [drag] }`, one vec2 position and one float rotation
parameter per handle, radius 0.05), and it should go live with no change to the station.

**Contract** (`knowledge/module-pipeline.md`, Param gestures): "Edits preview live and commit once
on release as one undo entry."

**Observed on 0.6.3**
1. No preview. While the host holds a param gesture the parameter does not change, so the picture
   stands still for the whole drag; on release the edit lands at once, as one undo entry
   (blade_rot -58 -> -41.45 for a +77 client px right-drag at 120.5 % zoom: 16.55 deg for 64 image
   px; an earlier run gave 16.0).
2. The module is starved while the host holds the drag. A temporary diagnostic reducer (not part
   of the station) counted what reached the module during a host-owned right-drag: no button
   press, no release, no drag gesture, one pointer move (onto the start point). `_ViewportButtons`
   read 0 on every cook, and `_ViewportPointerPosition` stayed at the press point after the drag
   ended. So no module can draw its own preview, and Handles' hover / held feedback freezes at the
   press.
3. Router state decides who gets a drag. With the module still holding the stale press from 4,
   the same unphased right-drag went to the module instead: it received the whole drag (press,
   release, drag begin, 188 drag updates, drag end), its reducer previewed the turn for 71 cooks -
   and the host committed no rotation. A module-side preview therefore cannot be paired with the
   host's commit.
4. After `force_reload` (focus lost), an unphased left-drag delivered its press to the module (no
   HOST_CONSUMED flag) and nothing after it: `_ViewportButtons` stayed at 1, a phantom press, until
   the next input. The host had engaged that drag and held it open: the blade still read 0.47
   right after the drag, and sat at the drag's end point (0.520, 0.497) only after the next drag.
5. `_Mouse` - still in `ProjectGlobals`, between `_Resolution` and `_Frame`, ahead of the viewport
   block (`tools/fxc_check.py` now declares it) - read all zeros in this events module throughout.

**Expected** (what makes the station pass)
- The position and rotation parameters preview while the button is held - the handle follows the
  pointer on a left-drag and turns on a right-drag - then commit once on release.
- The module keeps its pointer snapshot (and ideally its events, flagged `HOST_CONSUMED`) while
  the host holds a drag, so hover / held feedback can be drawn; or the active gesture is exposed
  to the module (which handle, which button, its phase).

**Repro**
- By hand: open `projects/interaction_lab`, focus the Handles preview, left-drag the Blade ring
  (the long bar near the centre): nothing moves until release, then the blade jumps under the
  pointer. Right-drag it: no turn until release.
- MCP: a phased `drag_at` never engages param gestures (the module gets the drag instead), so the
  host's path is reachable only with an unphased `drag_at`, which blocks the main loop (~2
  pipeline frames run during it): mid-drag output cannot be captured, but a parameter read before
  and after shows one change, on release.

## Engine bug: the param-gesture grab area is an ellipse (0.6.3, open)

Filed 2026-10-03 as sentinel-bugs #174. The grab test is `length(pointerUv - positionUv) <=
radius` in normalized coordinates, so on 1280x720 a radius of 0.05 grabs within 64 px left and
right of the position but only 36 px up and down. Measured with left-drags pressed at known
offsets from the Blade (unphased `drag_at`, which takes the host's path), reading `blade_pos`
back: 50 and 60 px right grabbed, 70 px did not; 30 and 34 px below grabbed, 40 and 50 px did not.
Handles draws round rings of radius x height (everything inside one grabs) and lights them by the
host's metric (`hdHitDist`), so until the fix a ring also lights from the strip beside it.
Expected: a round grab area, the radius in image heights; `hdHitDist` then scales x by the aspect
and ring and grab area coincide.

## Stations

| # | Station | Tier | Status |
| --- | --- | --- | --- |
| 00 | Kit | kit | built, proven (host controls round trip, pad AGREE); re-verified after batches. Widget States pane added: when the extent has the height, TYPE and PALETTE take their content heights and the pane takes the rest (at 16:9 the proven two-pane layout is unchanged - captured at 1280x720). Chip, slider, knob and toggle in rest / hot / down / on (a short rule where a widget has no such state), then a segmented row, a meter with a real peak hold (KitState[2].z, falling 0.4 a second: captured six frames after a 0.96 -> 0.30 drop with the peak still on the top segment), keycaps and a value row - all on the Kit's own amount, level and mode (one capture_at at 0.75 / 0.96 / A moved every specimen). Layout compile 2.2 -> 4.9 s (/Od) |
| 01 | Touch | basic | built, proven with real input: click, drag, double-click, keys 1-4, Space latch both ways, Backspace undo, C clear; durability through reload, save and preset recall (no replay: watermark outside the saved range); strokes start at the press, lift at the surface edge and restart on re-entry; 0.83 ms GPU at 1579x1162. Wheel: by hand |
| 02 | Handles | basic | built, proven: lamp + 3 blocks, 8 ordinary params; round grab rings, lit by the host's own grab test (its grab area is an ellipse on 16:9 - engine bug #174, section above); hover/held states; move + rotate commits; 0.49 ms GPU. Live mid-drag preview: none on 0.6.3 - engine bug #173 (section above), and this station is its test case |
| 03 | Still Life | basic | built, proven with real input: click select, Shift add, miss clears; body slide (moves the whole selection), arrow move, ring turn, Esc cancel; durable through reload; overlay registered from a flown viewpoint (W/D); frame contract + 4-rung quality ladder. GPU (march pass, Live = 1): Draft 0.41, Beauty 1.11, Hero 3.9 (10.9 ms, capture only); outline 0.20 ms with two selected. RMB look: by hand |
| 04 | Pulse Bus | basic | built, proven: Pulse (GPU physics) appends one Impact per strike -> Pulse Bus Script picks note + velocity -> MIDI Out (GS Wavetable, ~21 msg/s, late ~1 ms) and echoes each played note to Resonance (video + data + event inputs) on Pulse's clock: round trip 25 ms, every echo linked to its strike in the scope. Script window: scale pads + Mute proven by real clicks (retune relabels all 12 bars; mute leaves strikes unlinked, hollow on the curve). GPU: Pulse 0.82, Resonance 0.45 ms; Script tick 59 us (p99 93) |
| 05 | Control Atoms + Scope | basic | built, proven: Atoms Script makes LFO, ADSR, S&H and slew on the 240 Hz clock (7 us/tick) as Signal outputs; its window is a desk - knob drag (rate 0.5 -> 2.09 Hz), shape radio pads, LFO-gate toggle and a held Gate pad (env reached sustain 0.55, released to 0) - over live LFO / ADSR / slew-response previews. Scope plots the five outputs through ref() expressions: cursors (drag places and holds, 1 / 2 choose A / B, B-A per lane, "apart"), Space hold / resume, Z / X zoom 4 -> 8 -> 4 s, C clear, all with real input; desk S&H knob 2 -> 4.65 Hz shows in the Scope (slew visibly chasing). GPU: Scope 1.10 ms at 1579x1162 (raster 0.93). Wheel zoom: by hand |
| 06 | Desk | basic | built, proven with real input: Desk (panel: 2 readouts, 11 pads, 2 faders over a Stage preview) -> Cue Brain Script -> panel_feedback. Cue pad makes it next; GO crossfades (caught mid-fade: mix 0.662, FADING chip, progress on readout / GO / target pad / stack); GO during a fade completes it (live in the same tick); BACK fades to the previous cue, BACK during a fade reverses it from where it is; FADE fader -> 10 s, MASTER fader -> Stage master 0.496; guarded blackout: tap ignored (released at 0.01 s), 1.2 s hold -> on at 0.65 s (stage dark, red chip), tap restores. Lit / selected / fading / colour / value feedback and panel.label readouts, re-sent every 1.5 s; pad colours are the looks' own key colours. Brain window monitors the stack, the eased crossfade with its playhead, and the hold. GPU: Desk 0.17 ms, Stage 0.17 ms at 1280x720; Brain tick 32 us (p99 56) |
| 07 | Curve Desk | instrument | built, proven with real input: three channels of a bouncing ball (travel, height, squash) as bezier keys over one loop, with a spacing chart that draws the ball on twos. Drag a key (snaps to frames, neighbours clamp), drag a handle (aligned mirror; B breaks / re-aligns), box select, Backspace removes, double-click a curve inserts, 1 / 2 / 3 step / linear / bezier, A auto handles (flat at extremes, Fritsch-Carlson limited), arrows nudge, F frame, middle-drag pan, ruler and chart scrub (frame-snapped), Space play, R reset with Z bringing the edit back, Z undo / redo, channel rows hide. Keys are a 49-record `state_buffer` (working state after them); presets "Curves · Bounce" and "Curves · Soft contacts" are state-only, proven by recall. Publishes Curves (256 samples) and travel / height / squash / phase control outputs (height read through StateTree). GPU 0.91 ms at 1579x1162 (layout 0.39, raster 0.48). Wheel zoom, Shift-click: by hand |
| 08 | Path Desk + Plotter | instrument | built, proven with real input: up to six pen paths (ridge, sun, sea, gull by default) as bezier anchors on a plotter's sheet, read as curvature: a comb on the active path, and a radius strip along the whole plot with the plotter's playhead. Pen tool (P): click places a corner, drag places a smooth anchor, clicking an open end carries on drawing it, clicking the first anchor closes the path, Enter finishes it open, Esc stops. Edit mode: drag anchors (a selection moves together) and handles (aligned turns its twin, B breaks or re-aligns: broken handles proven independent), double-click an anchor for corner / smooth, double-click a curve to split it exactly (de Casteljau: sea length unchanged at 1116 px), box select, Backspace deletes (an emptied path is removed), 1 / 2 / B, arrows nudge, C closes / opens the active path, a row click selects its path, the pen chip cycles its ink, K comb, O shortest plot order (multi-start greedy with the return home counted: pen-up travel 3267 -> 2681 px), R reset with Z bringing the edit back, Z undo / redo. Anchors are a 127-record `state_buffer`. Publishes Path: 1024 arc-length samples (x, y, heading, curvature), anchors with turn angles, and per-path headers. The Plotter plans speed the way CNC firmware does (curvature speed limit, at rest at path ends, forward / backward acceleration passes, minimum-jerk pen-up moves). Ink density comes from speed and lands on a persistent RGBA16F sheet: corners pool, slow lines are darker and wider, old ink fades with a half-life. A pencil underdrawing shows an edit at once, before the pen gets there (proven: after R the default gull, sun and sea show in pencil while the edited ink fades). The Plotter's pen comes back to the Path Desk through `ref()` (a marker on the stage, a playhead on the strip). GPU: Path Desk 1.46 ms at 1579x1162 (layout 0.64, raster 0.78); Plotter 0.63 ms at 1280x720 (plan 0.43, one thread) |
| 09 | Ramp Desk + Relief | instrument | built, proven with real input: up to 12 colour stops on a ramp, each coloured on an OKLCH plane (lightness up, chroma across, hatched where sRGB ends) and a hue strip, blended in OKLab / OKLCH / sRGB (`Blend` param) into 256 gamut-mapped entries published as `Palette` (`_shared/palette.hlsli`: head with a content revision hash, stops, entries). Lanes on the ramp's own t axis: the same stops blended three ways, the ramp seen as lightness and with each dichromacy (Machado 2009), and lightness, chroma (red runs where sRGB clipped) and step curves against the mean step; a hover probe reads t / L / C / h. Click the ramp adds a stop in the colour already there (L 0.360 between 0.27 and 0.45), drag moves (0.30 -> 0.35), down and off removes, diamond drag leans the blend (m 0.80), double-click evens it (revision returned to the same hash), plane (L 0.50, C 0.150) and hue (30.0) drags, Tab, arrows (one entry = 1/255), F flips (mirrored exactly), E spaces evenly, Backspace, R cycles four built-ins, Z undo. A stop asking for more chroma than sRGB shows keeps its ask and is shown brought in (Thermal stop 3: 0.180 asked, 0.175 shown, in red). Presets `Palette · Hypsometric / Ink / Thermal / Diverging` are state-only, proven by recall. Relief: `execution: on_dirty`, ONE `time_dependent: false` pass - a hypsometric island plate (gradient-noise terrain with a shelf and a deep sea, palette tints over +-span, hill shading, contours, coastline, legend reading the palette back in metres); seeds 3 / 7 / 12 / 21 all presentable. Idle proof: the desk's reducer `executed: false` and the Palette generation still while the canvas cooks; Relief `cook_hz 0`, `idle_reason: on_dirty`; an edit, a parameter or a preset recall renders it once. GPU: Ramp Desk 0.91 ms at 1579x1162 (swatch 0.09, layout 0.20, raster 0.63; reducer only on input), Relief 1.09 ms per render, 0 when idle |
| 10 | Patch Bay + Bloom | instrument | built, proven with real input: five sources (sine, triangle, ramp, sample and hold, smooth drift; each phase integrated from its rate parameter) and an external `input`, patched by cables into six outputs, each resting on its base and swung by every cable into it, bipolar (out = base + sum depth * (2 src - 1) / 2, clamped; a negative depth inverts and its cable is drawn dashed). A cable's brightness is its live push; crossings read over-and-under (casing). Click a cable selects it (cable, matrix cell and both rows in amber, inspector: big bipolar knob, depth / swing / push now, the push over the last 1.92 s between its bounds, and the sum base + this + others = out, checked against the meter: 0.50 + 0.06 + 0.00 = 0.56). Drag the cable's own knob (0.35 -> 0.60 exactly) or the inspector's (0.30 -> -0.50: dashed, "inverted"); drag jack to jack patches (the loose cable hangs from the jack, reachable jacks lit; from an empty output jack too); drag a plug to another jack re-patches, into the air unplugs (a "let go: unplugged" tag warns first); matrix: click patches an empty cell, click the selected cell unplugs, drag an empty cell patches it with the dragged depth (+0.30); drag along a meter sets the base (out_5 0.799981 for 0.80); M mutes (every out on its base, MUTED chip), Tab, Up / Down 0.05, Backspace, R default patch, Z undo (proven on an unplug and on R). Outputs are control outputs out_1 .. out_6; the patch is a 23-record `state_buffer`; presets "Default patch" and "S&H storm" are state-only, proven by recall. Bloom (one pass, paper): a guilloche rosette - two families of rose-curve rings turning opposite ways - whose petals / depth / twist / spin / size / hue ride out_1 .. out_6 through expressions; the bay's input rides the Curve Desk's ball height (ref() in, ref() out). Petal counts stay whole except across the middle fifth between counts, where the curve morphs (a stepping S&H never draws a torn or lopsided ring). GPU: Patch Bay 1.41 ms at 1579x1162 (reduce 0.02, layout 0.30, raster 1.09) |
| 11 | Timeline + Sting | sequence | built, proven with real input: a title sting in four layers (Ring, Sun, Block, Bar) x five channels (x, y, scale, rotation, opacity), up to 8 keys a channel, each key's interpolation hold / linear / ease (out and in influence) / spring (bounce) / back (anticipation, overshoot), on one editor canvas: STAGE (the picture at the playhead, the selected layer's motion path with a dot per frame and squares at its keys, onion skin of two ghosts each side), INSPECTOR (value fields with key diamonds; the primary key's mode, parameters and segment shape; a caption for a last key), TRANSPORT (play, 1/4 1/2 1x 2x, loop in - out, onion), DOPE SHEET (layer summary rows, channel rows with a solid bar where a value holds) and GRAPH (the active curve with its ease handles; the layer's other moving channels in grey, each to its own range). Proven: ruler click and drag scrub (exact frames), Space, the 1x chip; stage drag keys x / y at the playhead (-0.074, +0.150 as dragged), scale handle (1.683 for 1.684), rotate handle (+90.4 for +90.5), field drag (opacity 0.676), diamond key / unkey, a dope key click selects and turns the graph to its channel, mode chips and 1 - 5, ease parameter drag (33 -> 65 % as computed), graph handle drag (24 %), graph key drag (52 -> 60, 1.197), dope retime (60 -> 70, the primary follows), box select (the primary becomes its first key on the graph's channel), Backspace then Z (keys and selection back), double-click adds in the dope sheet and the graph, graph pan and F, both splitters, Up / Down key to key (40 -> 58, 59 -> 58), Left / Right, Enter, Tab (the graph takes the new layer's moving channel), O, R. A key added after a channel's last key eases (no default ends on a hold), so dragging the Block at frame 40 makes an eased path from frame 0, not a jump. Publishes Motion (343 float4: loop, counts, keys, playhead) and frame / playing / phase control outputs. Sting (one pass, 1280x720): the same layers shaded identically (`_shared/timeline.hlsli`), motion-blurred across the shutter (180 deg default) from the curves themselves, in linear light: 32 instants evaluated once per 16x16 group into groupshared, a pixel averaging `samples` of them, one per stratum, offset by interleaved gradient noise (no stepping at 4 - 8 samples; it stepped visibly at 8 before). Quality ladder, project presets scoped to samples + resolution: Draft 1 @ 720p 0.17 ms, Live 8 @ 720p 0.35 (2x, the default), Beauty 16 @ 1080p 1.20 (7x), Hero 32 @ 2160p 5.19 (30x, capture only), measured with 18 other stations open; recall proven narrow (shutter 270 kept). GPU: Timeline 1.05 ms at 1579x1162 (reduce 0.01, stage 0.09, layout 0.30, raster 0.65). Wheel zoom, Shift-click: by hand |
| 12 | Pattern + Pattern Bus | sequence | built, proven with real input: a polymetric step sequencer, six lanes on one sixteenth clock, each its own length 1 - 16 (factory 16 12 7 5 9 11: the hands point up together again only every 55,440 steps, the LCM, counted down in steps and m:ss at the rings' centre). A step: on, velocity, chance, ratchet (1 - 4 hits inside it), nudge (+- half a step); swing on the odd sixteenths. One canvas: GRID (each lane at its own length in the edit layer's terms - steps, velocity, chance, ratchet, nudge - with its end bracket), RINGS (each cycle as a ring of steps turned by its turn, a hand sweeping it), LANE and STEP inspectors, TAPE (every hit as it went out against the steps, hollow where the chance said no, the 100 ms sent ahead shaded right of now). Proven: cell click toggles (C3 step 2), a drag paints a velocity ramp (0.20 -> 0.93 over steps 1 - 8), bracket drag 16 -> 12, ring drag a quarter turn = turn 3 of 12, ring dot click (step 3 on), note / length / turn / hits fields (C3 -> G#3, 12 -> 9, 3 -> 5, hits 3 re-spread over 9 keeping velocities and nudges), velocity / chance / nudge fields (0.44 -> 0.60, 1.00 -> 0.81, 0 -> +0.06 as computed), ratchet 3, bpm 96 -> 104, swing 0.56 -> 0.58, MUTE in the inspector, M and S in the lane headers (a solo dims the rest; the tape shows only the solo), Space, 0 (step 0), Tab, Up / Down, Left / Right, Enter, E (re-spreads the on count; a ratchet on an off step kept), M, S, Backspace then Z (the lane back), R then Z (factory, then mine), layer keys 2 - 5 and the tabs, PLAY chip, both splitters. Timing: the reducer sends each hit on GPU EventOut "Hits" 100 ms before it is due, with "due in"; the Pattern Bus script stamps NoteOn at the record's host timestamp + due in and MIDI Out holds it until then: NoteOn stamps within +-0.6 ms of the swung grid, leads 83 - 100 ms, none late, MIDI Out late_ms ~4. MIDI Merge (a Script) joins the Pulse Bus and the Pattern Bus into the one Synth. Measured 14.1 hits/s for the factory pattern from the event stream, which the counted readouts match (hits in the last bar; notes in the last 4 s). Found by that count: lanes fired a step twice once the clock passed ~3,000 (float fmod, below) - fixed and re-measured. Presets (state only, project): "Pattern 1 Six lengths (factory, 96 bpm)", "Pattern 2 Clave, bell, tresillo (108 bpm)" (E(5,16), E(7,12), E(3,8), four on the floor, E(4,9), E(5,13), built by field drags, realigning every 1,872 steps), both recalled live while playing. GPU: Pattern 0.87 ms at 1579x1162 (reduce 0.05, layout 0.25, raster 0.57) |
| 13 | Score + Program | sequence | built, proven with real input: a show of acts on one clock. A RAIL act flies the camera through a colonnaded hall along up to 8 marks (eye, target and fov at a fraction of the act); a CARD act is a 16:9 title card (word, disc, bar, each placed, sized, shown or hidden). Every act has a light (day, dusk, night), a length and a hand-off to the next act over its own length: cut; dip through black; glide (between rails the camera and the light blend, with a card it dissolves). One canvas: SPACE (a rail: the plan over the elevation sharing the z axis, its marks, the rail and the live camera's wedge; a card: the stage), VIEW (a schematic projection of the hall through the camera at the playhead; drag aims the selected mark), the MARK / ITEM inspector, ACTS (ruler, a lane of act blocks with hand-off glyphs and mark ticks) over the CAMERA TRACK (eye height against the wall top, and lens, plotted over the whole show by the same resolve function the reducer runs), and the ACT inspector. Proven: Play chip, ruler and track scrub (15.67 s and 28.39 s as computed), act select, mark select in the elevation (the playhead jumps to it), plan eye drag (exact), VIEW look drag (aim as predicted), fov field drag, tick retime (45 -> 59.8 %), right-edge resize (act 4 -> 11 s), reorder then Z, card word drag, size handle (0.105 -> 0.143), SHOWN chip, the kind / light / hand-off rows and the word button, double-click adds a mark in the plan, A, Backspace, H, K, L (the light, on both kinds), D, R, Z, Left / Right, Space, 0, act loop (12.65 s wrapped to 8.64 s), both splitters. Publishes Score (the show plus the resolved act pair, 242 float4) and cam_x / y / z / yaw / pitch / fov control outputs. Program (one pass, 1280x720): the hall marched through its own internal camera, which the Score drives by expression on the six camera parameters (clear them to fly it: keys proven, RMB look by hand); day sun, dusk through the open end, night lamp pools under the moon; soft shadows, occlusion, one traced reflection off the glossy works; the cards drawn from the same `_shared/score.hlsli` as the stage; hand-offs composited in the cook that marches, so none shows a stale picture. Registration: the VIEW outline lies on the Program's render within a pixel. Presets: "Program Quality 1-4" scoped to march / shadow / occlusion / reflection steps and rays - Draft 0.73x, Live 1.00x (1.04 ms, the default), Beauty 1.06x, Hero 4.1x (four rays, capture only) - measured on the day view with the whole lab running (27 nodes, ~10.5 ms total GPU); state-only shows "Score 1 The hall by day and night" (the default) and "Score 2 Nocturne" (authored by clicks and keys: every rail at night, dips, the CODA card in the night palette), both recalled. GPU: Score 1.21 ms at 1579x1162 (layout 0.86, raster 0.34); Program 1.04 ms at Live, 0.07 ms while a card shows (nothing marched) |
| - | Scene Groups | wrap-up | done: one Scene Group per station (00 - 13, frames titled by number and name, a one-line body each) plus "Sound" (MIDI Merge + Synth, shared by 04 and 12). Exposed controls, 0 - 6 a group, each exercised in the open group Properties through its own widget (sliders, int sliders, checkboxes, combos by mouse, the Kit's XY pad by its Reset) and checked on the member, then restored: Kit point / amount / level / mode / enabled; Handles lamp intensity / cone / size / warmth / ambient; Still Life quality / key light / ambient / exposure; Pulse auto drop / gravity / bounce and Pulse Bus scale / root / mute; Sound channel / latency; Atoms LFO shape / rate, envelope attack / release, S&H rate, slew rise; Desk fade / master (via the Cue Brain) and Stage haze; Curve Desk loop length / fps / snap; Plotter speed / cornering / acceleration / nib / flow / memory; Ramp Desk blend and Relief terrain / sea level / shading / sun azimuth / contours (rendered once per change, captured); Patch Bay's five rates and Bloom's rings; Sting shutter / samples / slate and Timeline onion spacing; Pattern Bus transpose / gate / mute; Program exposure and march / shadow / reflection steps. Touch exposes nothing (its surface is the canvas). No camera parameter is exposed anywhere. Program frame contract "Frame · The door (fly from here)" saved (camera only) |
