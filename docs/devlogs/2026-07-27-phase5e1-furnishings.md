---
type: devlog
date: 2026-07-27
phase: 5
subphase: 5E.1
status: complete
approval: pending
summary: "Living Room Furnishings is a responsive sui3 plan editor with proven selection, desktop drag, durable save/reload, and unchanged 3D data flow"
---

## Done

`projects/living_room_sdf/modules/LR_Furnishings` is the runtime authority.
The six-control spatial toolbar and plan renderer now use the frozen sui3 kit,
and the Showcase Gallery copy matches all eleven authored files by normalized
hash. The parameter surface, eight passes, typed ports, selection provider, and
384-byte furnishing state contract are unchanged.

### Control verdict

All six controls remain on Canvas because they operate the spatial plan editor:

| Control | Verdict | Reason / proof |
| --- | --- | --- |
| Move Tool | keep | selects the direct-manipulation translation mode; live drawn active state |
| Rotate Tool | keep | selects the direct-manipulation rotation mode; click changed the drawn bank from 0 to 735 accent pixels |
| Snap | keep | spatial transform constraint; true -> false -> true round trip with drawn-state proof |
| Fit Plan | keep | restores the spatial editor camera framing |
| Reset Selected | keep | command reset the moved sofa state from `[1.5, -0.5]` to `[0, 0]` |
| Reset All | keep | spatial editor recovery command for the full durable record set |

The official 5A v1 button/toggle route remains operator-unproven as required by
the contract. The port's sui3 event route nevertheless actuated Rotate, Snap,
and Reset Selected in live proof; that additional evidence does not rewrite the
5A route verdict or conceal the host's one-way button-latch hazard.

## Offline gates

- `sentinel_pipeline compile_check`: `compile_ok=true`, 20 parameters, eight
  passes, zero lints.
- `tools/module-ui.ps1 validate`: `OK Living Room Furnishings Plan Editor
  (6 controls)`.
- v1 include grep: zero results in the authority and Gallery copies.
- `python tools/example-ui-guards.py --check-module-copies LR_Furnishings`:
  all eleven authored files match.
- The copy guard was watched failing against an added Gallery-only content
  line: `preview.hlsl all_match=false`, exit 1. The probe was removed and the
  green result rerun.

## Live proof

Host: Sentinel DIST 0.5.49, interactive Windows SessionId 1.

Load count was **three project loads in three separate Sentinel processes**:

1. current-HEAD Living Room baseline;
2. the edited main project once for gestures, extents, health, and profiling;
3. a bundled persistence save once in a fresh process.

No project was loaded twice in one Sentinel session.

### Selection and real desktop drag

`sentinel_viewport pick` at normalized `(0.4721, 0.3174)` selected furnishing
object 1. Host selection reported `active_id=1`, `count=1`, `source=User`, and
the panel followed with an amber selection outline, gizmo, and attached `01`.

The synthetic host object-edit transaction does not target this module's
raw-event durable buffer, so it was correctly treated as non-applicable. A real
pointer drag on the interactive Session 1 desktop, from panel client
`(577,205)` to `(656,232)`, delivered the viewport events and moved the sofa:

- descriptor pivot: `[-0.65, 0.66, 2.35]` ->
  `[0.85, 0.66, 1.85]`;
- durable offset: `[0,0]` -> `[1.5,-0.5]`;
- selection remained object 1;
- the 12-record / 384-byte durable state inventory remained valid.

`moved-sofa.png` visibly isolates the translated sofa assembly in amber. The
canonical 1280x720 renderer remained healthy and visibly changed, but its
continuous deformation makes its 81.02% adjacent-frame delta animation
confounded; descriptor, durable-state, and editor capture are the causal proof.

### Save/reload persistence

The moved project was saved with `bundle_modules=true` to a temporary portable
path; all six referenced modules were bundled. After terminating Sentinel and
launching a new interactive process, that saved project was loaded exactly
once. Once the asynchronous descriptor producer settled, object 1 restored at
`[0.85, 0.66, 1.85]`, proving the `[1.5,-0.5]` edit survived. The reloaded
module was healthy, compiled, and rendered at 1222x488. The curated
`proof/plan_offset_sofa.png` is the settled reload capture.

### Gesture and pixel probes

At the wide 1222x488 dock:

- Rotate changed its local drawn state by 12.93% and added 735 accent pixels.
- Snap completed true -> false -> true with 579 -> 0 -> 579 accent pixels and
  a 12.23% local pixel change.
- the selected/moved editor contained 3,309 warm-accent pixels, **0.555%** of
  the full panel, keeping the accent subordinate;
- 3,086 isolated gray hairline candidates were measured across the plan and
  toolbar, with the intended 7 / 14 / 21 px body, live-number, and title type
  ladder visible.

At the narrow 366x429 dock, `content_size == render_size` and remained nonzero.
The first capture caught `RESET ALL` clipping. The responsive branch now uses
`RST` / `ALL` inside the unchanged hit regions. The rerun is collision-free,
and Snap again completed true -> false -> true with 226 -> 0 -> 226 accent
pixels and an **18.44%** local pixel change.

Tier 1 aesthetic verdict: at wide and narrow extents the panel reads as a
technical plan editor rather than a generic control form. Monochrome furniture,
thin rules, and one selection accent clearly separate authored geometry from
active state. Approval remains pending.

## Health and cost

- All six Living Room modules compiled successfully and were healthy with
  frames climbing; the final grade remained 1280x720.
- Matched Daylight, Furnishings panel open at 1222x488:
  - current-HEAD v1 six-sample median: **0.01885 ms**;
  - sui3 six-sample median: **0.0158 ms**;
  - change: **-16.2%**, at 57-58 cooks/s.
- The selected/moved and reloaded plan captures and 3D regression captures are
  retained under `captures/phase5/living_room_sdf/LR_Furnishings/`; the curated
  moved plan and renderer images were refreshed.

## Pending

- 5E.2 ports `LR_Lighting` and control-free `LR_Architecture`, then closes the
  whole-project group, preset, README, proof-bundle, variant, validator, and
  promotion-report gates.
- Human taste approval and the operator-only full-window screenshot.
- Phase 5F and 5G. No later phase started.
