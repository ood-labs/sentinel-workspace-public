# Authored Module UI

Sentinel Modules can be complete interactive interfaces, not only image effects. The Module shader draws the interface, while the viewport manifest gives Sentinel the normalized hit regions, ordered input events, selection providers, and durable state contracts needed to interact with it.

Use the `module-ui-authoring` skill for the end-to-end workflow. The reference implementation in this workspace is `projects/interaction_lab/`.

## Responsibility Boundary

- HLSL owns appearance: panels, typography, spacing, borders, control faces, readouts, selection highlights, gizmos, and animation.
- The manifest owns semantics: parameter types, normalized hit rectangles, event interests, bindings, selection providers, state buffers, named outputs, and panel presentation.
- Sentinel owns routing: focus, pointer capture, undo transactions, parameter commits, host selection, project persistence, and the dock tab.
- Keep custom UI inside the Module system. Do not add native Sentinel widgets for an authored look unless the product itself needs a new general capability.

## Visual Foundation

Create a neutral project-local scaffold with:

```powershell
./tools/module-ui.ps1 new projects/my_project/modules/my_panel -Name "My Panel"
```

The scaffold vendors its small dependency set into the owning project. Its
plain field, type, frame, and rail exist only to prove the responsive contract.
Replace their palette, typography, density, shapes, and motion with a language
appropriate to the current problem. Do not inherit Interaction Lab's
scientific-instrument look merely because it is available.

Whatever visual language you choose:

- derive layout rectangles from the actual panel size;
- express strokes, glyph sizes, and grab affordances in pixels;
- make rendered control geometry match the manifest hit rectangles;
- derive control visuals from live values, not decorative hover state;
- keep required font licenses beside every vendored font table.

## Scaffold And Generate

```powershell
./tools/module-ui.ps1 new projects/my_project/modules/my_panel -Name "My Panel"
./tools/module-ui.ps1 generate projects/my_project/modules/my_panel
./tools/module-ui.ps1 validate projects/my_project/modules/my_panel
```

The generator writes `_ui.generated.hlsli` from `viewport.controls`, `viewport.labels`, and comments shaped like `# ui-label: title = SCIENTIFIC PANEL`.

Do not hand-edit `_ui.generated.hlsli`. Validation rejects stale generated files, incompatible control/parameter types, inverted or out-of-range rectangles, hit targets shorter than 32 pixels at the manifest resolution, duplicate ids, and unsupported non-ASCII labels.

## Controls

Do not recreate the Properties panel inside an authored Canvas. Ordinary numeric sliders, colors, toggles, and enums already have precise host controls, range editing, reset, OSC, expressions, presets, and undo. A permanent wall of shader-rendered duplicates consumes the space needed for the visual and adds no new capability.

Viewport controls are justified when they are spatial, contextual, or performative: tool selection, momentary actions, transport, mode switches, an XY pad whose location is part of the visual, or controls that operate on the current selection. Keep them few and subordinate to the content.

Bind shader-rendered controls to ordinary parameters:

```yaml
parameters:
  - { name: amount, type: float, min: 0, max: 1, default: 0.5 }
  - { name: apply, type: button }
  - { name: enabled, type: bool, default: true }
  - { name: cursor, type: point2D, min: [0, 0], max: [1, 1], default: [0.5, 0.5] }

viewport:
  controls:
    - { id: amount, kind: slider, param: amount, rect: [0.08, 0.28, 0.62, 0.36], label: "Amount" }
    - { id: apply, kind: button, param: apply, rect: [0.68, 0.28, 0.90, 0.36], label: "Apply" }
    - { id: enabled, kind: toggle, param: enabled, rect: [0.68, 0.40, 0.90, 0.48], label: "Enabled" }
    - { id: cursor, kind: xypad, param: cursor, rect: [0.08, 0.52, 0.90, 0.88], label: "Cursor" }
```

Control rectangles are normalized image coordinates and must match the rectangles rendered by HLSL. Use `_ViewportControlFlags[index]` through `suiInteraction(index)` for local down/hover state. Momentary feedback should read only that control's pressed bit. Do not let one control's rollover state alter shared structural borders or neighboring controls.

Prefer value-driven visuals. A toggle thumb should derive from its value, a slider fill from its numeric value, and a selected tool from its actual mode. Keep geometry branchless where practical so both states share the same rendering path.

## Direct Manipulation First

Use the viewport for work that Properties cannot express well:

- select, move, rotate, and scale objects;
- add, remove, and edit points, handles, and splines;
- paint ripple, displacement, mask, force, or erase fields;
- manipulate regions, falloffs, attractors, flow directions, and camera gizmos;
- trigger spatial or time-sensitive performance gestures.

Toolbars should select interaction modes, not expose every implementation parameter. Make brush radius broad enough for both fine detail and frame-scale gestures, and provide several semantically distinct tools rather than one brush with many hidden meanings. Put exact gain, decay, threshold, palette, and tuning values in Properties. Show only compact, useful telemetry such as active tool, selection, feature counts, frame budget, and capture state.

For a system-wide editor, publish durable structured interaction data instead of baking all interaction into a final post-process. A renderer can then consume the same points, splines, strokes, regions, or force records at its canonical output resolution.

## Events, Selection, And Durable State

Use `viewport.interactions: [events]` when controls are not enough. Declare the exact pointer, keyboard, modifier, and gesture interests. Reduce ordered events once in a `dispatch: [1,1,1]` pass, write derived interaction state to a persistent structured buffer, and let full-resolution passes consume that state. Use `_DeltaTime` for every decay because Modules can cook much faster than the visible display rate.

For object tools:

- `param_gestures` is the simplest drag-to-move/rotate path for parameter-backed objects;
- `viewport.controls` is best for fixed UI chrome;
- `selection` plus `ray_query` or `id_buffer` gives Sentinel host-owned object selection;
- `state_buffers` persists authored GPU state through projects, presets, and undo;
- four-phase viewport edits (`begin`, `preview`, `commit`, `cancel`) keep one drag as one undo transaction.

Acquire a drag handle on pointer-down and retain ownership until commit or cancel. Do not re-pick the handle every frame; fast pointer motion and event-free cooks must not drop the active edit.

## Responsive Geometry

Treat the actual output texture extent as the source of truth:

```hlsl
uint width, height;
OutputUAV.GetDimensions(width, height);
float2 resolution = float2(width, height);
```

- Store UI rectangles in normalized coordinates.
- Express stroke widths, glyph scale, hit affordances, and gizmo sizes in pixels through `SuiContext`.
- Project 3D helpers with the actual `_Resolution`; never use a hard-coded 960 x 540 viewport for hit testing or ring orientation.
- Use an explicit design canvas only for intentional legacy scaling, and map it into the actual output consistently.
- Generate camera-facing rotation rings by projecting their real 3D axis planes. Render and hit-test the same projected basis.

## Scrolling Data Traces

Interaction Lab's scalar plots use its project-bundled
`projects/interaction_lab/modules/_shared/ui/sui3_trace.hlsli` helper. It gives a strip chart the behaviour
a TouchDesigner CHOP viewer has: the plot advances at the rate of the data rather
than the frame rate, and it rescales itself continuously to the signal's recent
dynamics. Every function is pure and takes its extents as arguments, so a state
pass can include it without declaring viewport events, and it contains no text,
theme, or parameter references so both the `sui3` and `au_hud` kits can draw with
it. Labels, units, and readouts stay with the calling module.

Four mechanisms make the plot honest. Each was measured in
`projects/cloth_lab/modules/cloth_bands`, the reference consumer.

**Ring plus generation catch-up.** Keep a write cursor and drain from it to `_DataN_Generation` every cook, rather than sampling the newest value once per frame. A module cooking at 60 Hz against a 187.5 Hz hop rate discards two of every three samples that way, aliases the rest, and the time axis it draws is fiction. Use `sui3CatchupStart` to clamp the drain to what the ring still holds; a fresh cursor of 0 against a generation counter in the millions would otherwise spin the loop a million times on the first cook. Buffers that carry no header record, including Spectrum and Mel Bands, need each slot's own `generation_counter` validated inside the loop, because element zero cannot report the latest generation.

**Decaying-peak autoscale.** A fixed full scale is wrong for every input. Measured peaks on real drums run past 24 dB while a quiet pad barely reaches 4, so one case clips and the other draws a flat line along the bottom. `sui3PeakDecay` holds a rolling peak with instant attack and a half-life release; 4 seconds is the measured point where the scale follows a change of material without twitching on individual hits. Always pass a `minFs` floor to `sui3FullScale`. Without one, a silent input autoscales its own noise to full height and looks like it is working.

Pass `sui3FullScale` the maximum over the displayed samples as well as the decayed peak, as `max(windowMax, decayedPeak)`. The decay is anchored at the present moment while the plot shows history, so when the half-life is short relative to the span, a loud passage still fully on screen has already decayed the peak below its own samples and the plot clips itself. Measured in Data Scope on identical material at a 5 second span against a 0.25 second half-life, as a fraction of strip height: the decayed peak alone gave peak 1.000, p95 1.000, median 1.000, while `max(windowMax, decayedPeak)` gave peak 0.875, p95 0.855, median 0.614. The 0.875 is exactly the 1.15 headroom, so the tallest sample sits just below the top edge. Severity scales with the span-to-half-life ratio: the same break at the 3 second and 4 second defaults measured only 0.896, which looks almost correct at a glance, so check this with a number rather than by eye.

**Max-reduce, never mean, but only when downsampling.** At long spans one pixel column covers many samples. `sui3TraceSpan` returns the index range a column covers and the caller takes the maximum over it. Averaging hides precisely the transient the plot exists to show. The span is capped at eight samples per column because an uncapped per-pixel loop at a long span is a frame-rate cliff.

Max-reduce is wrong in the other direction. When the plot has more pixel columns than samples, several adjacent columns land on the same sample, the reduced value is piecewise constant, and a smooth signal is drawn as a staircase. That is the normal case for a cook-rate stream on a wide panel: Signal Trails plots 481 samples across 1600 pixels at an 8 second span, roughly three columns per sample, and every step had a three-pixel tread. Test with `sui3TraceUpsampling` and, when it is true, take `sui3TraceFrac` and interpolate between `floor(pos)` and `floor(pos) + 1` instead of reducing.

**Smooth the interval when sampling at cook rate.** Never pass a raw `_DeltaTime` to `sui3TraceSamples`. The sample count sets the horizontal mapping, so recomputing it from the instantaneous frame delta rescales the whole time axis every frame. Measured in Signal Trails at a nominal 60 fps, the plotted window swung across 12.4 samples of an 8 second span, a 2.6% horizontal stretch on every cook, which at 1600 pixels is about 42 pixels of visible jitter anchored at the live edge. `sui3SmoothDt` with an alpha of 0.02 took that to 0.8 samples, or 0.16%. A stream-driven consumer does not need this: its interval is `hop_size / sample_rate` and is exactly constant.

**Clamp the sample index to what has been written.** `writeIdx` is the next slot to write, not the last one written, and that slot still holds the sample from one full ring ago. Fetching it plots data from a thousand samples in the past at the live edge, appearing as a spike or notch welded to the rightmost column that never scrolls away. Pass every index through `sui3TraceClampIndex` in both the reduce and interpolate paths; the interpolating path is worse because it reaches one sample further for its segment endpoint.

**Fill or trail, by signal type.** `sui3StripFill` suits a signal made of events, where each column is an independent excursion from a baseline. `sui3StripTrail` suits a smooth continuous signal, where a solid slab hides the shape that is the entire content. Do not draw unconnected per-column marks for a smooth signal: adjacent columns take their maxima from different samples, so the result is a dotted scatter rather than a curve.

**Scale the reference line too.** Pass any threshold or reference level into `sui3FullScale` as `refLevel`. A threshold set above the recent peak otherwise pins itself to the top edge, where it stops reading as a threshold and becomes the rect border, losing the one thing the strip is for: how far under the line the peaks are falling.

The strip's Y is value-up, so value 0 sits on the bottom edge. This matches Style Authority's pad contract: the host value remains unmodified everywhere, and pad rendering goes through `sui3PadPoint`. Do not reproduce the helper with local `1.0 - value.y` arithmetic; centralizing the conversion is what prevents the host, Properties, published data, readout, and reticle from drifting apart. Time runs oldest-left to newest-right, so the trace scrolls right to left.

Do not reach for this when a single current value is the whole story. A number, a bar, or a meter is more legible than a trace, and a trace of a value that does not change is a horizontal line that costs a ring buffer.

## Full-Bleed Canvas Panels

Sentinel 0.5.32 and newer support this authored panel contract:

```yaml
panel:
  mode: canvas
  output: UI
  resolution: follow_panel
```

The fields are independent:

- `mode: standard | canvas` controls host presentation.
- `resolution: pipeline | follow_panel` controls the Module's real output extent.
- `output` names the texture output shown by Canvas. It is optional for a single-output Module and required for a multi-output Canvas.

Canvas keeps the dock tab as the identity and recovery handle. Everything below it is the named authored texture: no Sentinel header, status, input strip, output tabs, hints, padding, preview border, scrollbars, or aspect-fit letterboxing.

`follow_panel` publishes each non-zero integer content extent to the Module. The selected output pass must inherit the root resolution; a conflicting per-pass resolution fails manifest validation. Each dimension clamps to 64 through 16384. Hidden, collapsed, or inactive panels retain their last valid extent.

A Canvas may keep `resolution: pipeline` and stretch its texture. A Standard panel may use `follow_panel`. Use Canvas plus `follow_panel` for a pixel-matched full-frame interface.

Users can recover through `Panel Presentation > Follow Module | Standard | Canvas` in the graph-node context menu or selected-node View menu. Project workspaces persist docking, sizes, visibility, window identity, and per-node presentation overrides.

## Canonical Program And Flexible Editor

Do not use a `follow_panel` Canvas as the canonical Program renderer unless the artwork is deliberately authored for arbitrary aspect ratios. Dock dimensions are an editor concern and can change continuously; a 16:9 image sampled directly across an arbitrary panel will stretch.

Prefer two responsibilities:

1. A Program renderer keeps an intentional resolution such as 1280x720 and consumes scene plus interaction data.
2. A flexible editor Canvas displays the Program inside an aspect-correct stage rectangle and publishes interaction data back to the renderer.

For a fitted preview, compute a stage rectangle from the Program aspect and panel extent. Letterbox or crop intentionally, render contextual tools in the remaining gutters, and transform pointer coordinates from panel UV into stage UV before hit testing or writing strokes. Reject or clamp events outside the active stage. Render and hit-test against the same transform.

This separation keeps exported imagery stable, prevents dock resizing from reallocating the entire creative pipeline, and allows the editor to use arbitrary panel space without distorting the composition.

## Runtime Proof

```text
sentinel_pipeline action=compile_check project_dir=<absolute-module-dir>
sentinel_pipeline action=compile_status pipeline_id=<id>
sentinel_pipeline action=info pipeline_id=<id>
```

For Canvas/follow-panel Modules, `info.panel` reports `declared_mode`, `effective_mode`, selected `output`, `resolution_mode`, `content_size`, `render_size`, extent generations, render-target recreations, and deferred-resource count.

Prove controls with real or injected pointer input, not StateTree writes alone. Inspect viewport diagnostics and relevant data ports, then capture the visible result. An immediate capture taken on the same instant as a parameter write can observe an in-flight frame; require a settled capture and live interaction proof before diagnosing persistent corruption.

## Reference Examples

- `projects/interaction_lab/modules/Style_Authority/`: responsive style and layout station.
- `projects/interaction_lab/modules/Spline_Desk/`: authored sub-object editing with persistent state and typed outputs.
- `projects/interaction_lab/modules/Gizmo_Desk/`: selection, multi-object transforms, projected handles, and camera-aware rotation rings.
- `projects/interaction_lab/modules/Motion_Console/`: responsive performance controls and durable action state.
- `projects/interaction_lab/modules/data_scope/` and `projects/interaction_lab/modules/signal_trails/`: bundled `sui3_trace.hlsli` consumers.
- `projects/cloth_lab/modules/cloth_bands/`: the reference consumer, with three auto-ranging strip charts and an on-plot threshold handle.
- `projects/interaction_lab/interaction_lab.sentinel`: bundled review project.

Study these for interaction architecture and proof strategy. Do not copy their
project-specific visual language or Modules into unrelated work unless the user
explicitly requests a fork or remix. Everything above is authored Module
content; it does not require a new Sentinel native widget or IPC feature.
