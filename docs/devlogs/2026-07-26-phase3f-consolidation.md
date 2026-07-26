---
type: devlog
date: 2026-07-26
phase: 3
subphase: 3F
status: in-progress
approval: pending
summary: "Lab consolidated to four stations; groups rebuilt and every control proven live; presets re-saved; cold load and profile pass. Hands-on gesture pass outstanding."
---

# Phase 3F - Consolidation, Presets, And Hand-Off

Six of the seven pass criteria are met and recorded below. Criterion 2 is met with one stated
deviation, and the **hands-on interaction pass remains open** - it is the phase doc's planned
Tier-3 operator gate, and no gesture-dependent criterion is marked complete without it.

| # | Criterion | Result |
| --- | --- | --- |
| 1 | Four stations plus `Spline_Output`; three retired module dirs deleted | Seven v1 nodes destroyed; lab is `Style_Authority`, `Motion_Console`, `Spline_Desk`, `Gizmo_Desk` + `Spline_Output`, all healthy. `ui_kit_gallery`, `ui_style_tuner`, `font_style_sampler` and their bundled copies deleted |
| 2 | Every exposed group control tested live; 4-8 per group | **27 controls tested, 27 caused a change**, after removing 3 that did not. Logical counts 5 / 6 / 6 / 7. Deviation stated below |
| 3 | No camera parameter on any Scene Group | Asserted programmatically across all four groups: none |
| 4 | Every surviving preset recalls with non-empty `applied[]`, empty `skipped[]` | 6 presets, `applied` 8/8/8/8/11/11, `skipped` 0 for all. 8 orphans retired, listed below |
| 5 | Total frame cost at or below the 3A ceiling | **10.086 ms** mean over 5 samples (9.83-10.55), against 14.88 ms. Under by 4.79 ms, with all five nodes confirmed cooking during the window |
| 6 | Clean checkout cold-loads, all stations healthy with frames climbing | Fresh copy with `shader_cache` and `.sentinel` state stripped, loaded from a temp path: all five healthy, frames climbing on a second sample |
| 7 | `proof_bundle`; README rewritten; `lessons.md` updated | `captures/proof_20260726_162349/`; README rewritten around four stations and the v3 language; six lessons added |

## Criterion 2, and the deviation

The criterion says "tested live in the open Properties panel." No MCP call can click a Properties
row, so each control was exercised by **writing to its `/sentinel/groups/<id>/parameters/<name>`
path** - the same path the Properties row writes - and asserting the member parameter took the value
and the station's render changed. That is the write path and the observable effect; what is not
covered is the row's own widget behaviour, which batches into the hands-on pass.

Motion Console is continuously animated, so a pixel diff there proves nothing: every capture differs
by ~100k pixels whether or not a control works. Its six controls were asserted against **published
control outputs** instead:

- `mute`: `energy` range 0.245-0.660 unmuted, exactly 0.000 muted.
- `master_rate`: 3 / 12 / 34 direction reversals of `lfo1` in a fixed 4 s window at rate 0.25 / 1.0 / 4.0.
- `motion_bias_x/y`: published value equals the value set.
- `burst_trigger`: `burst_env` peaks and `burst_fires` increments.
- `burst_decay`: envelope 0.15 s after the trigger reads 0.000 / 0.298 / 0.667 at decay 0.05 / 0.45 / 0.95.

That sweep also re-confirms **3C criterion 5** on the current build: `pad_y 0.10` publishes
`bias_y 0.900` and `pad_y 0.90` publishes `0.100`. The host pad increases downward, the published
value increases upward, and the flip is applied exactly once.

**Three controls were removed for failing the criterion**, which is the criterion doing its job:

- `nudge_x` / `nudge_y` on Spline Desk - amounts consumed by a separate fire command, so neither
  does anything on its own. A two-step interaction belongs in Properties, not on a curated surface.
- `control_height` on Style Authority - see the defect below.

`orbit_axis` and `orbit_degrees` on Gizmo Desk are arguments to `do_orbit` and likewise move nothing
alone, but unlike nudge they were kept, because they were proven to change the **outcome** of the
action they parameterize: axis Y sends object 1 to `(-1.825, -1.25, 0.570)` and axis Z to
`(-2.006, -1.571, 0.298)` from the same start, with the round trip returning exactly to baseline.

## Defects this sub-phase found

**`type: button` parameters cannot be exposed on a Scene Group at all** -
`Error: Button parameters cannot be exposed`. This is a second, independent reason not to build
actions on button globals, on top of 3C's measurement that the global is a one-way latch. Every v3
action is a bool rising edge or an `int` bank, so all of them exposed cleanly.

**Closing a path could never be undone.** Undo preserved the entire `flags` word so that undo would
not disturb the selection - but the closed-path bit lives in `flags` too. Selection is view state; a
closed path is document state. Now only bit 0 is preserved, and undo reverses close and tangent with
the knot records returning exactly to their prior values.

**Style Authority published a metric it never used.** `body_scale` was published, printed in the
station's own readout table, and never passed into `saLayout`. The one station whose entire claim is
"what you see is what the rest of the graph receives" was not applying one of its own values to
itself. Now wired: the control went from 4 changed pixels to 139,985. Related and left as-is by
design: glyph scales are integers because the face is a bitmap, so `1.8` renders as `1x` while the
readout prints `1.80`.

**`control_height` cannot do what its name says.** The control rects come from the host's manifest
so that drawing and hit-testing cannot disagree - which is exactly why a published height cannot
resize them. The parameter stays published for downstream consumers and is off the group surface.

## The profile is a CPU wall-clock profiler

Style Authority read 0.58 ms early in the session and 8.7 ms later with no code change. Disabling
its entire primitives grid - roughly forty percent of its drawing - changed the number by nothing,
and closing its floating window changed nothing either. The per-node figure tracks which station
owns the active canvas panel. A bounding reject was added to the specimen grid anyway (proven
pixel-identical, 0 of 1,112,375 differing); it is structurally right and produced no measurable
CPU-side gain, which is recorded rather than claimed as a win.

Also worth stating: an early profile read `0.000 ms` for every node with `framesProcessed = 0` right
after a project load. A profile taken before the graph is cooking is not a measurement.

## Presets

Retired, all eight orphaned onto destroyed v1 identities by the rebuild:

| Identity | Preset | Reason |
| --- | --- | --- |
| `module:UI_Style_Tuner` | Dense Instrument, Airy Review | Module merged into Style Authority; re-saved under `module:style_authority` with the same names and intent |
| `module:Motion_Console` | Balanced Motion, Slow Drift | v1 identity destroyed; Slow Drift re-saved under `module:motion_console`, Balanced Motion superseded by Motion Reference |
| `module:Gizmo_Lab` | Gizmo Grid, Gizmo Offset Lead | Both stored `camera_*` parameters, which must not be recalled from a preset surface; replaced by Gizmo Desk Default |
| `module:Spline_Editor` | Spline Default Wave, Spline Offset Wave | Both carried a 3072-byte knot payload from the v1 buffer layout; the desk seeds its own path and resets via command, so a state-payload preset is redundant |

Three `module:phase89_*` **library** presets belong to an unrelated project and were left untouched.

## Bundle

`bundle_modules` never reuses an existing bundled directory - it mints `_1`, then `_2`. Every
station bundle was deleted and the project saved once, giving five directories matching the five
nodes and relative `project_dir` values throughout. `_shared/` is still not copied by the bundler
(2026-07-05 lesson); its `sui3_*` files were verified byte-identical to the workspace copies.

The bundled `Spline_Output` is byte-identical to `modules/spline_render`, which is the point of
keeping it: the data contract survived the rebuild without the consumer changing.

## Open: the hands-on interaction pass

Still outstanding, and deliberately not self-approved. Needs an operator at the mouse:

1. **Spline Desk (3D criterion 1)** - drag an anchor, drag a handle, marquee-select, and the
   keyboard bindings.
2. **Gizmo Desk (3E criterion 1)** - drag the gizmo itself. `pick` and shift-extend are already
   proven over MCP with `source: User`; only the drag is unreachable, because
   `sentinel_viewport action=edit` drives the host object-edit path and this module renders its own
   gizmo from raw events.
3. **Style Authority (3B.3)** - hover feedback on the accent.
4. **Scene Group Properties rows** - confirm each exposed row drives its control from the panel.

Assert on `edit_transaction_active` and `capture_owner` changing during a real drag. Note the phase
doc's "non-zero delivered gesture count" cannot be satisfied: `sentinel_viewport action=info`
publishes no gesture counter.
