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

Interaction Lab is the only official example on the sui3 kit. The other seven
canvas panels in the public collection are still on v1 `sui_*`, which is the
visual gap an operator sees immediately when moving between examples. This phase
ports them: six modules with declared controls, plus one control-free canvas
panel (`LR_Architecture`) that the controls-only census originally missed.

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
viewport_control_drag`, present in the installed host build, drives host-declared
`viewport.controls` directly. Slider and pad controls on a ported panel can be
proven by a real synthetic gesture rather than a parameter readback, which is the
difference between "the panel draws" and "the panel works". Phase 3 shipped a
green suite over a broken pad twice because only the former was asserted. Button
and toggle gestures have no verified automated route yet; 5A settles what is
provable per control kind before any panel depends on it.

## Problem statement

Measured 2026-07-27, not assumed.

| Project | Module | Declared canvas controls | Kit |
| --- | --- | --- | --- |
| topographic_hud | `signal` | 16 slider | v1 |
| strata | `strata_control` | 12 slider, 1 toggle | v1 |
| desert_totem | `dada_control` | 12 slider | v1 |
| living_room_sdf | `LR_Furnishings` | 5 button, 1 toggle | v1 |
| living_room_sdf | `LR_Lighting` | 4 slider | v1 |
| living_room_sdf | `LR_Architecture` | none (events-only canvas panel) | v1 |
| showcase_gallery | `Fruit_LFO` | 13 slider, 1 button, 1 toggle, 1 xypad | v1 |
| showcase_gallery | copies of the six above | as above | v1 |
| interaction_lab | 4 stations | 16 slider, 3 toggle, 4 button, 2 xypad | **sui3** |

Out of scope, stated so the omission is deliberate rather than forgotten:

- `face_collage`, `industrial_lattice`, `procedural_building_system` declare no
  canvas panels at all. Nothing to port.
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
its port, applying the written verdict rubric that 5A establishes. This phase
does **not** silently delete controls; see the Autonomy section for how that
decision is gated.

These panels are also control buses. Desert Totem records bidirectional binds
into layout, scatter and render parameters, and Showcase Gallery records eight
and twelve bind networks driven from the Strata and Desert panels. Moving a
control to Properties therefore removes only its `viewport.controls` entry and
keeps the parameter; every bind or `ref()` consumer of that parameter is either
untouched or re-pointed and proven live.

## Deliverables

| ID | Deliverable | Proof |
| --- | --- | --- |
| D1 | sui3 headers bundled into each in-scope project's `modules/_shared/ui/` | identical to the workspace kit by newline-normalized content hash |
| D2 | Seven modules' render passes rewritten against sui3 | `module-ui.ps1` validate + `compile_check` clean |
| D3 | Every ported control proven per the 5A per-kind proof table | gesture writes the expected value AND a pixel-probe assertion shows the drawn state tracking it; control kinds with no automated route are recorded unproven per Tier 3 |
| D4 | Control sets reviewed against the Properties-duplication rule | per-project written verdict under the 5A rubric, with any removal explicitly gated |
| D5 | Scene Group exposed controls still 6-10 and still live | group Properties readback per project, plus each exposed control driven from the group and observed at the module |
| D6 | Presets migrated or explicitly retired | `sentinel_preset recall` returns non-empty `applied[]` AND a paired capture shows the intended visible change against the prior preset |
| D7 | Proof bundles regenerated | `proof/` refreshed and curated to the pre-existing file set; validator `forbidden_artifacts` empty |
| D8 | Public promotion still validates | `promote-public.ps1` report-only run (no `-Apply`) clean per project |
| D9 | A reusable example-UI guard harness | re-runnable script, each guard kind watched failing, existing lab suite re-runs unchanged |

## Sub-phases

Ordered so the riskiest structural work happens once, early, and the aggregator
happens last.

### 5A - Kit preparation, proof routes and harness

Bundle sui3 into the in-scope projects, settle what is provable per control
kind, generalize the guard harness, and write the control-verdict rubric so each
subsequent sub-phase has both a proof mechanism and a decision rule ready.

- Copy `sui3_core/controls/text/theme/events` into each in-scope project bundle.
  `sui3_trace` is deliberately excluded: no in-scope panel plots a time series.
- Generalize `tools/interaction-lab-guards.py` into a project-agnostic
  `tools/example-ui-guards.py`: the `BUNDLE_PAIRS` identity guard becomes a
  copy-set guard (a module can have workspace, project and gallery copies), and
  the pad machinery becomes a control table covering all control kinds.
- Confirm `viewport_control_drag` behaviour holds outside Interaction Lab:
  control-local 0..1 coordinates, `value = (x, 1-y)`, focused viewport required.

**Pass criteria**

1. Every in-scope project bundle contains the five sui3 headers, identical to
   `modules/_shared/ui/` by newline-normalized content hash. (The existing lab
   bundle differs from the workspace copy only by CRLF; the copy step
   normalizes, and the identity guard compares normalized content.)
2. The MCP surface is current: reconnect the MCP server and confirm
   `viewport_control_drag` is in the accepted action list before any proof is
   attempted, and record the host build actually used. (The installed host
   carries the action; a session connected before the server rebuild does not.
   `.sentinel-workspace-version` says 0.5.43 while the kit's measured behaviour
   notes say 0.5.49; the recorded build resolves the discrepancy.)
3. A per-kind proof table is written and empirically confirmed on a v1 panel,
   with the measured numbers recorded: sliders prove by `viewport_control_drag`
   at two targets near 0.25 and 0.75; xypads by two asymmetric drags; toggles by
   an off-on-off round trip; buttons by whatever route the experiment
   establishes. If no automated route fires a button or toggle, that kind is
   routed to the Tier 3 recorded-unproven clause and the finding is written
   here, before 5B begins.
4. The harness carries drawn-state probes, not only value readbacks: a slider
   probe locating the rail head inside the manifest rect and asserting its
   position against the expected fraction within 0.05, and a toggle/button probe
   asserting the accent-pixel count inside the rect changes by a recorded factor
   between states. Each guard kind (slider head, toggle accent, pad reticle,
   bundle identity) is run once against a deliberately broken variant and its
   failing numbers are recorded.
5. The generalized harness re-runs the existing Interaction Lab suite unchanged,
   with the same pass and skip counts, and drives at least one control on one
   unported project, correctly reporting it as **not yet ported** rather than
   passing vacuously.
6. No workspace `modules/_shared/ui/sui3_*.hlsli` header is modified in this
   phase. The lab's `data_scope` and `signal_trails` stations consume the
   workspace headers live through `../../modules/` project references, and
   Phase 3's hands-on gesture pass is still pending; a kit edit would silently
   re-base its subject. A port that appears to need a kit change is a Tier 3
   stop.
7. `validate-official-examples.ps1` is run against every in-scope project and
   each baseline result is recorded before any edit.
8. The control-verdict rubric is written as part of 5A: a control stays on
   canvas only with a recorded reason Properties cannot serve (spatial meaning,
   gestural use, or coupling to a canvas visualization); otherwise it moves,
   subject to the Tier 2 conditions. Every panel applies the same written rule
   independently, so 5B through 5F can run in any order.

### 5B - `signal` (topographic_hud)

The worst offender at 16 sliders. Its criteria are the template the other
panel sub-phases apply.

Each panel sub-phase runs as two stages. The offline stage (control verdict,
port, `compile_check`, `module-ui.ps1` validate) needs no project load. The live
stage (gesture proof, group readback, presets, captures, proof bundle) loads the
project in a fresh Sentinel session, and every additional load in that sub-phase
is another relaunch; the devlog records the load count.

**Pass criteria**

1. Panel ports measurably: no v1 `sui_*` include remains in the module's
   sources (grep); a run-length histogram of the panel capture's frame strokes
   shows 1px runs with no 2px entries, as Phase 3B measured; at least three
   distinct glyph heights are present; accent-hued pixels stay under a recorded
   fraction of lit panel pixels. The aesthetic verdict (type scale, composition,
   restraint) is logged separately as Tier 1 and never substitutes for these
   four numbers.
2. Every surviving canvas control is exercised per the 5A proof table: sliders
   dragged to two targets near 0.25 and 0.75, both landing within 0.05, with a
   control whose two probes land within 0.1 of each other failing as
   unresponsive; the bound parameter reaches the expected value AND the harness
   drawn-state probe passes at the gestured position. Vision review may
   accompany the pixel probes and never substitutes for them.
3. A written control verdict exists for all 16 sliders under the 5A rubric:
   kept on canvas with a reason Properties cannot serve, or moved to
   Properties. A move keeps the parameter, removes only the `viewport.controls`
   entry, and every bind or `ref()` consumer of that parameter is re-pointed or
   proven live by driving the value and observing the consumer change.
4. The Scene Group still exposes 6-10 controls and each is proven live: driven
   from the group Properties path and observed changing at the module.
5. At least three whole-group presets including `Performance` remain, and
   `Performance` stays healthy at the documented target resolution. Each recall
   returns non-empty `applied[]` and is paired with a capture showing the
   intended visible change against the prior preset's capture.
6. The README's control, preset and remix sections match the shipped panel and
   Properties surface after the port.
7. The panel is captured at two dock widths differing by at least 2x:
   `content_size` and `render_size` are nonzero and matching at both, no
   control rect clips the panel edge, and one control's gesture proof passes at
   both extents.
8. `sentinel_graph profile` per-node wall time is recorded before and after the
   port; a regression beyond 20% is explained or fixed.
9. The bundled module is the runtime authority. After the port, the workspace
   original `modules/signal` is synced to match it (all three copies of a
   module agree by normalized hash), and the copy-set identity guard is green.
10. Project loads healthy, all nodes cooking, proof bundle regenerated and
    curated, and `validate-official-examples.ps1` clean with `generated_stale`,
    `orphan_modules` and `forbidden_artifacts` empty.

### 5C - `strata_control` (strata)

Criteria as 5B, applied to 12 sliders and 1 toggle. The toggle is proven by the
5A per-kind route with a full off-on-off round trip, so a stuck-at-on control
cannot pass a single actuation. Copy sync covers the workspace original
`modules/strata_control`.

### 5D - `dada_control` (desert_totem)

Criteria as 5B, applied to 12 sliders. Copy sync covers the workspace original
`modules/dada_control`. Desert Totem's panel drives recorded bind networks, so
criterion 3's consumer proof is load-bearing here.

### 5E - `LR_Furnishings`, `LR_Lighting` and `LR_Architecture` (living_room_sdf)

The most interesting case, and a correction to this plan's first draft: the six
declared controls on `LR_Furnishings` are tool and command controls (Move Tool,
Rotate Tool, Snap toggle, Fit Plan, Reset Selected, Reset All). Furnishing
selection happens through the manifest's `ray_query` selection provider via the
`left_click` gesture, outside the control table entirely. The spatial story that justifies this
panel is the plan editor itself: click-to-select, drag-to-transform, pan and
zoom. The tool buttons are reviewed under the same rubric as everything else,
with "they serve the spatial editor workflow" as an admissible canvas reason.

`LR_Architecture` joins the sub-phase as a control-free events-only canvas
panel on v1 `sui_*`; it needs the kit swap and the 5B.1 port measurables but no
gesture proof.

Runs as two stages: 5E.1 (`LR_Furnishings` and the 3D regression), then 5E.2
(`LR_Lighting` and `LR_Architecture`). This is the largest panel sub-phase
despite its small control count.

**Pass criteria**

1. All three modules on sui3, each passing the 5B.1 port measurables.
2. Furnishing selection proven through `sentinel_viewport`: a pick changes the
   selection, the panel's drawn selection state follows, a transform edit
   changes the descriptor position, a capture shows the furnishing moved, and
   the edit survives save and reload.
3. The tool buttons and Snap toggle get written verdicts under the 5A rubric
   and are proven by the 5A per-kind route. If 5A found no automated route for
   buttons, they are recorded unproven per Tier 3 and left for the operator
   pass. Note the platform hazard: a `type: button` parameter is a one-way
   latch on the current host (it survives `force_reload` and clears only on
   project reload, and `sentinel_state get` can disagree with
   `sentinel_pipeline info` about it), and the sui3 idiom hit-tests real click
   gestures instead of reading the latched parameter, which moves buttons off
   the only surface MCP can currently write.
4. `LR_Lighting`'s 4 sliders get the same control verdict and proof as 5B.
5. Direct manipulation of furnishings in the 3D view still works after the
   port, proven by an actual edit, not by the module compiling.
6. The numbered module variants (`LR_Furnishings_2`, `LR_Lighting_1` through
   `_4`) carry stale `_ui.generated.hlsli`: each is either regenerated or
   recorded as control-free and unaffected, and the validator flags no orphan.
7. Group controls, presets, README, extents, profile, copy-set guard, curated
   proof bundle and validator as 5B.

### 5F - `Fruit_LFO` (showcase_gallery)

The only module carrying an `xypad`, so it is the one that proves the pad fix
inside a shipped example rather than only in the lab. `Fruit_LFO` has no source
project; it lives only in the gallery, so this sub-phase edits the aggregator
directly and loads `showcase_gallery`, the heaviest project, in its own Sentinel
session. 5G loads it again in a separate session.

**Pass criteria**

1. Module on sui3, passing the 5B.1 port measurables.
2. The pad is proven by a real drag at two asymmetric points: the reticle lands
   under the drag, matching `value = (x, 1-y)` within tolerance.
3. Criteria 2-10 of 5B for the 13 sliders; the button and toggle follow the 5A
   per-kind route with the 5E.3 latch hazard in force.

### 5G - Showcase Gallery resync and collection review

The gallery bundles copies of the other projects' modules. It cannot be ported
independently; it must be resynced after 5B-5F land.

**Pass criteria**

1. Every gallery module copy that has a source project is identical to its
   source project's module by normalized hash. (`Fruit_LFO` has no source
   project; its authority is the gallery copy 5F ported.)
2. All seven groups load, the groups-mode Mux still switches between them, and
   `solo_upstream` still holds non-selected looks.
3. All seven panels pass the 5B.1 port measurables from captures taken inside
   the gallery. The side-by-side "one visual family" review of the seven looks
   is a Tier 1 aesthetic verdict logged with those captures; the measurables
   are the falsifiable half.
4. The gallery's own `Fruit_LFO` and at least one imported panel per source
   project are registered as harness targets and re-proven by gesture inside
   `showcase_gallery.sentinel`, so a byte-identical but dead-in-context copy
   cannot pass on file parity alone.
5. `promote-public.ps1` report-only run (no `-Apply`) clean for all in-scope
   projects.
6. Full guard suite green, with any skip named and justified, and
   `validate-official-examples.ps1` clean per project.

## Files summary

**New**

- `tools/example-ui-guards.py`
- `docs/devlogs/` entries per sub-phase

**Modified**

- `projects/{topographic_hud,strata,desert_totem,living_room_sdf,showcase_gallery}/modules/*/render.hlsl` and layout includes
- the same projects' `manifest.yaml` where control rects move
- each in-scope project's `modules/_shared/ui/` (sui3 headers added)
- workspace originals `modules/{signal,strata_control,dada_control}` (synced to
  the ported bundles; all three copies of a module must agree)
- each in-scope project's `README.md` and `proof/`
- `docs/state.md`, `docs/implementation-plan.md`

**Unchanged, deliberately**

- `modules/_shared/ui/sui_*.hlsli` - the v1 kit stays for non-official projects
- `modules/_shared/ui/sui3_*.hlsli` - frozen for this phase (5A criterion 6)
- `projects/autopsia`, all `au_*` modules
- `projects/interaction_lab` - already sui3
- `face_collage`, `industrial_lattice`, `procedural_building_system` - no canvas panels

## Implementation order

5A, then 5B, 5C, 5D, 5E, 5F in any order once 5A lands, then 5G last.

The control-verdict rubric lives in 5A, so no panel's verdict depends on
another's precedent. 5F and 5G both load `showcase_gallery` and do so in
separate Sentinel sessions.

## Verification plan

Every sub-phase proves in this order, and a later step never substitutes for an
earlier one:

1. `compile_check` on the module directory.
2. `tools/module-ui.ps1` validate.
3. Load the project in a fresh Sentinel session (never the same project twice
   in one session), confirm every node healthy with frames climbing.
4. **Gesture proof** per the 5A per-kind table: two-target drags for sliders,
   two asymmetric drags for pads, off-on-off round trips for toggles, the
   established route for buttons; assert the bound parameter reaches the
   expected value AND the harness drawn-state pixel probe passes at the
   gestured position. Both halves are required; Phase 3 proved that either
   alone passes over a broken control.
5. Group Properties readback for exposed controls, plus bind liveness: drive
   each exposed control from the group and observe the module parameter move.
6. `sentinel_preset recall` for each project preset, paired with a capture
   showing the intended visible change.
7. README control, preset and remix sections checked against the shipped
   surface.
8. Proof bundle regenerated and curated.
9. `validate-official-examples.ps1` clean: `generated_stale`, `orphan_modules`,
   `forbidden_artifacts` empty.
10. `promote-public.ps1` report-only run clean.

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
SessionId verified as non-zero. Each sub-phase's devlog records its load count.

**Bundled kits diverge silently, and some kit copies are live.** Every project
carries its own `modules/_shared/ui/`. Editing only the workspace copy changes
nothing at runtime for bundled projects, and the failure mode is that the fix
appears not to work; this cost real time on 2026-07-27. The inverse hazard is
sharper: Interaction Lab's `data_scope` and `signal_trails` stations reference
workspace modules directly, so a workspace sui3 header edit changes the lab at
runtime while its Phase 3 hands-on pass is pending. Hence 5A criterion 6: the
workspace sui3 headers are frozen for this phase, every bundle edit updates the
copy-set together, and the identity guard runs before concluding a change did
not take.

**Three copies of a module can exist and have already drifted.** `signal`,
`strata_control` and `dada_control` exist as workspace originals AND project
bundles (and gallery copies), and every workspace original has already diverged
from its bundle. The bundled copy is what runs; each port names it the
authority and syncs the other copies.

**Rebuilt modules orphan presets.** Phase 3 hit this. Each ported project's group
and node presets are recalled and checked, then migrated or explicitly retired
under the Tier 2 floor.

**Panels follow the dock.** `follow_panel` modules reflow with panel size, so
layout that reads well at one dock size can collide at another. This is now
5B criterion 7, checked before each sub-phase closes.

**The Sentinel window is unreachable from the agent session.** Phase 3A
recorded that full-window screenshots are unavailable; pipeline texture capture
works. `proof_bundle`'s window screenshot may therefore be absent; if it is,
that item is recorded unproven for the operator pass rather than silently
skipped.

## Autonomy and human-in-the-loop

### Tier 1 - self-serve, never stop

- Aesthetic verdicts on a ported panel. Log the verdict and a capture in the
  devlog, commit `approval: pending`, continue. The 5B.1 measurables still
  gate; the aesthetic log never substitutes for them.
- Per-sub-phase approval cadence.
- Layout, spacing, type scale, hairline and graticule choices within the sui3
  vocabulary.
- Relaunching Sentinel between project loads.

### Tier 2 - conditional-proceed, pre-authorized with a testable rule

- **Moving a canvas control to Properties.** Proceed when ALL hold: the control
  is a plain scalar or enum; it has no spatial meaning on the panel; removing
  it leaves the panel with at least one genuinely spatial or gestural control;
  the parameter itself is kept (only the `viewport.controls` entry is removed);
  and every bind or `ref()` consumer of the parameter is untouched or
  re-pointed and proven live. Otherwise stop and ask. Record the verdict for
  every control either way.
- **Adjusting a control's rect** to fit the sui3 layout: proceed, provided
  `module-ui.ps1` validates and the gesture proof still passes.
- **Retiring a preset** that no longer resolves after the port: proceed when
  the preset targets parameters that no longer exist, the project keeps at
  least three whole-group presets including a healthy `Performance` afterward,
  and the devlog says so. Migrate rather than retire whenever the parameters
  still exist. Dropping below the three-preset floor or losing `Performance`
  is a Tier 3 stop.

### Tier 3 - hard stop

- Removing the **last** canvas control from a panel, which would delete the
  panel's reason to exist.
- Any change to a shipped example's visual identity beyond the kit swap: new
  colours outside the theme, restructured composition, changed output resolution.
- Editing `docs/official-example-standard.md` or the governing spec.
- Editing any workspace `modules/_shared/ui/sui3_*.hlsli` header (see 5A
  criterion 6).
- Deleting or restructuring a Scene Group.
- A gesture-dependent criterion that cannot be proven automatically. It is
  recorded as unproven and left for an operator pass; it is never self-approved.
- Promotion to the public repository. This phase prepares and validates; the
  promotion itself is a separate, explicitly authorized step.

## Dependencies

- sui3 kit at `modules/_shared/ui/sui3_*.hlsli`, with the Y-up pad fix
  (`56e326b`) and the v1 equivalent (`d262ae2`). The kit is consumed frozen;
  see 5A criterion 6.
- Phase 4 (Data Scope, 4A-4C) has landed in the working tree even though the
  planning docs still say planned. No in-scope panel plots a time series, so
  nothing in this phase depends on `sui3_trace`, and it is excluded from the
  5A bundle set.
- `sentinel_ui action=viewport_control_drag`, and its measured contract:
  control-local 0..1 coordinates, `value = (x, 1-y)`, **focused viewport
  required** or the call succeeds silently and writes nothing. The installed
  host and MCP server carry the action; a session connected before the server
  rebuild does not see it, so 5A reconnects and confirms before proving
  anything, and records the host build used.
- `tools/module-ui.ps1`, `tools/promote-public.ps1`,
  `tools/official-examples.config.psd1`,
  `tools/validate-official-examples.ps1`.
- `tools/interaction-lab-guards.py` as the harness pattern. Its `Mcp` class,
  guard runner and pad machinery generalize; drawn-state probes for sliders,
  toggles and buttons are new 5A work.
- Interaction Lab as the reference implementation of every sui3 idiom.
- An operator pass for any control kind 5A finds unprovable by automation, per
  Tier 3.

## Cross-references

- [[phase-3-interaction-lab-v2]] - where the sui3 kit was built
- [[phase-4-data-scope]] - `sui3_trace`, the kit's strip-chart component
- [[official-example-standard]] - the release-readiness contract this must not weaken
- `knowledge/ui-authoring.md` - direct-manipulation doctrine
- `ood-labs/sentinel-bugs#88` - the repeat-load crash constraining the workflow

## Plan audit findings

Audited 2026-07-27 by four parallel agents (spec-alignment, acceptance-bar,
toolchain-feasibility, decomposition) before implementation. Verdict: judgement
calls to review, no open questions. 18 derived fixes and 6 judgement-call fixes
were applied to this doc; each judgement call is independently revertible.

### Derived fixes applied

1. **Preset proof was readback-only.** D6, 5B.5 and verification step 6 now
   require a paired capture showing the intended visible change, plus a floor
   of three group presets including a healthy `Performance` (the standard's
   preset rules; the old criteria could pass while presets regressed below the
   contract).
2. **The gesture proof's second half named no mechanism.** 5A.4 and 5B.2 now
   specify pixel probes (slider rail head within 0.05 of expected, accent-pixel
   count deltas for toggles/buttons), watched failing, with vision review
   allowed only as accompaniment.
3. **One-point slider proofs pass inverted tracks.** Sliders now prove at two
   targets (0.25/0.75) with an unresponsiveness check, mirroring 5F's pad
   criterion.
4. **5B.1 was self-graded.** It now carries four measurables (include grep,
   1px hairline histogram, three glyph heights, accent fraction) with the
   aesthetic verdict split out as Tier 1.
5. **Toggles could pass stuck-at-on.** Off-on-off round trip required (5C,
   verification step 4).
6. **5G could pass on stale file parity.** 5G.4 adds in-gallery gesture
   re-proof for the `Fruit_LFO` copy and one imported panel per source project.
7. **5G.1 was unsatisfiable for `Fruit_LFO`** (no source project exists);
   reworded to copies that have a source, with the gallery copy as `Fruit_LFO`'s
   authority.
8. **5G.3 could not fail.** Split into measurable half (5B.1 measurables on
   in-gallery captures) and Tier 1 aesthetic log.
9. **`validate-official-examples.ps1` was missing** from the verification plan
   despite being the standard's static gate; added as step 9 plus a 5A baseline
   criterion.
10. **README accuracy had no criterion** (5B.6, verification step 7); current
    READMEs describe the pre-port control surfaces.
11. **`follow_panel` extent conformance was prose**, not a criterion; now 5B.7
    with `content_size`/`render_size` assertions.
12. **No performance criterion existed**; 5B.8 adds before/after profile with a
    20% regression gate.
13. **`proof/` regeneration had no curation rule**; D7 and step 8 now require
    curation and empty `forbidden_artifacts`.
14. **Tier 2 control moves ignored bind/`ref()` consumers** on panels that are
    recorded control buses; the rule now keeps the parameter and requires
    consumer re-point-and-prove.
15. **"Byte-identical" bundles were already false on the only existing sui3
    bundle** (CRLF skew); D1/5A.1 now use newline-normalized content hashes.
16. **Three drifted copies per module existed where the plan named two**;
    5B.9 (and 5C/5D) name the bundle as authority and sync the workspace
    originals; the harness identity guard generalizes to copy-sets.
17. **`promote-public.ps1` has no dry-run flag** (report-only is the default);
    D8/5G.5 reworded to "report-only run (no `-Apply`)".
18. **Stale claims corrected**: Phase 4 has landed (Dependencies note);
    `viewport_control_drag` requires an MCP reconnect to appear (5A.2); the
    Sentinel window screenshot is unreachable from the agent session
    (hazard + operator routing); the numbered `LR_*` variants carry stale
    generated UI (5E.6).

### Judgement-call fixes applied (review these)

1. **`LR_Architecture` added to 5E scope.** It is an active v1 canvas panel in
   two shipped projects that the controls-only census missed. Alternative not
   taken: exclude it with a written reason and accept a v1 panel inside the
   "one visual family" claim. Revert by removing it from the Problem statement
   table, 5E, and the Files summary.
2. **5E's premise rewritten from measurement.** The five buttons are tool and
   command controls, and furnishing selection is ray-query picking; 5E.2 now
   proves selection through `sentinel_viewport` instead of a button click.
   Alternative not taken: keep the original framing and discover the mismatch
   mid-port. Revert by restoring the old 5E text, though the manifest contradicts
   it.
3. **Buttons and toggles get an empirical proof route decided in 5A.** No
   verified MCP route currently fires a canvas button or toggle, and the host's
   `type: button` latch makes parameter readback untrustworthy; 5A.3 settles
   the route or routes the kind to Tier 3 recorded-unproven. Alternative not
   taken: block the phase on a host feature for button gesture injection.
4. **The control-verdict rubric moved from "5B sets the precedent" to a 5A
   deliverable**, resolving the contradiction with "5B-5F in any order" in
   favour of keeping any order. Alternative not taken: strict 5B-first
   ordering.
5. **Sub-phases run as two named stages** (offline port, live proof) with a
   recorded load count, instead of formally splitting 5B/5E into numbered
   sub-sub-phases. Alternative not taken: renumbering to 5B.1/5B.2 and
   5E.1/5E.2 as separate approval units (5E keeps informal stage labels).
6. **Workspace sui3 headers frozen for the phase (new Tier 3 entry)** because
   the lab consumes them live while its Phase 3 hands-on pass is pending.
   Alternative not taken: allow kit edits with a mandatory lab regression
   check, which would couple this phase to Phase 3's open blocker.

### Open questions

None. Every finding admitted a defensible resolution.

### Considered and accepted

- The control-count census (16 / 12+1 / 12 / 5+1 / 4 / 13+1+1+1) is exact
  against every manifest, including the `signal` name collision between
  topographic_hud and desert_totem's unrelated module.
- The out-of-scope list is correct for control-declaring panels; gallery copies
  were byte-identical to their sources at audit time, so 5G is a true resync.
- 5F's two-asymmetric-point pad proof is the right shape and was kept as the
  model the slider criteria now copy.
- Ordering 5G last is correct; the gallery genuinely bundles copies of the
  other projects' modules.
- Tier 3 gates (last control, visual identity, standard edits, promotion) match
  the governing standard.
- The `/IT` relaunch workaround for `sentinel-bugs#88` is documented in the
  mcp-automation skill, including SessionId verification.
