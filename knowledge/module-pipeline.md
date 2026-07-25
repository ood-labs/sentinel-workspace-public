# Module Pipeline

Pipeline type: `module`

Modules are authored shader projects with a `manifest.yaml`. They can be generators, post-processors, data consumers, data producers, control-output producers, or multi-pass renderers.

## When To Use A Module

Use a Module when you need:

- a custom HLSL visual effect;
- a shader parameter surface exposed to MCP and the UI;
- a typed data input from tracking or detection;
- a typed data output for another node;
- a scalar control output that can drive expressions;
- persistent buffers or multi-pass feedback.

For simple one-file post-processing, `hlslshader` may be enough.

## Fast Scaffold From Tracking Data

Use `sentinel_module action=scaffold_from_ports` when a Module should consume tracking, detection, blob, corner, line, landmark, PCM, Spectrum, or Mel Bands data. Pass the upstream pipeline id and optional data port name. The tool writes `modules/<module_name>/manifest.yaml` and `render.hlsl` in the launched workspace, using the live schema from `get_data_schemas`.

The generated Module starts with modern controls: color palette pickers, a `point2D` composition pad, grouped toggles, and an `enum` button grid. Treat it as the starting point for creative shaping, then run `sentinel_pipeline action=compile_check project_dir=<generated_dir>` before creating the Module node.

## Parameters

Module manifest parameters become normal Sentinel parameters. They appear in `sentinel_pipeline info` and can be changed with `sentinel_state set` or driven with `sentinel_expression action=set`.

Supported parameter types include:

- float
- int
- bool
- enum
- color
- vec2 / point2D
- vec3
- vec4

## Data Ports

Modules can declare `data_inputs` and `data_outputs`. These are structured buffers, wired through `sentinel_graph add_link`.

Use data inputs for landmarks, detections, blobs, corners, lines, or records produced by another module.

`sentinel_pipeline action=get_data_schemas` reports the data schema and, when the graph node exists, the matching graph pin name and slot. Use that reported pin name with `sentinel_graph action=add_link` instead of guessing singular/plural labels.

Audio In Spectrum and Mel Bands inputs are flattened 64-hop rings. Add `features: [audio]`, store a next-unread generation in a persistent buffer, and use `AudioRingCatchupStart` plus `AudioRingGenerationToSlot` to process retained hops in chronological order. See `knowledge/audio-reactivity.md`.

## Meaningful Intermediate Previews

Every Module that generates or transforms structured data must also render a cheap, legible preview of its own current output. The preview is part of the node's authoring contract, not decorative polish.

At minimum, visualize active records and their spatial arrangement. Encode direction, group, weight, kind, confidence, or other defining fields when they materially affect the downstream result. Parameter changes that alter structure must produce an obvious preview change.

After create or reload, focus the node, call `sentinel_pipeline action=open_window`, and inspect the actual Sentinel preview before continuing to the next node. Use `capture_data_port` to verify record values and a preview capture to verify their visual decoding. `stats.has_preview_srv=true` is insufficient: a blank, constant, generic, or unreadable texture is a failed preview and must be fixed before handoff.

## Control Outputs

Modules can publish scalar values under:

```text
/sentinel/pipelines/<module_id>/control_outputs/<name>
```

Other parameters can read them with:

```text
ref("module_lfo/control_outputs/rate")
```

## Shared Motion And Audit Libraries

For authored motion, include `#include "../_shared/anim/anim.hlsli"` and use `an_spring`, `an_spring_v`, the `an_stagger_*` family, `an_anticipate`, `an_squash`, and `an_loop_noise` instead of hand-rolled easing. The same equations exist in expressions (`spring`, `stagger`, ...). Rate-driven values integrate phase; never multiply a live rate by absolute time. See `knowledge/motion-choreography.md`.

For measured geometry assertions on SDF modules, `modules/_shared/sdf/sdf_audit.hlsli` provides bisection dimension measurement, bounds clearance, and overlap sampling; results publish through a structured data output that `sentinel_blueprint action=audit` reads. See `knowledge/precise-construction.md`.

## Viewport Interactions And Cameras

A manifest can declare an optional `viewport:` block with a `hint` string and an `interactions` list drawn from `mouse`, `pan_zoom`, and `camera`. The preview shows the hint and only forwards the declared interactions, and the values publish at `/sentinel/pipelines/<id>/viewport/hint` and `/viewport/interactions`. Camera-feature modules (`features: [camera]`) get a shared fly/orbit rig plus a `camera_ref` parameter for binding to a `camera` node; see `knowledge/scene-system.md` for the camera and camera-switcher system.

Choose one camera owner per graph: the Module's internal camera or an explicit `camera`/`camswitch`. Never expose camera-related parameters, including `camera_ref`, mode, position, orbit, target, and FOV, on a Scene Group/top-level interface. Keep camera operation on the owning renderer preview or camera node Properties. When bound to an external or group camera, local camera controls are intentionally inactive. Verify the owning camera through an open renderer preview and a visible before/after change.

## Authored Viewport Events

Modules that need ordered pointer, gesture, or keyboard edges in their shaders add `events` to `viewport.interactions` (available on installs at 0.5.30 or newer). The workspace module `modules/click_ripples/` is a complete working example: an interactive paint canvas using clicks, drags, wheel brush sizing, and key commands. Read its manifest and three shaders alongside this section.

### Manifest

```yaml
viewport:
  hint: "Click/drag=paint, wheel=brush, C=palette, X=clear"
  interactions: [events]
  input:
    pointer: [left, wheel]
    keyboard: [c, x]
    gestures: [click, drag]
  bindings:
    - { gesture: left_click, action: paint, label: "Paint" }
    - { gesture: left_drag, action: paint_trail, label: "Paint Trail" }
    - { key: c, action: next_palette, label: "Next Palette" }
```

Token vocabularies (invalid tokens fail compile with a field-qualified message such as `viewport.bindings[1].gesture`):

- `input.pointer`: `left`, `right`, `middle`, `wheel`
- `input.keyboard`: single characters `a`-`z` and `0`-`9`, plus `escape`, `tab`, `enter`, `space`, `backspace`, `left`, `right`, `up`, `down`, `shift`, `control`, `alt`
- `input.gestures`: `click`, `double_click`, `drag`
- `bindings[].gesture` uses a DIFFERENT vocabulary than `input.gestures`: `left_click`, `right_click`, `middle_click`, `shift_left_click`, `shift_right_click`, `shift_middle_click`, `left_double_click`, `right_double_click`, `middle_double_click`, `left_drag`, `right_drag`, `middle_drag`, `wheel`

Bindings are user-facing help and conflict intent: each has one `key` or `gesture`, an `action`, and a `label`. They publish at `/sentinel/pipelines/<id>/viewport/bindings` and render as a Controls affordance beside the preview OUTPUT row.

### Injected shader API

Every pass of an events module gets a cbuffer snapshot and an event array:

- Snapshot (safe to read in any pass, any thread): `_ViewportEventCount`, `_ViewportPointerPosition` (float2), `_ViewportPointerDelta`, `_ViewportWheelDelta` (frame-summed scroll notches), `_ViewportButtons`, `_ViewportModifiers`, `_ViewportCaptureFlags`, `_ViewportKeyBits` (uint4), `_ViewportAbiVersion`, `_ViewportFrameSequence`, `_ViewportOverflowCount`.
- `StructuredBuffer<ViewportEvent> _ViewportEvents` at `t127`, `_ViewportEventCount` valid entries (max 64), fields `type`, `phase`, `code`, `modifiers`, `position` (float2), `delta` (float2), `value`, `sequence`, `flags`, `device`.
- Helper functions: `ViewportKeyDown(key)`, `ViewportButtonDown(button)`, `ViewportModifierDown(modifier)`; constants `VIEWPORT_EVENT_FLAG_REPEAT/SYNTHETIC/HOST_CONSUMED/CAPTURE_CANCEL` and `VIEWPORT_MODIFIER_SHIFT/CONTROL/ALT/SUPER`.

Event vocabulary (frozen v1 ABI): `type` none 0, pointer move 1, pointer button 2, wheel 3, key 4, gesture 5, capture 6. `phase` press 1, repeat 2, release 3, double-click 4, begin 5, update 6, end 7, cancel 8. Pointer `code`: left 0, right 1, middle 2. Gesture `code`: click 1, double-click 2, drag 3. Key `code`: A-Z are 1-26 (so C is 3, X is 24), digits 0-9 are 32-41, Escape 48, Tab 49, Enter 50, Space 51, Backspace 52, arrows 53-56, Shift 57, Control 58, Alt 59.

Verified conventions:

- `event.position` and `_ViewportPointerPosition` are normalized preview coordinates in exactly the same space as a full-resolution pass's `uv`. A click in the preview center arrives as position (0.5, 0.5).
- A completed click gesture arrives as ONE event: type 5, code 1, phase 7 (end). Drags stream type 5, code 3 with phase 5 begin, 6 update per movement, 7 end (8 on cancel), each carrying the current position. Raw pointer presses (type 2, phase 1) also arrive when `pointer` interests include the button.
- Key presses are type 4, phase 1 edges; held keys are also visible any frame through `ViewportKeyDown()`.

### The `_DeltaTime` rule (critical)

Modules cook at a rate decoupled from the display, often hundreds or thousands of cooks per second on a fast GPU (check `stats.fps` in `sentinel_pipeline info`). Any per-cook constant decay or accumulation is therefore wrong: `energy *= 0.975` fades to nothing within milliseconds at 2000 cooks per second, which reads as "my event visuals never appear" even though every event was delivered and every splat was written. Scale all rates by `_DeltaTime`:

```hlsl
// behaves like 0.99/frame at 60 FPS regardless of the actual cook rate
energy *= pow(saturate(decay), _DeltaTime * 60.0);
```

This is the same family as the expression rule "integrate phase, never multiply a live rate by absolute time".

### Recommended architecture: reduce once, fan out through a buffer

The proven pattern (used by both `modules/click_ripples/` and the engine's own replay fixture) is a small explicit-dispatch pass that reduces the event array into a persistent state buffer, with full-resolution passes consuming derived state:

1. A `dispatch: [1, 1, 1]` events pass reads `_ViewportEvents`, updates control values (palette, brush size, toggles), writes a bounded splat queue (position + strength entries), and bumps a generation counter whenever it queued work.
2. The full-resolution pass compares the generation against the last one it consumed (remembered in its own buffer) and applies queued splats exactly once, no matter how many cooks share one input frame.
3. Render passes read only derived state plus the cosmetic snapshot values (`_ViewportPointerPosition`, `ViewportButtonDown`) for cursor rings and hints.

This keeps event handling single-threaded and testable, dedupes work across cooks, and keeps heavy passes free of event logic.

### Focus, lifecycle, and testing

Events deliver only while the module's preview is focused; a click on the preview focuses it. Hot reload cancels focus and capture, so after editing shaders the first click refocuses. The router priority is modal and text/terminal input, then pointer capture, then focused authored bindings, then global shortcuts; Escape cancels active pointer capture before delivery. Capture also cancels on disable, project load, and preview close. `_Mouse` keeps working for existing modules.

To verify an events module end to end, read the live diagnostics under `/sentinel/pipelines/<id>/viewport/`: `focused`, `delivered_boundary_count` (grows by 3 per click: press, release, click gesture), `bindings`, `event_overflow_count`, and `capture_owner`. Exercise the preview with real pointer or keyboard input and capture the output to confirm the visual result. State writes never exercise this path; only real or host-injected input does.

## Viewport Persistence, Controls, And Selection

Installs at 0.5.31 or newer add higher-level authoring surfaces on top of raw events, plus the `sentinel_viewport` MCP tool (`info`, `objects`, `selection`, `pick`, `edit`, `state`; every action takes `pipeline`).

### Param gestures

`viewport.param_gestures` binds drags to ordinary parameters. Left-drag within `radius` of `position_param` moves it; right-drag adjusts the optional `rotation_param`. Declare the target parameters `hidden: true` when the viewport should be their only visible editor. Edits preview live and commit once on release as one undo entry.

```yaml
parameters:
  - { name: obj_pos, type: vec2, min: [0, 0], max: [1, 1], default: [0.5, 0.5], hidden: true }
  - { name: obj_rot, type: float, min: -720, max: 720, default: 0, hidden: true }

viewport:
  interactions: [events]
  input: { pointer: [left, right], gestures: [drag] }
  param_gestures:
    - { id: obj, position_param: obj_pos, rotation_param: obj_rot, radius: 0.075 }
```

### Authored controls

`viewport.controls` defines normalized hit regions bound to parameters. The host owns capture, parameter preview, and commit; the Module draws the entire control. Kinds and required types are `slider` (float/int), `button` (button), `toggle` (bool), and `xypad` (`vec2`/`point2D`).

```yaml
viewport:
  controls:
    - { id: mix_slider, kind: slider, param: mix, rect: [0.10, 0.82, 0.48, 0.90], label: "Mix" }
```

Use `tools/module-ui.ps1` and `knowledge/ui-authoring.md` for the shared scientific UI foundation, generated labels and rectangles, responsive layout, and proof workflow.

### Durable state buffers

`state_buffers` names persistent structured buffers whose declared element range serializes into the project, node presets, and undo payloads. Restore happens through the upload path before processing resumes. `sentinel_viewport action=state` reports declared buffers and captured byte counts.

```yaml
buffers:
  - { name: scene_state, structured: true, element_size: 16, element_count: 200, persistent: true }
state_buffers:
  - name: scene_state
    max_elements: 200
    schema:
      - { name: position, type: float2 }
      - { name: rotation, type: float }
      - { name: id, type: uint }
```

### Selection and picking

Add `selection` to `viewport.interactions` and declare a `selection:` block. `ray_query` uses descriptor-only picking; `id_buffer` uses a stable rendered object-id pass. The object buffer publishes ids, transforms, bounds, pivots, visibility, selectability, and capability flags. Shaders read `_ViewportSelectionIds` and `_ViewportSelectionMeta` to draw highlights.

### Driving it over MCP

- `sentinel_viewport action=info`: interaction surface, controls, selection config, and edit transaction state.
- `action=objects`: published object descriptors.
- `action=selection` with `selection_action=get|set|clear`.
- `action=pick x=<nx> y=<ny>`: asynchronous normalized-coordinate pick.
- `action=edit`: a full begin/preview/commit move transaction, or an explicit four-phase edit.
- `action=state`: durable state-buffer inventory and captured byte counts.

## Authored Canvas Panels

Installs at 0.5.32 or newer support Phase 89.2 panel presentation:

```yaml
panel:
  mode: canvas
  output: UI
  resolution: follow_panel
```

`mode` is `standard` or `canvas`; `resolution` is independently `pipeline` or `follow_panel`. Canvas retains the dock tab but gives every pixel below it to the named authored texture, with no host header, input strip, output tabs, hints, padding, border, scrollbars, or letterboxing. A single-output Canvas may omit `output`; a multi-output Canvas must name it.

`follow_panel` continuously makes the Module's real output extent match the non-zero panel content extent. Each dimension clamps to 64 through 16384. The selected output pass must inherit the root resolution; conflicting per-pass resolution settings fail manifest loading. Hidden/inactive panels retain the last valid extent.

`sentinel_pipeline info` reports `panel.declared_mode`, `effective_mode`, `output`, `resolution_mode`, `content_size`, `render_size`, and resize diagnostics. Users can recover through `Panel Presentation > Follow Module | Standard | Canvas`; project workspaces persist docking, visibility, sizes, anchors, and per-node overrides.

See `knowledge/ui-authoring.md` for the complete shader UI workflow and the Interaction Lab examples.

## Compile And Reload

Module creation with `project_dir` is atomic. The response reports whether manifest parsing started cleanly. Shader compilation is async, so poll:

```text
sentinel_pipeline action=compile_status pipeline_id=<id>
```

Use `force_reload` after changing files or recovering from a compile error.

## Authoring Order

When writing a module project programmatically, write shader files first and `manifest.yaml` last. The file watcher reacts to manifest saves, so saving the manifest before its shader files exist can create a temporary compile failure.

## Output Resolution

By default, modules match input slot 0. A manifest can select generator mode or explicit resolutions. Multi-pass modules can use per-pass resolution rules.

For fixed generator visuals, use an explicit or generator resolution. For video effects, match the input.
