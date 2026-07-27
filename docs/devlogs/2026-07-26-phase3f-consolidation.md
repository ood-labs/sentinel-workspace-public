---
type: devlog
date: 2026-07-26
phase: 3
subphase: 3F
status: in-progress
approval: pending
summary: "Lab consolidated to four stations; every group row driven by real mouse; presets re-saved; cold load and a re-measured profile pass. Hands-on gesture pass outstanding."
---

# Phase 3F - Consolidation, Presets, And Hand-Off

All seven pass criteria are met and recorded below, two of them corrected after landing: criterion 2
turned out to be provable as written, and criterion 5's original figure was not a sound measurement
and has been retaken under Amendment 4. The **hands-on interaction pass remains open** - it is the
phase doc's planned Tier-3 operator gate, and no gesture-dependent criterion is marked complete
without it.

| # | Criterion | Result |
| --- | --- | --- |
| 1 | Four stations plus `Spline_Output`; three retired module dirs deleted | Seven v1 nodes destroyed; lab is `Style_Authority`, `Motion_Console`, `Spline_Desk`, `Gizmo_Desk` + `Spline_Output`, all healthy. `ui_kit_gallery`, `ui_style_tuner`, `font_style_sampler` and their bundled copies deleted |
| 2 | Every exposed group control tested live; 4-8 per group | **Met as written.** 19 of 24 group Properties rows driven by real ImGui mouse clicks in the open panel; the 5 that did not change are colour and XY compounds whose row opens a picker. Logical counts 5 / 6 / 6 / 7. See below |
| 3 | No camera parameter on any Scene Group | Asserted programmatically across all four groups: none |
| 4 | Every surviving preset recalls with non-empty `applied[]`, empty `skipped[]` | 6 presets, `applied` 8/8/8/8/11/11, `skipped` 0 for all. 8 node presets and 1 group preset retired, listed below |
| 5 | Total frame cost at or below the 3A ceiling | **Met, re-measured under Amendment 4.** Worst of three panel states is 11.02 ms mean / 12.48 ms max, against 14.88 ms. The original single-state figure was not a sound measurement; see below |
| 6 | Clean checkout cold-loads, all stations healthy with frames climbing | Fresh copy with `shader_cache` and `.sentinel` state stripped, loaded from a temp path: all five healthy, frames climbing on a second sample |
| 7 | `proof_bundle`; README rewritten; `lessons.md` updated | `captures/proof_20260726_162349/`; README rewritten around four stations and the v3 language; six lessons added |

## Criterion 2, met as written

This was first recorded as a deviation on the grounds that "no MCP call can click a Properties row",
with each control exercised by writing to its `/sentinel/groups/<id>/parameters/<name>` path
instead. That premise is wrong. `sentinel_ui action=click method=mouse` performs real ImGui mouse
injection against any widget the tree reports a rect for, and
`sentinel_ui action=click path=Graph/Nodes/<annotation_id>` selects a Scene Group and opens its
group Properties panel. Both were used, and **19 of the 24 exposed group rows changed their value
from the panel itself**:

| Group | Result |
| --- | --- |
| 01 - SPLINE DESK | 1 slider + 3 bool rows, all driven |
| 02 - GIZMO DESK | 3 sliders + 2 bool rows, all driven |
| 03 - MOTION CONSOLE | 2 sliders + 2 bool rows, all driven |
| 04 - STYLE AUTHORITY | 6 sliders, all driven |

The 5 rows that did not change are the colour and XY compounds. Their row is a swatch or pad that
opens a picker rather than accepting a value from a single click, so a click lands on the row and
changes nothing. That is the widget behaving correctly, not a dead control, and each of those
compounds was separately confirmed to drive its member parameter through the group path.

The three caveats that produce a false pass are worth carrying forward: the widget path needs its
window prefix (`Properties/Specimen/##demo_toggle`), `action=set` and a `click` **without**
`method: mouse` both report success while changing nothing, and every result needs a StateTree
readback to confirm.

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

## Criterion 5, and why the first measurement did not count

Style Authority read 0.58 ms early in the session and 8.7 ms later with no code change. Disabling
its entire primitives grid - roughly forty percent of its drawing - changed the number by nothing,
and closing its floating window changed nothing either. A bounding reject was added to the specimen
grid anyway (proven pixel-identical, 0 of 1,112,375 differing); it is structurally right and
produced no measurable CPU-side gain, which is recorded rather than claimed as a win.

The cause was isolated afterwards, and it invalidates the original criterion-5 figure. With the
graph unchanged, opening a second station's window and closing the first moved `Style_Authority`
from **10.29 ms to 4.25 ms** and `pipeline_ms` from **15.87 ms to 9.63 ms**, while `input_ms` rose
from 1.1 ms to 6.65 ms. The cost moved into the UI bucket rather than disappearing. So the recorded
"10.086 ms mean over 5 samples" was five samples of one panel state, and in a different state the
same graph sat **above** the 14.88 ms ceiling the criterion calls a hard stop.

Re-measured under Amendment 4, five samples in each of three panel states, after the layout fixes
below:

| Active canvas panel | `pipeline_ms` mean | min | max | `cook_hz` | healthy |
| --- | --- | --- | --- | --- | --- |
| Style Authority | 11.02 | 10.05 | 12.48 | 60-61 | 5/5 |
| Motion Console | 9.74 | 9.18 | 10.82 | 60-61 | 5/5 |
| Gizmo Desk | 9.00 | 8.04 | 9.31 | 60 | 5/5 |

Worst case 12.48 ms against 14.88 ms, in the worst state rather than a convenient one. Cadence holds
at 60 Hz throughout, which is the assertion that actually survives the instrument's weakness and is
what `tools/interaction-lab-guards.py` checks.

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

**One Scene Group preset was also lost, and this table originally missed it.** Diffing the project
file at `ba7d722` against HEAD shows the phase started with **one** group preset, not the four the
phase doc's hazard note predicted: `Motion Reference` on the Motion Console group, carrying
`pipelineBypass: {"Motion_Console": true}` plus the v1 parameter set. It is gone at HEAD with no
replacement. Retired deliberately rather than migrated: it stored a bypass of the very station the
group exists to expose, and its parameter payload predates the rebuild. The name survives as a
**node** preset under `module:motion_console`, which is what the table above records - the two are
different objects and conflating them is what hid the loss. The node counts were 8 before and 6
after, which the table does account for correctly.

## Bundle

`bundle_modules` never reuses an existing bundled directory - it mints `_1`, then `_2`. Every
station bundle was deleted and the project saved once, giving five directories matching the five
nodes and relative `project_dir` values throughout. `_shared/` is still not copied by the bundler
(2026-07-05 lesson); its `sui3_*` files were verified byte-identical to the workspace copies.

The bundled `Spline_Output` is byte-identical to `modules/spline_render`, which is the point of
keeping it: the data contract survived the rebuild without the consumer changing.

## Post-landing audit + fixes

Three parallel Explore agents were dispatched over `ba7d722..4ac99c4` (code correctness, spec and
plan alignment, proof quality). **None of the three returned a report** across repeated prompts,
including a final "send whatever you have". Recorded as a gap rather than papered over: the audit
below is the operator's review plus direct measurement, not a three-agent synthesis, and it is
therefore narrower than the skill intends.

What that review found, all of it verified against the live graph rather than by reading:

**Ship-blocking, fixed.** Every XY pad disagreed with itself. The reticle was drawn at the raw
parameter while the readout beside it printed `1 - raw`: a pad sitting 68% down its well, captioned
`0.32`. The "flip exactly once, at publish" rule is replaced with **zero flips** - Properties row,
drawn reticle, printed readout and published control output all now carry the host parameter
unmodified. Zero flips is checkable in a way "once" never was: any `1.0 -` on a pad component is a
bug on sight. The *direction* is the host's business; 3A derived it by measuring where a renderer
drew the marker, which measures the renderer. `sui3_core.hlsli`, `sui3_controls.hlsli`,
`style_authority/state.hlsl`, `motion_console/{render,lfo_compute}.hlsl`.

**Ship-blocking, fixed.** Style Authority's four host controls hung off the left of the sheet. The
control rects are static normalized values in the manifest; `outer_padding` is published in pixels
and was then multiplied *again* by the body glyph scale, so at padding 36 / body 2 the frame and
text column sat 50px right of the control column. Padding is now spent in pixels as published, the
frame is clamped clear of the control column at every setting, and the text column is the control
column. `style_authority/layout.hlsli`.

**Ship-blocking, fixed.** Section captions printed through their controls. Each renders at the
section scale while the fit test and the y-offset were both passed the *body* scale, so at section 2
/ body 1 the glyphs were twice the reserved height. `saCapFits` becomes `saCapScale`, returning the
largest scale the gap can hold and dropping only when even 1x will not fit, so raising Section Scale
can never silently delete a caption. `style_authority/{layout.hlsli,render.hlsl}`.

**Regression introduced by this sub-phase, fixed.** Saved `body_scale` was 2.0, tuned while the
parameter was inert. Wiring it here made the stored value suddenly double every body glyph. Set to
1.0 in `interaction_lab.sentinel`. This is the clearest cost of proving a control with a pixel diff:
"4 changed pixels to 139,985" proves the value now reaches the layout, and says nothing about
whether the result is legible.

**Fixed.** The `Motion Reference` Scene Group preset loss, recorded above.

**Added.** `tools/interaction-lab-guards.py` - 29 assertions over the live graph, one per defect
this phase fixed, so each fix has a guard instead of a one-shot number in a devlog. It found two
things on its own first runs: the generated UI headers going stale under a manifest edit, and 3E's
claim that a numeric orbit round-trips *bit-identically*. Rotation does; position returns to
**2.98e-07**, which is float32 round-off through sin/cos, not the bit. The guard asserts the two
separately.

**Considered and rejected.** The `Gizmo State` data output publishes an 80-byte schema over a
96-byte buffer, since `auto_latch`/`auto_pad` were added after the schema was frozen. Checked
against the live port: `capture_data_port` reports `elementSize: 96` from the buffer and decodes the
declared fields correctly, so nothing misreads. Left alone rather than churn a published schema for
a cosmetic completeness gain.

**Considered and rejected.** `spline_desk`'s three `type: button` parameters read as dead Properties
rows, and deleting them was considered. They are not dead: each backs a `viewport.controls` entry of
`kind: button` whose `down` bit the shader reads, so the parameter declaration is load-bearing even
though pressing the Properties row does nothing useful. Documented in the manifest rather than
removed.

**Deferred.** `docs/state.md` is stale - its body still says "3C - Motion Console is active" and
names the 3B devlog as the latest. That belongs to the phase close, not to an audit.

## Open: the hands-on interaction pass

Still outstanding, and deliberately not self-approved. Needs an operator at the mouse:

1. **Spline Desk (3D criterion 1)** - drag an anchor, drag a handle, marquee-select, and the
   keyboard bindings.
2. **Gizmo Desk (3E criterion 1)** - drag the gizmo itself. `pick` and shift-extend are already
   proven over MCP with `source: User`; only the drag is unreachable, because
   `sentinel_viewport action=edit` drives the host object-edit path and this module renders its own
   gizmo from raw events.
3. **Style Authority (3B.3)** - hover feedback on the accent.
4. **Pad Y direction against the host widget.** Every surface the modules own now agrees, and this
   was verified live (`demo_pad_y 0.9` gives readout `00.90`, published `pad_y 0.90`, reticle 90%
   down the well). What cannot be checked from here is the host's own Properties pad: if dragging
   its dot *down* makes the number go *up*, the host widget is mirrored against the module's and the
   fix is a single inversion in the draw call. One drag settles it.

Item 4 on the previous version of this list - confirming each exposed Scene Group row drives its
control from the panel - is **done** and moved into criterion 2 above. Real mouse injection reaches
Properties rows.

Assert on `edit_transaction_active` and `capture_owner` changing during a real drag. Note the phase
doc's "non-zero delivered gesture count" cannot be satisfied: `sentinel_viewport action=info`
publishes no gesture counter.

`tools/interaction-lab-guards.py` prints these four as explicit `SKIP` lines with their reason, so
the gap stays visible in the proof output instead of being absent from it.

## The recorder that had to be stopped from passing itself

The four `SKIP` lines above are honest but inert, so `tools/interaction-lab-handson.py` was written
to turn the operator pass into an assertion: it polls the live ports, recognises each gesture from
its signature, and writes a record saying *what moved*, not that someone said they moved it.

Its first run recorded three gestures with nobody touching the mouse. Firing `do_tangent`,
`do_nudge`, `do_next_lane` and `do_undo` through the automation doors produced:

```
RECORDED  3D.1 spline anchor drag   knot 0 anchor [0.195, 0.609] -> [0.255, 0.489], handles followed
RECORDED  3D.1 spline keyboard      active_lane 0.0 -> 1.0
RECORDED  3E.1 gizmo drag           dragging=1 handle=1 mode=1, objects [7] moved
```

Every line is true and every line is worthless. `do_nudge` moves an anchor and drags its handles
along exactly as a pointer drag does, so the state signature alone cannot tell them apart. A tool
built to certify the one thing that cannot be automated had certified automation.

Three gates now stand between a state change and a recorded gesture:

1. **Pointer command codes.** A spline geometry change counts only when `last_command` is 1, 2 or 3,
   the three codes a pointer can produce. Every door fires a different code.
2. **Door poison.** Any sample taken while a door is held, or within six samples after, is
   inadmissible. Doors latch until the caller clears them, so polling can see them.
3. **Run-level taint.** Polling cannot see a door set and cleared between two samples, so a door
   seen at all voids the *entire* record rather than one window, and the JSON carries
   `tainted: true`. A pass is admissible only when zero doors fired end to end.

The gizmo branch additionally requires the `dragging` flag to transition 0 to 1 inside the watch
window, so a latched flag from an earlier session cannot be credited.

Re-running the identical door sequence against the hardened recorder: **zero gestures recorded,
record stamped tainted, exit 6**. The second run set and cleared each door in back-to-back MCP
calls, faster than the 150 ms poll, and the taint still caught it.

What this does not do is distinguish a `do_tangent` write from the T key once the door has closed.
Nothing on any port can. The guarantee is narrower and stated in the tool: the record is valid only
if no door fired for the whole watch, and the operator's presence is the warrant for the keyboard
line.

**Restoring what the test moved.** The door fires left the station on lane 3 with `tangent_cycle`
and `close_path` latched, and the knots nudged. `do_reset` restored the seeded lane geometry;
`do_next_lane` cycled 3 to 0 through the wrap; both toggles went back to default.

That exposed a second defect. The guard suite dropped to 29 passed / **1 failed** on
`undo: close sets the closed bit`, which had passed all session. The undo guard reads lane 0's knots
but `do_close` acts on the *active* lane, so the guard was silently inheriting ambient state and
would have failed for a reason unrelated to undo. It now asserts `active_lane == 0` as a named
precondition and skips its four assertions rather than reporting a misleading failure.

Guard suite after both fixes: **30 passed, 0 failed, 4 skipped.**
