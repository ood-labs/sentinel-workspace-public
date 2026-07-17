# Authored Module UI

Sentinel Modules can be complete interactive interfaces, not only image effects. The Module shader draws the interface, while the viewport manifest gives Sentinel the normalized hit regions, ordered input events, selection providers, and durable state contracts needed to interact with it.

Use the `module-ui-authoring` skill for the end-to-end workflow. The reference implementation in this workspace is `projects/interaction_lab/`.

## Responsibility Boundary

- HLSL owns appearance: panels, typography, spacing, borders, control faces, readouts, selection highlights, gizmos, and animation.
- The manifest owns semantics: parameter types, normalized hit rectangles, event interests, bindings, selection providers, state buffers, named outputs, and panel presentation.
- Sentinel owns routing: focus, pointer capture, undo transactions, parameter commits, host selection, project persistence, and the dock tab.
- Keep custom UI inside the Module system. Do not add native Sentinel widgets for an authored look unless the product itself needs a new general capability.

## Tailored Instrument Standard

An authored interface is not a reusable dashboard skin. Start from the operator's actual task, data topology, control frequency, and decision order, then design one compact instrument around that workflow. Reuse the shared interaction and typography primitives, but do not copy another example's panel arrangement, labels, decorative charts, or information hierarchy unless the new tool genuinely has the same job.

`projects/interaction_lab/modules/Motion_Console/` is the canonical reference for this standard. Its density is earned by a specific modulation workflow: four semantic lanes, live waveform previews, directly adjacent rate/amplitude/shape controls, numeric readouts, a master strip, an XY bias pad, burst, mute, and output meters. Every region either changes the modulation system or explains its live state. The lesson is the tight fit between information and action—not the monochrome styling or the four-lane layout itself.

Before authoring a UI:

- inventory the actions and state the operator needs at a glance;
- group controls by workflow and semantic ownership, not parameter type;
- put high-frequency controls next to the feedback they change;
- use domain labels, units, ranges, status, and previews rather than generic placeholder cards;
- remove decorative panels and charts that do not answer an operator question;
- keep the result compact, but preserve the 32-pixel hit-target minimum and clear hierarchy;
- study the nearest Interaction Lab example for implementation patterns, then compose a new layout tailored to the requested tool.

A UI review should be able to explain why every visible region exists. If the same panel could be dropped unchanged onto an unrelated module, it is probably not tailored enough.

## Scientific UI Foundation

Include the shared foundation from a sibling Module:

```hlsl
#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
```

The foundation provides normalized layout, a monochrome scientific theme, geometry primitives, controls, Scientifica regular-face text, named typography roles, and generated control rectangles/label tables.

Approved defaults are centralized in the shared headers:

- title: scale `2.0`, edge weight `0.2`, tracking `-2.5`;
- section: scale `1.75`, edge weight `0.0`, tracking `-2.5`;
- body: scale `1.5`, edge weight `0.0`, tracking `-2.5`;
- outer padding `15 px`, section gap `10.595863 px`, control height `32 px`, control gap `6.446163 px`.

Use the regular glyph face and add thickness through edge coverage. Do not switch to the bold Scientifica face for hierarchy.

## Scaffold And Generate

```powershell
./tools/module-ui.ps1 new modules/my_panel -Name "My Panel"
./tools/module-ui.ps1 generate modules/my_panel
./tools/module-ui.ps1 validate modules/my_panel
```

The generator writes `_ui.generated.hlsli` from `viewport.controls`, `viewport.labels`, and comments shaped like `# ui-label: title = SCIENTIFIC PANEL`.

Do not hand-edit `_ui.generated.hlsli`. Validation rejects stale generated files, incompatible control/parameter types, inverted or out-of-range rectangles, hit targets shorter than 32 pixels at the manifest resolution, duplicate ids, and unsupported non-ASCII labels.

## Controls

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

Treat `_Resolution` as the source of truth:

```hlsl
SuiContext c = suiContext(tid.xy, _Resolution.xy);
```

- Store UI rectangles in normalized coordinates.
- Express stroke widths, glyph scale, hit affordances, and gizmo sizes in pixels through `SuiContext`.
- Project 3D helpers with the actual `_Resolution`; never use a hard-coded 960 x 540 viewport for hit testing or ring orientation.
- Use an explicit design canvas only for intentional legacy scaling, and map it into the actual output consistently.
- Generate camera-facing rotation rings by projecting their real 3D axis planes. Render and hit-test the same projected basis.

## Full-Bleed Canvas Panels

Sentinel 0.5.32 and newer support the Phase 89.2 authored panel contract:

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

## Runtime Proof

```text
sentinel_pipeline action=compile_check project_dir=<absolute-module-dir>
sentinel_pipeline action=compile_status pipeline_id=<id>
sentinel_pipeline action=info pipeline_id=<id>
```

For Canvas/follow-panel Modules, `info.panel` reports `declared_mode`, `effective_mode`, selected `output`, `resolution_mode`, `content_size`, `render_size`, extent generations, render-target recreations, and deferred-resource count.

Prove controls with real or injected pointer input, not StateTree writes alone. Inspect viewport diagnostics and relevant data ports, then capture the visible result. An immediate capture taken on the same instant as a parameter write can observe an in-flight frame; require a settled capture and live interaction proof before diagnosing persistent corruption.

## Reference Examples

- `modules/ui_kit_gallery/`: slider, momentary button, toggle, XY pad, readouts, and shared chrome.
- `modules/ui_style_tuner/`: live typography and spacing calibration.
- `modules/font_style_sampler/`: regular-face edge-weight comparison.
- `modules/spline_editor/`: authored sub-object editing with persistent state and typed outputs.
- `modules/transform_gizmo_lab/`: selection, multi-object transforms, projected handles, and camera-aware rotation rings.
- `projects/interaction_lab/modules/Motion_Console/`: canonical tightly packed, task-specific instrument with semantic modulation lanes, adjacent live feedback, and no generic dashboard filler.
- `projects/interaction_lab/interaction_lab.sentinel`: bundled review project.

Everything above is authored Module content. It does not require a new Sentinel native widget or IPC feature.
