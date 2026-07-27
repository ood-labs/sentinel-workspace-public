---
type: phase
phase: 5
title: "Official example UI port to the sui3 kit"
status: planned
approval: pending
created: 2026-07-27
updated: 2026-07-27
summary: "Move the shipped examples' authored panels off the v1 sui_* kit onto sui3, so the public collection reads as one instrument family instead of two generations."
---

# Phase 5 - Official Example UI Port

## Overview

Interaction Lab is the only official example on the sui3 kit. The other six
canvas panels in the public collection are still on v1 `sui_*`, which is the
visual gap an operator sees immediately when moving between examples. This phase
ports them.

This is a **presentation and control-design phase, not a feature phase**. No new
capability ships. What ships is that the seven public projects stop looking like
two different products.

## Motivation

Three things force this now rather than later.

**The collection is visibly inconsistent.** Interaction Lab draws hairline
frames, a real type scale, graticules, registration marks and accent discipline.
The v1 panels draw a flat rail of identical widgets. Placed side by side in
Showcase Gallery, which is literally a gallery of the others, the difference
reads as unfinished rather than varied.

**Both kits just diverged and reconverged on a bug.** The XY pad Y-direction
defect had to be fixed twice on 2026-07-27, once in `sui3PadPoint` and once in
`suiXYPad` across 16 bundled copies. Every future fix to shared drawing behaviour
costs double while two kits are live in the public set.

**The proof story is now much stronger on sui3.** `sentinel_ui action=
viewport_control_drag`, added in the 0.5.49-era build, drives host-declared
`viewport.controls` directly. Every control on a ported panel can be proven by a
real synthetic gesture rather than a parameter readback, which is the difference
between "the panel draws" and "the panel works". Phase 3 shipped a green suite
over a broken pad twice because only the former was asserted.

## Problem statement

Measured 2026-07-27, not assumed.

| Project | Module | Declared canvas controls | Kit |
| --- | --- | --- | --- |
| topographic_hud | `signal` | 16 slider | v1 |
| strata | `strata_control` | 12 slider, 1 toggle | v1 |
| desert_totem | `dada_control` | 12 slider | v1 |
| living_room_sdf | `LR_Furnishings` | 5 button, 1 toggle | v1 |
| living_room_sdf | `LR_Lighting` | 4 slider | v1 |
| showcase_gallery | `Fruit_LFO` | 13 slider, 1 button, 1 toggle, 1 xypad | v1 |
| showcase_gallery | copies of the five above | as above | v1 |
| interaction_lab | 4 stations | 16 slider, 3 toggle, 4 button, 2 xypad | **sui3** |

Out of scope, stated so the omission is deliberate rather than forgotten:

- `face_collage`, `industrial_lattice`, `procedural_building_system` declare no
  canvas controls at all. Nothing to port.
- `fruit_atlas_scatter` no longer declares any, since its `Fruit_LFO` was an
  orphan and was removed in `e93261b`. It still bundles the v1 kit; that copy is
  left in place because non-official projects share the bundle shape.
- `interaction_lab` is already sui3.

### The control-design problem underneath

A 16-slider rail is not a styling defect. `CLAUDE.md` is explicit: *"Do not build
authored Canvas panels that merely duplicate Properties sliders... Keep exact
numeric shaping, colors, toggles, and ordinary enums in Properties. Use viewport
UI for interactions Properties cannot express well."*

Porting a 16-slider rail verbatim to sui3 yields a better-looking violation of
the project's own doctrine. So each panel gets a control-set review as part of
its port. This phase does **not** silently delete controls; see the Autonomy
section for how that decision is gated.

## Deliverables

| ID | Deliverable | Proof |
| --- | --- | --- |
| D1 | sui3 headers bundled into each in-scope project's `modules/_shared/ui/` | bundle-identity check passes against the workspace kit |
| D2 | Six modules' render passes rewritten against sui3 | `module-ui.ps1` validate + `compile_check` clean |
| D3 | Every ported control proven by a real synthetic gesture | drag/click writes the expected value AND the drawn state tracks it |
| D4 | Control sets reviewed against the Properties-duplication rule | per-project written verdict, with any removal explicitly approved |
| D5 | Scene Group exposed controls still 6-10 and still correct | group Properties readback per project |
| D6 | Presets migrated or explicitly retired | `sentinel_preset recall` returns non-empty `applied[]` |
| D7 | Proof bundles regenerated | `proof/` refreshed per project |
| D8 | Public promotion still validates | `promote-public.ps1` dry run clean per project |
| D9 | A reusable example-UI guard harness | re-runnable script, each guard watched failing |

## Sub-phases

Ordered so the riskiest structural work happens once, early, and the aggregator
happens last.

### 5A - Kit preparation and harness

Bundle sui3 into the in-scope projects and generalize the guard harness so each
subsequent sub-phase has a proof mechanism ready.

- Copy `sui3_core/controls/text/theme/events` into each in-scope project bundle.
- Generalize `tools/interaction-lab-guards.py`'s pad/gesture machinery into a
  project-agnostic `tools/example-ui-guards.py` taking a project + control table.
- Confirm `viewport_control_drag` behaviour holds outside Interaction Lab:
  control-local 0..1 coordinates, `value = (x, 1-y)`, focused viewport required.

**Pass criteria**

1. Every in-scope project bundle contains the sui3 headers, byte-identical to
   `modules/_shared/ui/`.
2. The harness drives at least one control on one unported project and correctly
   reports it as **not yet ported** rather than passing vacuously.
3. The `viewport_control_drag` contract is re-confirmed on a v1 panel, with the
   measured numbers recorded.

### 5B - `signal` (topographic_hud)

The worst offender at 16 sliders, and therefore the one that sets the pattern.

**Pass criteria**

1. Panel renders on sui3 with a real type scale, hairline frames and accent used
   sparingly; no v1 header remains in its includes.
2. Every surviving canvas control is exercised by a synthetic gesture; the bound
   parameter reaches the expected value and a capture shows the drawn state at
   the gestured position.
3. A written control verdict exists for all 16 sliders: kept on canvas with a
   reason Properties cannot serve, or moved to Properties.
4. The Scene Group still exposes 6-10 controls and each still resolves.
5. Project loads healthy, all nodes cooking, proof bundle regenerated.

### 5C - `strata_control` (strata)

Same shape as 5B, plus a toggle. **Pass criteria** as 5B, applied to 12 sliders
and 1 toggle.

### 5D - `dada_control` (desert_totem)

**Pass criteria** as 5B, applied to 12 sliders.

### 5E - `LR_Furnishings` and `LR_Lighting` (living_room_sdf)

The most interesting case: `LR_Furnishings`' 5 buttons select furnishings, which
is genuinely spatial and should stay on canvas. This sub-phase is the positive
example of the control-design rule rather than the corrective one.

**Pass criteria**

1. Both modules on sui3.
2. Furnishing selection proven by synthetic click: the selected furnishing
   changes and the panel's drawn selection state follows.
3. `LR_Lighting`'s 4 sliders get the same control verdict as 5B criterion 3.
4. Direct manipulation of furnishings in the 3D view still works after the port,
   proven by an actual edit, not by the module compiling.
5. Group controls, presets, proof bundle as 5B.

### 5F - `Fruit_LFO` (showcase_gallery)

The only module carrying an `xypad`, so it is the one that proves the pad fix
inside a shipped example rather than only in the lab.

**Pass criteria**

1. Module on sui3.
2. The pad is proven by a real drag at two asymmetric points: the reticle lands
   under the drag, matching `value = (x, 1-y)` within tolerance.
3. Criteria 3-5 of 5B for the 13 sliders, button and toggle.

### 5G - Showcase Gallery resync and collection review

The gallery bundles copies of the other projects' modules. It cannot be ported
independently; it must be resynced after 5B-5F land.

**Pass criteria**

1. Every gallery module copy is byte-identical to its source project's module.
2. All seven groups load, the groups-mode Mux still switches between them, and
   `solo_upstream` still holds non-selected looks.
3. Side-by-side captures of all seven looks show one visual family.
4. `promote-public.ps1` dry run clean for all in-scope projects.
5. Full guard suite green, with any skip named and justified.

## Files summary

**New**

- `tools/example-ui-guards.py`
- `docs/devlogs/` entries per sub-phase

**Modified**

- `projects/{topographic_hud,strata,desert_totem,living_room_sdf,showcase_gallery}/modules/*/render.hlsl` and layout includes
- the same projects' `manifest.yaml` where control rects move
- each in-scope project's `modules/_shared/ui/` (sui3 headers added)
- each in-scope project's `README.md` and `proof/`
- `docs/state.md`, `docs/implementation-plan.md`

**Unchanged, deliberately**

- `modules/_shared/ui/sui_*.hlsli` - the v1 kit stays for non-official projects
- `projects/autopsia`, all `au_*` modules
- `projects/interaction_lab` - already sui3
- `face_collage`, `industrial_lattice`, `procedural_building_system` - no canvas controls

## Implementation order

5A, then 5B, 5C, 5D, 5E, 5F in any order once 5A lands, then 5G last.

5B first among the panels because it is the largest rail and its control verdict
sets the precedent the others follow.

## Verification plan

Every sub-phase proves in this order, and a later step never substitutes for an
earlier one:

1. `compile_check` on the module directory.
2. `tools/module-ui.ps1` validate.
3. Load the project, confirm every node healthy with frames climbing.
4. **Gesture proof**: `sentinel_ui action=viewport_control_drag` (or `click`) on
   every declared control; assert the bound parameter reaches the expected value
   AND a capture shows the drawn state at the gestured position. Both halves are
   required; Phase 3 proved that either alone passes over a broken control.
5. Group Properties readback for exposed controls.
6. `sentinel_preset recall` for each project preset.
7. Proof bundle regenerated.
8. `promote-public.ps1` dry run.

Guards are only evidence once watched failing. Every guard added in this phase is
run against a deliberately broken variant before it is kept, and the failing
numbers are recorded in the devlog.

## Operational hazards

**Repeat project loads crash the app.** Reported as
`ood-labs/sentinel-bugs#88`: loading the same project twice in one session is a
deterministic access violation in `d3d11.dll` on the StreamDiff CUDA/D3D11
interop teardown path. This phase loads projects constantly, so: **never load the
same project twice in one Sentinel session.** Relaunch between iterations on a
project, via an interactive `/IT` scheduled task with the resulting process
SessionId verified as non-zero. Budget for the relaunch cost in every sub-phase.

**Bundled kits diverge silently.** Every project carries its own
`modules/_shared/ui/`. Editing only the workspace copy changes nothing at
runtime, and the failure mode is that the fix appears not to work. This cost real
time on 2026-07-27. Every kit edit updates workspace and bundle together, and the
bundle-identity guard is run before concluding a change did not take.

**Rebuilt modules orphan presets.** Phase 3 hit this. Each ported project's group
and node presets are recalled and checked, then migrated or explicitly retired.

**Panels follow the dock.** `follow_panel` modules reflow with panel size, so
layout that reads well at one dock size can collide at another. Each ported panel
is checked at a small and a large panel size before its sub-phase closes.

## Autonomy and human-in-the-loop

### Tier 1 - self-serve, never stop

- Aesthetic verdicts on a ported panel. Log the verdict and a capture in the
  devlog, commit `approval: pending`, continue.
- Per-sub-phase approval cadence.
- Layout, spacing, type scale, hairline and graticule choices within the sui3
  vocabulary.
- Relaunching Sentinel between project loads.

### Tier 2 - conditional-proceed, pre-authorized with a testable rule

- **Moving a canvas control to Properties.** Proceed when ALL hold: the control
  is a plain scalar or enum; it has no spatial meaning on the panel; and removing
  it leaves the panel with at least one genuinely spatial or gestural control.
  Otherwise stop and ask. Record the verdict for every control either way.
- **Adjusting a control's rect** to fit the sui3 layout: proceed, provided
  `module-ui.ps1` validates and the gesture proof still passes.
- **Retiring a preset** that no longer resolves after the port: proceed when the
  preset targets parameters that no longer exist, and say so in the devlog.
  Migrate rather than retire whenever the parameters still exist.

### Tier 3 - hard stop

- Removing the **last** canvas control from a panel, which would delete the
  panel's reason to exist.
- Any change to a shipped example's visual identity beyond the kit swap: new
  colours outside the theme, restructured composition, changed output resolution.
- Editing `docs/official-example-standard.md` or the governing spec.
- Deleting or restructuring a Scene Group.
- A gesture-dependent criterion that cannot be proven automatically. It is
  recorded as unproven and left for an operator pass; it is never self-approved.
- Promotion to the public repository. This phase prepares and validates; the
  promotion itself is a separate, explicitly authorized step.

## Dependencies

- sui3 kit at `modules/_shared/ui/sui3_*.hlsli`, with the Y-up pad fix
  (`56e326b`) and the v1 equivalent (`d262ae2`).
- `sentinel_ui action=viewport_control_drag`, and its measured contract:
  control-local 0..1 coordinates, `value = (x, 1-y)`, **focused viewport
  required** or the call succeeds silently and writes nothing.
- `tools/module-ui.ps1`, `tools/promote-public.ps1`,
  `tools/official-examples.config.psd1`.
- `tools/interaction-lab-guards.py` as the harness pattern.
- Interaction Lab as the reference implementation of every sui3 idiom.

## Cross-references

- [[phase-3-interaction-lab-v2]] - where the sui3 kit was built
- [[phase-4-data-scope]] - `sui3_trace`, the kit's strip-chart component
- [[official-example-standard]] - the release-readiness contract this must not weaken
- `knowledge/ui-authoring.md` - direct-manipulation doctrine
- `ood-labs/sentinel-bugs#88` - the repeat-load crash constraining the workflow
