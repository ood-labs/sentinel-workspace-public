# Interaction Lab

Interaction Lab is a bundled Module-only example project for authored viewport tools. It combines a reusable monochrome scientific UI gallery, a live UI style tuner, a font-style sampler, a tightly tailored four-lane motion console, a GPU spline editor, a downstream spline renderer, and a multi-object 3D transform gizmo.

Load `interaction_lab.sentinel` in Sentinel. Each example is boxed and labeled in the graph; double-click a Module node to use its viewport.

The graph is organized as four independent, flat Scene Group stations:

- `01 · SCIENTIFIC UI + TYPE SYSTEM`
- `02 · SPLINE EDITOR + PNODE OUTPUT`
- `03 · 3D TRANSFORM GIZMO`

- `04 - TAILORED MOTION CONSOLE`

The groups save `Reference UI`, `Default Sweep`, `Object Study`, and `Motion Reference`. They are intentionally control-only: Interaction Lab is a tool and data-flow reference, so it has no Group Output endpoint. Scene Groups are never nested.

## Tailored Motion Console

`Motion_Console` is the canonical reference for a compact interface designed around one operator workflow rather than a generic dashboard template. Its four semantic lanes—Prompt, Energy, Camera, and Pulse—place live waveforms, numeric state, rate, amplitude, and shape selection together. The master strip, motion-bias XY pad, burst, mute, and output meters occupy a narrow side rail because they affect or summarize the whole modulation system.

The reusable lesson is not “make every UI monochrome” or “always use four lanes.” It is that every region earns its space by changing the system or explaining live state. New interfaces should reuse the shared UI primitives while deriving their own grouping, labels, ranges, feedback, and density from the requested tool.

Control outputs publish the four LFO lanes, XY bias, combined energy, and pulse under the normal Module control-output paths so the console can drive other examples through expressions.

## Scientific UI Kit

`UI_Kit` demonstrates a slider, momentary button, toggle, XY pad, readouts, and Scientifica typography. Its reusable source is `_shared/ui/scientific_ui.hlsli` inside the bundled modules directory. The shared chrome is deliberately black, white, and neutral gray. Every control has a constant symmetric 1.5-pixel inset frame. The Pulse button reads only its own pressed bit and flashes only its own face while held; slider fill, toggle value, and selected tool mode show their own meaningful state. None of those visuals depend on rollover flags.

All UI text is built from Scientifica's regular glyph data. Titles get a small synthetic edge weight from the same regular face instead of switching to the bold font. `Font_Sampler` shows Regular, Light Edge, Clean Edge, and Full Edge side by side; `Custom Edge` can be dragged from 0 to 1 for finer comparison. The current Interaction Lab recommendation is Clean Edge at `0.28`.

The host owns normalized hit rectangles and writes ordinary Module parameters. HLSL owns the complete visual treatment. Resize the output freely: the layout is authored in a 960 x 540 design space and follows the Module output.

`UI_Style_Tuner` exposes the title, section, and body typography roles plus the shared padding, section gap, control height, and control gap. Its saved values are the defaults in `_shared/ui/sui_typography.hlsli` and `sui_layout.hlsli`; adjust them there only after reviewing the tuner at several panel sizes.

Project presets `Dense Instrument` and `Airy Review` provide compact and spacious interface checks without changing source files.

On Sentinel 0.5.32 or newer, UI Modules can opt into a full-frame authored panel:

```yaml
panel:
  mode: canvas
  output: UI
  resolution: follow_panel
```

Canvas keeps the dock tab and removes Sentinel chrome below it. `follow_panel` independently makes the real Module resolution track the panel content. The graph and View menus retain a Standard/Canvas override for recovery. See `knowledge/ui-authoring.md` for the complete contract and proof workflow.

## Spline Editor

`Spline_Editor` starts with a four-knot cubic path and publishes four typed data outputs. Its `Sampled Path` output is already linked to `Spline_Output`, showing how an authored editing tool can feed another Module.

Controls:

- `V` or SELECT: selection tool.
- `P` or PEN: pen tool; click the canvas to append a knot.
- Drag an anchor to move it. Its handles follow as a rigid set.
- Drag either handle to shape the cubic segment.
- Drag empty canvas space to marquee-select. Shift adds and Control subtracts.
- `T` or TANGENT cycles the selected knot between free, aligned, and mirrored behavior.
- `O` or CLOSE toggles the active path between open and closed.
- Backspace or DELETE removes selected knots.
- Enter advances to the next of eight spline lanes.
- Escape cancels an active edit. `Ctrl+Z` undoes and `Ctrl+Shift+Z` redoes committed drags.

Data outputs:

- `Spline Headers`: first knot, count, closed flag, and active flag for eight paths.
- `Spline Knots`: anchors, handles, ids, tangent modes, selection flags, and activity.
- `Sampled Path`: 512 PNode-compatible records for downstream renderers.
- `Editor Selection`: compact selection and tangent metadata.

The durable authored state is `spline_knots`; transient interaction, snapshots, headers, samples, and selection records are separate passes. Selection is intentionally local to the editor because knots are sub-object records, while drag edits still participate in Sentinel's viewport transaction and undo system.

`Path Weight` is an ordinary preset-safe appearance control. Project presets `Spline Default Wave` and `Spline Offset Wave` restore both this parameter and the full durable knot buffer, so their geometry survives project reload.

## 3D Transform Gizmo Lab

`Gizmo_Lab` renders twelve selectable SDF objects and publishes their durable transforms. Selection uses Module-provided ray-query descriptors and the host's standard multiple-selection state.

Controls:

- Click an object to select it; Shift-click adds or removes objects.
- Drag a selected object body to translate it in the view plane.
- `1` or MOVE selects translation. Drag an axis arrow.
- In MOVE mode, the three small two-color squares are the visible XY, YZ, and ZX plane handles. A visible axis line always wins when projected handles overlap.
- `2` or ROT selects rotation. Drag a colored screen-space ring.
- `3` or SCALE selects scaling. Drag an axis or the amber center for uniform scale.
- `4` or LOCAL switches world/local axes.
- Escape cancels the active transform. `Ctrl+Z` undoes and `Ctrl+Shift+Z` redoes a committed transform.

Multi-selection transforms use the average selected-object pivot. Translation applies one shared delta, rotation orbits every object around the shared pivot while updating its orientation, and scaling expands or contracts both positions and object scale around that pivot. The gizmo is screen-space sized for stable handles at any camera distance. Axis motion follows the camera-projected line that is actually drawn, with fixed screen-space sensitivity so near-view-aligned axes cannot jump. Handle acquisition occurs on mouse-down and remains owned until commit or cancel, including fast pointer motion and pauses while the button is held.

The scene, toolbar, and objects use the shared monochrome theme. X/Y/Z handles remain red, green, and blue because those colors carry directional meaning. The blue Z ring uses the corrected screen-space sign, while red X and green Y retain their existing direction.

Data outputs:

- `Scene Objects`: durable position, rotation, scale, object id, shape kind, and flags for sixteen slots.
- `Gizmo State`: mode, world/local state, active handle, pointer state, pivot, and active object.
- Sentinel also exposes the declared viewport descriptors and pick result through the standard selection provider.

Project presets `Gizmo Grid` and `Gizmo Offset Lead` restore the complete durable object buffer in addition to the authored transform and camera controls.

## Architecture and scope

Everything in this project is authored content: YAML manifests, HLSL passes, persistent structured buffers, typed data ports, and a `.sentinel` graph. No Sentinel application source, IPC command, native widget, or engine feature was added or changed.

This is a foundation rather than a full DCC toolset. It does not yet include snapping, numeric transform entry, spline segment insertion, depth-tested gizmo fading, or host-mirrored sub-object selection. Those can be layered on as additional Module passes and controls without changing the application. The compact, portable evidence set in `proof/` records the current Canvas, interaction, undo, picking, Scene Group, and preset checks.
