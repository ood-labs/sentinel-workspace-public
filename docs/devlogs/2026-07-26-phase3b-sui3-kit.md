---
type: devlog
date: 2026-07-26
phase: 3
subphase: 3B
status: complete
approval: pending
summary: "3B - sui3_* kit and Style_Authority shipped; six of seven criteria pass with measurements, 3B.3 structurally proven but empirically pending the taste checkpoint. Two real defects found and fixed by measurement: every hairline was a 2px half-intensity straddle, and the METERS bank carried no readable value."
---

## Outcome

The `sui3_*` kit and its proving station, `Style_Authority`, are live and healthy at
1280x720, 81,075 frames, `healthy=true`, `health_reasons=[]`.

**Six of seven pass criteria pass with recorded measurements.** The seventh (3B.3, hover
inertness) is proven structurally but is gesture-dependent, so it is **not** marked
complete — it is batched onto the taste checkpoint, where a human is present anyway.

Two genuine defects were caught by measuring instead of looking. Both would have shipped:
a capture that reads correct to the eye was wrong in both cases.

## The two defects

### 1. Every hairline was 2px at half intensity

The kit's entire premise is "exactly one pixel." A run-width census said otherwise:
the header rule came back as **two adjacent rows at 0.118** where it should have been
one row at 0.220, and the primitive-cell frames split 627 runs of width 1 against 581
of width 2.

Cause: callers pass `P = tid + 0.5`, so pixel centres sit on half-integers, while the
proportional layout hands the primitives integer and fractional edges. A line on an
integer boundary is equidistant from two centres — both get `d = 0.5`, both light at
50%. The "1px hairline" was a 2px smear roughly half the time, at random, depending on
where a rect happened to land.

Fixed in the kit, not per-station, by snapping the **geometry** to `floor(v) + 0.5`
(`sui3Snap` / `sui3Snap2` / `sui3SnapRect` / `sui3HairAt` in `sui3_core.hlsli`). Snapping
the coordinate is the only option: by the time a function receives `d`, the straddle has
already happened.

Two primitives needed more than a wrapper:

- `sui3Brackets` tested `nearX <= 1.0`, counting pixels from an unsnapped rect edge, so
  it silently doubled. Rewritten distance-based.
- `sui3Graticule` and `sui3Ticks` derived mark distance from `frac()`, measured from an
  unsnapped origin, so *every* line straddled. Rewritten to resolve the nearest
  gridline/tick coordinate and snap that.

Radial primitives (`sui3Ring`, `sui3Disc`) are deliberately left unsnapped — a circle's
coverage is genuinely fractional and quantising the radius would flat-spot it.

Result, same scene before and after:

| | before | after |
| --- | --- | --- |
| cell-frame edge run widths | `{1: 627, 2: 581}` | `{1: 1162}` |
| header rule | 2 rows @ 0.118 | 1 row @ 0.231 |

Zero 2px runs remain.

### 2. METERS was the one control you could not read a value off

`sui3_controls.hlsli` opened by claiming "every control renders its own live value …
draws a numeric readout as part of the control." `sui3Meter` does not, and cannot — a
20px meter in a bank of six has nowhere to put digits. PAD, RAIL, STATE and BANK all
printed a number; METERS printed nothing, which is exactly the failure the kit forbids
everywhere else.

Fixed on both sides: the header comment now states the real rule (numeric where there is
room, positional where there is not, and **the caller owes the bank one printed number**),
and the station now prints the seed the six lanes derive from at the bank's right.

## Pass criteria

| # | Criterion | Verdict | Evidence |
| --- | --- | --- | --- |
| 1 | A human can SEE the new language | **pass** | content read + mechanical baseline separation, below |
| 2 | The authority actually governs | **pass** | 12.09% of a *different* station's pixels changed |
| 3 | Hover is inert | **structural only** | no interaction state exists to hover with; empirical pass deferred to checkpoint |
| 4 | Amber means something | **pass** | 0 amber in the toggle rect when off, 464 when on |
| 5 | Legible at 640x360 and 1600x900 | **pass** | `v3_0.png`, `v3_1.png` |
| 6 | `module-ui.ps1 validate` clean | **pass** (see note) | `OK  Style Authority (0 controls)` |
| 7 | Three retired modules not yet deleted | **pass** | untouched on disk |

### 1 — not mistakable for the 3A baseline

Asserted content, all present: 1px hairlines, corner brackets (BRKTS specimen plus every
well, toggle and bank cell), graticules (GRAT specimen plus the PAD's 4x4 interior), and a
live numeric readout on every control — PAD `00.34`/`00.32`, RAIL `00.62`, STATE `ON`,
BANK per-cell digits, METERS `00.62`.

The "could be mistaken for `UI_Kit`" clause is settled mechanically rather than by
assertion:

| | 3A `UI_Kit` | 3B `Style_Authority` |
| --- | --- | --- |
| lit runs exactly 1px | 0.7% | **60.9%** |
| mid-grey widget fill | 37.6% | **2.7%** |
| amber present | 0.000% | 0.169% |
| median run width | 3px | **1px** |

The baseline's 0.000% amber is not a rounding artefact — 3A found `scientific_ui.hlsli:17-20`
defining `SUI_CYAN`, `SUI_BLUE`, `SUI_AMBER` and `SUI_RED` as four identical greys.

### 2 — the authority governs

`UI_Style_Tuner` exposes five parameters whose names match authority control outputs.
Bound all five with `sentinel_expression`, then wrote **only** the authority:

| param | before | after |
| --- | --- | --- |
| `control_height` | 28 | 56 |
| `outer_padding` | 20 | 44 |
| `section_gap` | 14 | 30 |
| `control_gap` | 8 | 18 |
| `title_scale` | 2 | 3 |

The downstream station's own parameters were never written. Its output changed by
**12.09% of pixels across rows 181–1245** — padding, control heights, section gaps and
title scale all visibly retuned (`govern_before.png`, `govern_after.png`, `govern_sbs.png`).
The station is a tool, not a swatch page.

Bindings were cleared and the authority restored to defaults afterwards; `expression list`
returns 0 active.

### 3 — hover, and why it is not marked complete

Structurally, rollover is unreachable rather than merely unused:

- `Style_Authority`'s manifest declares **no** `panel`, `viewport`, `events` or
  `interactions` block, so no pointer event is delivered to it at all.
- **No function in the entire v3 kit takes an interaction-state argument** — grepping for
  a hover/down/pressed parameter across all five headers returns nothing. A v3 control
  *cannot* change appearance on rollover; there is no argument to change it by.
- For contrast, the v1 kit references hover 3 times in `sui_controls.hlsli` and 3 times
  in `sui_interaction.hlsli`.

The criterion as written asks for two captures with the pointer on and off a control.
That is gesture-dependent, and 3A established the Sentinel window is unreachable from this
agent session (`list_windows` empty, `sentinel_screenshot` "No window found"), so the
pointer cannot be driven from here. Per the standing rule, a gesture-dependent criterion
is not marked complete without a hands-on pass. It is batched onto the taste checkpoint.

### 4 — amber is reserved, measured per region

Two captures, `demo_toggle` off/bank 0 against on/bank 2:

| region | OFF | ON |
| --- | --- | --- |
| toggle rect | **0** | 464 |
| bank cell 0 | **789** | 0 |
| bank cell 1 | 0 | 0 |
| bank cell 2 | 0 | **773** |
| bank cell 3 | 0 | 0 |
| RAIL (idle control) | **0** | **0** |
| header + section rules | **0** | **0** |
| PAD value mark | 96 | 96 |

Amber totals 0.167–0.197% of frame. Exactly one bank cell carries it and it moves with
selection; an idle rail and all chrome and typography carry none; the PAD's amber is the
value mark and is correctly selection-invariant.

### 6 — note on what this actually proves

`validate` exits clean, but reports **0 controls**: the station declares no viewport
control rects, so the "rendered rectangles agree with the manifest" half of the criterion
is satisfied vacuously. It will bite properly in 3D/3E, which do declare control rects.

## Cost

Five-sample profile, `Style_Authority` wall time: 1.852, 1.848, 1.865, 1.893, 1.868 ms —
**mean 1.865 ms**. It draws a considerably denser sheet than `Motion_Console`
(13.0 ms mean, still the graph's sole hotspot) at roughly **one seventh** the cost, which
is direct support for the single-tap-glyph decision recorded in `sui3_text.hlsli`.

3B sets no cost bar, but this comfortably clears the 2.0 ms bar 3C must hit.

## State left behind

- Authority restored to published defaults, 1280x720, healthy.
- All governance expressions cleared (0 active).
- No file under `projects/interaction_lab/` modified. The three retired modules remain on
  disk for side-by-side comparison at the checkpoint, per criterion 7.

**Correction.** The first version of this entry claimed the lab was clean after the
governance test. It was not. **Clearing an expression does not restore the parameter's
prior value** — it leaves the last value the driver wrote. `UI_Style_Tuner` was therefore
left at the test values (`control_height` 56, `title_scale` 3, …), which is why the
checkpoint sheet initially showed its title overflowing as "SCIENTIFIC CONTR". Caught
while building the comparison sheet, and it mattered: the checkpoint would have compared
the new station against an old one I had accidentally detuned. All five parameters were
explicitly written back and verified by readback.

Worth carrying into 3C-3F: `sentinel_expression clear` is not an undo. Snapshot the target
with `sentinel_state snapshot` before binding a driver to a station you intend to keep, or
write the originals back by hand afterwards.

## Checkpoint material

`captures/phase3b/CHECKPOINT_old_vs_new.png` — the three retired stations against the new
one at matched width, each annotated with its measured numbers:

| station | lit runs exactly 1px | mid-grey widget fill | amber |
| --- | --- | --- | --- |
| OLD `UI_Kit` | 0.7% | 37.64% | 0.000% |
| OLD `Font_Sampler` | 1.9% | 4.10% | 0.000% |
| OLD `UI_Style_Tuner` | 0.2% | 15.46% | 0.000% |
| NEW `Style_Authority` | **60.9%** | **2.68%** | **0.169%** |

(`captures/` is gitignored, so the sheet is not committed; it is regenerable from the
captures listed above.)

## Checkpoint outcome (2026-07-26)

**Look approved** - "this is actually looking pretty good now". **Gestures confirmed landing**
by the operator: pad, rail, state and bank all respond. That satisfies both halves of what the
phase doc asks the checkpoint for. 3B.3 (hover specifically) remains open and is carried into
the 3F hands-on pass.

The operator caught a real defect at the checkpoint, which is what it exists for: nothing on
the sheet was clickable. See the two commits below.

### The interaction rework, and the architecture lesson

First attempt decoded the raw event stream into a persistent buffer (`28126d6`). It worked and
was **wrong**: a persistent buffer is not a parameter, so it had no undo, no project
save/restore, no presets, no OSC, no expressions. It also re-picked the hit target every event
instead of holding a drag handle, which `ui-authoring.md:99` warns against - a fast drag
leaving the rect silently dropped the edit.

Replaced with host-owned `viewport.controls` (`d52f6f9`), which binds a normalized hit region
to an **ordinary parameter**; the host owns capture, preview and commit, so one drag is one
undo entry. **Net -204/+127 lines.** Everything the hand-rolled version was building came free.

**Carry into 3C-3E: reach for `viewport.controls` before `events`.** Use raw events only for
gestures no control kind expresses. The kinds are `slider`, `button`, `toggle`, `xypad`.

Rects now live in the manifest, compile to `_ui.generated.hlsli`, and the renderer draws from
those same constants, so the host's hit region and the drawn control cannot disagree.
`validate` enforces freshness - it caught one stale generation during the change - and it also
caught two real defects: 28px hit targets below the 32px minimum, and the station publishing
`control_height 28` while drawing 34.

## MEASURED: synthetic input works after all, with caveats

3A recorded pointer injection as dead, forcing "every gesture criterion needs a hand on the
mouse". That is **too pessimistic**. Re-measured:

`sentinel_ui action=click method=mouse` **works**. It flipped `demo_toggle` false -> true,
confirmed in the StateTree, returning `method: imgui_injection`.

Three traps, all of which produce a false pass:

1. The widget path needs the **window prefix**: `Properties/Specimen/##demo_toggle`. The bare
   `Specimen/...` form from `get_tree` errors with "Window not found: Specimen".
2. `action=set` and `action=click` **without** `method: mouse` both returned success and
   changed nothing. A `"method": "direct_activation"` response is NOT proof - verify with a
   StateTree readback every time.
3. It targets a widget by path only. There is **no MCP route to click an arbitrary point inside
   a module preview**: the preview window reports `items: []`, `sentinel_viewport pick` is
   rejected without a `selection` interaction, `edit` needs object descriptors controls do not
   produce, and `CLICK_AT`/`DRAG_AT` appear in `capabilities` with x/y args but have no MCP
   wrapper.

**What this means for 3C-3F.** Because `viewport.controls` binds to parameters, the viewport
and Properties write the SAME state. Everything downstream of a value - publish, render,
control outputs - is automatable through parameters and `capture_at`. Only the hit-region
mapping itself still needs a human. That is a far smaller gap than 3A assumed, and 3C should
retest `method: mouse` against Motion Console's `burst`: if a Properties-side button click
injects correctly, the burst latch becomes automatable too.

## Next

3C - Motion Console.
