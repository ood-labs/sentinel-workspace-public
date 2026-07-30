# Interaction Lab

Interaction Lab is a bundled example project for authored viewport tools. It is four stations,
each a full-panel authored interface that follows its dock, plus one downstream renderer that
exists to prove a data contract and a live Audio In analysis branch.

Load `interaction_lab.sentinel` in Sentinel. Each station is boxed and labeled in the graph;
double-click a Module node to use its viewport.

| Scene Group | Station | What it is for |
| --- | --- | --- |
| `01 - SPLINE DESK` | `Spline_Desk`, `Spline_Output` | Direct point/handle editing, and the data contract that survives a rebuild |
| `02 - GIZMO DESK` | `Gizmo_Desk` | Host-owned selection and a 3D transform gizmo over lit geometry |
| `03 - MOTION CONSOLE` | `Motion_Console` | A compact interface designed around one operator workflow |
| `04 - STYLE AUTHORITY` | `Style_Authority` | The live theme source: every v3 primitive drawn at the published values |

`Scope_Audio` defaults to **Device**, **Loopback**, **Default loopback** so the audio scope and
signal trails work portably without a bundled test file. Silence is a healthy state; play audio on
the Windows default output to exercise the analysis panels.

Scene Groups are flat, never nested, and control-only: the lab is a tool and data-flow reference,
so it has no Group Output endpoint. Each group exposes five to seven curated controls rather than
mirroring its node's internals.

## The v3 language

Every station is built on `_shared/ui/sui3_*.hlsli` and follows the same rules. They are worth
reading as a set, because each one is a decision that was measured rather than assumed.

**Full-panel, extent-driven.** Every station declares
`panel: { mode: canvas, output: <name>, resolution: follow_panel }`, so the render size is whatever
the dock gives it. That means no layout may assume an extent. Geometry is proportional, strokes and
glyphs are in pixels, and text scale steps on integers derived from `min(W/1280, H/720)` — the
smaller axis ratio, because height alone puts giant glyphs in a wide, short dock. The root
`resolution:` remains as a fallback for a hidden or unsized panel.

**Captions are dropped, never overlapped.** A caption is a fixed pixel height sitting in a
normalized gap, so the gap shrinks with the panel while the caption does not. Every station has a
`*CapFits`/`*LabelFits` helper, and a label that cannot fit its gap is not drawn. This single defect
class — a fixed-pixel label placed in a normalized gap — accounted for six separate layout bugs
across the rebuild.

**The host owns the hit rects.** Control rectangles come from `_ui.generated.hlsli`, compiled from
the manifest's `viewport.controls` block by `tools/module-ui.ps1 generate`. The shader draws from
the same numbers the host hit-tests against, so a click cannot land off a control by construction.
`tools/module-ui.ps1 validate` fails if the generated file drifts from the manifest.

**Amber means something.** The accent marks the active selection and established live values, never
hover and never decoration. The only other chroma in the lab is red/green/blue on the gizmo's axis
handles, where the colour carries direction. A hue audit of Gizmo Desk's output finds 0.23%
chromatic pixels, all amber or axis, with the remaining 63 pixels being antialiasing blends between
two palette colours.

**Actions are ordinary parameters, not buttons.** No station drives an action from a `type: button`
parameter global, because that global is a one-way latch that survives `force_reload` — and because
button parameters **cannot be exposed on a Scene Group at all**. Every action is either a bool read
as a rising edge or an `int` on a bank, so it undoes, presets, saves with the project, and takes
OSC. Where a station renders its own clickable plate, the shader reads that control's `down` bit
from the interaction flags rather than the parameter.

**Numbers are attached to what they describe.** Every station prints its live values next to the
control that produces them, read back from the same buffer the control outputs are taken from, so a
readout cannot drift from what the graph receives.

## Spline Desk

`Spline_Desk` edits knots directly: anchors, both handles, tangent continuity, per-lane selection,
marquee, and undo. Selection is amber brackets on the anchor; tangent mode is the terminal's
*shape* — free is an open ring, aligned is a ring plus bar, mirrored is a filled disc — so the mode
is readable without the label.

Controls: `V`/SELECT and `P`/PEN choose the tool; drag an anchor to move it with its handles as a
rigid set, or a handle to shape the segment; drag empty space to marquee-select, Shift adds and
Control subtracts; `T` cycles free/aligned/mirrored; `O` toggles the path closed; Backspace deletes
the selection; Enter advances through eight lanes; Escape cancels; `Ctrl+Z` undoes.

Data outputs — `Spline Headers`, `Spline Knots`, `Sampled Path` (512 PNode-compatible records),
`Editor Selection` — are unchanged from the previous editor.

`Spline_Output` is deliberately unchanged from before the rebuild and is byte-identical to
`modules/Spline_Output`. It consumes the desk's `Sampled Path` port and is the proof the contract
survived: a downstream consumer written against the old editor still works against the new one.

Undo is worth understanding before you copy it. An edit that undo must reverse is **armed on one
cook and executed on the next**, and the snapshot is taken on the arm cook. This is not caution: the
pass graph is a cycle — `snapshot` reads the knots and `update` writes them, while `update` reads
the snapshot and `snapshot` writes it — and the scheduler runs `update` first. A snapshot taken on
the command frame therefore records the state *after* the edit, and undo restores the desk to where
it already is. The arm cook mutates nothing, so it is order-independent by construction.

Undo also restores everything except the selection bit. Selection is view state; a closed path is
document state. Keeping the whole flags word to protect the selection is what made closing a path
the one edit undo could never reverse.

## Gizmo Desk

`Gizmo_Desk` places twelve selectable objects — sphere, box, torus, capsule — on a lit ground plane
and transforms them with a translate/rotate/scale gizmo. Selection is host-owned through a
`ray_query` provider, so `sentinel_viewport action=pick` drives the same path a real click does and
reports `source: User`; shift extends. Multi-selection transforms use one shared pivot, so two
selected objects orbit together while each keeps its own orientation.

Controls: click to select, Shift-click to extend; `1`/`2`/`3` choose move, rotate and scale; `4`
switches world/local; drag an axis arrow, a rotation ring, or the amber centre for uniform scale;
Escape cancels. Handle acquisition happens on mouse-down and is held until commit or cancel, so a
fast drag or a pause mid-gesture cannot lose the handle.

The objects are **raymarched lit solids, not screen-space outlines**. A transform gizmo can only be
judged against shaded geometry, because a rotation and a non-uniform scale are both invisible on a
flat silhouette. Shading is strictly greyscale so the axis colours stay the only chroma.

Two raymarching details generalize. The hit epsilon scales with distance and the step floor is tied
to it, testing `d < eps` rather than `abs(d) < eps`: with a fixed floor, a ray that overshoots the
surface lands inside at a negative distance and marches inward forever, which prints a scatter of
black pixels exactly where a surface faces the camera dead-on. And the selection rim is *blended*
toward amber rather than added — an additive rim on an already-lit body clips the red channel first
and drifts the hue to yellow.

Numeric orbit (`do_orbit` / `orbit_axis` / `orbit_degrees`) applies an exact rotation about the same
shared pivot the drag uses, and it is the only way to transform a selection from OSC, a Conductor
cue, or an expression. It is also the honest reason it exists: no automated call can produce a
pointer drag, so this is the only code path that exercises the transform maths without a hand on the
mouse. It proves the maths and the shared pivot. It does not prove the drag that normally reaches
them, and it is not a substitute for it.

Data outputs: `Scene Objects` (durable transforms for sixteen slots) and `Gizmo State`, plus the
declared viewport descriptors and pick result through the standard selection provider.

## Motion Console

`Motion_Console` is the reference for an interface designed around one operator workflow rather
than a generic dashboard. Four semantic lanes — Prompt, Energy, Camera, Pulse — place live
waveform, numeric state, rate, amplitude and shape together. The master strip, bias pad, burst,
mute and meters sit in a narrow rail because they affect or summarize the whole system.

The reusable lesson is not "make every UI monochrome" or "always use four lanes." It is that every
region earns its space by changing the system or explaining live state.

The XY bias pad applies the host's Y flip exactly once: the host pad increases downward, and the
published `bias_y` increases upward, so `pad_y 0.10` publishes `0.900`. If you copy the pad, verify
that direction rather than assuming it.

Control outputs publish the four lanes, XY bias, combined energy, pulse, the burst envelope and a
burst-fire count, so the console can drive other nodes through expressions.

## Style Authority

`Style_Authority` merges what were three separate stations — a UI kit gallery, a font sampler, and
a style tuner — into one live specimen sheet. It draws every v3 primitive at the currently
published theme and prints the exact values leaving the node beside them.

It is a *source*, not a mock-up: the specimens read the same buffer the control outputs are taken
from. That claim only holds if every published metric actually drives the sheet, which is precisely
what went wrong once — `body_scale` was published, printed in the readout table, and never passed
into the layout function at all. If you add a metric here, make the sheet consume it, or it is a
label rather than a value.

Two honest limits. Glyph scales are integers because the face is a bitmap, so `1.8` renders as `1x`
while the readout prints `1.80`. And `control_height` is published for downstream use but does not
resize this station's own controls, because those rects belong to the host — the same property that
makes clicks land correctly. It is deliberately not on the group's control surface.

All UI text is built from Scientifica's regular glyph data; titles take a small synthetic edge
weight from the same regular face rather than switching to a bold font.

## Extents

Every station is verified legible at 640x360, 1600x900 and 1920x403 in addition to its live dock
extent. Testing a forced extent requires a throwaway node: a panel that is open owns its module's
render size, so editing `resolution:` and reloading does not change it.

One known limit: host control rects are static normalized values, so hit regions scale with the
panel and fall below the 32px minimum somewhere under 1000px wide. The drawn controls remain
correct and aligned; they simply become small targets.

## Performance

Five-sample profile of the whole lab: **10.09 ms** mean, against a 14.88 ms ceiling measured on the
seven-station predecessor.

Read that profile carefully. `sentinel_graph action=profile` is a CPU wall-clock profiler, and the
dominant per-node number tracks *which station currently owns the active canvas panel*, not how much
that station draws. Disabling Style Authority's entire primitives grid — roughly forty percent of
its drawing — changed its number by nothing. Use it to spot a node that has fallen over, not to
tune a shader.

## Architecture and scope

Everything here is authored content: YAML manifests, HLSL passes, persistent structured buffers,
typed data ports, and a `.sentinel` graph. No Sentinel application source, IPC command, native
widget, or engine feature was added or changed.

This is a foundation rather than a full DCC toolset. It does not include snapping, spline segment
insertion, depth-tested gizmo fading, or host-mirrored sub-object selection. Those can be layered on
as additional Module passes and controls without changing the application. Captures and
machine-generated proof bundles are intentionally excluded from the public project.

Numeric transform entry belongs on that deferred list too, and an earlier draft of this file dropped
it from the list without saying so while adding the feature above. It is present, deliberately, for
the reason given there. The rest of the list stands.

## Component map

This is a set of independent teaching stations, not one program-output chain.

| Component | Type | Receives | Publishes or contributes |
| --- | --- | --- | --- |
| `Style_Authority` | Module | Canvas control gestures | responsive style and layout station |
| `Motion_Console` | Module | Canvas gestures and time | scalable LFO panel and scalar control outputs |
| `Spline_Desk` | Module | pointer/keyboard events | durable spline state and sampled path records |
| `Spline_Output` | Module | `Spline_Desk` sampled path | downstream rendered proof of the data contract |
| `Gizmo_Desk` | Module | selection and viewport edits | durable object transforms and camera-aware gizmos |
| `Scope_Audio` | Audio In | Windows default loopback endpoint | PCM, Spectrum, Mel Bands, level, and peak |
| `Data_Scope` | Module | `Scope_Audio` texture/data inputs | auto-ranging low/mid/high traces |
| `Signal_Trails` | Module | scalar expression drivers | four cook-rate trace lanes |

The saved workspace focuses the relevant station rather than defining a Group
Output. Audio In requires no engine pack. Study the interaction contracts and
responsive layout decisions; reimplement the needed interaction in the owning
project instead of copying these station Modules.
