---
type: devlog
date: 2026-07-27
phase: 5
subphase: 5C
status: complete
approval: pending
summary: "Strata Composition Desk is a responsive sui3 plate instrument with four proven rails, five live presets, and three-copy authority"
---

## Done

The bundled `projects/strata/modules/strata_control` is the runtime authority.
It ports to the frozen sui3 kit, keeps all thirteen parameters and fourteen
published outputs, and syncs the workspace and Showcase Gallery copies by
normalized content hash.

The Canvas is now a premultiplied plate-balance instrument: four coupled plate
lanes, live corner/thread telemetry, compact setup readbacks, and four broad
mix rails. Exact setup stays in Properties.

### Control verdict — all 12 sliders and one toggle

| Control | Verdict | Reason / liveness |
| --- | --- | --- |
| `blob_mix` | keep on Canvas | live sculpture-plate balance gesture coupled to the composition plot |
| `marble_mix` | keep on Canvas | live marble-plate balance gesture coupled to the composition plot |
| `wire_mix` | keep on Canvas | live wire-plate balance gesture coupled to the composition plot |
| `marks_mix` | keep on Canvas | live marks-plate balance gesture coupled to the composition plot |
| `master_seed` | move to Properties | exact scalar setup; blob, wire, marble, and marks consumers remain live |
| `palette_variant` | move to Properties | plain enum; all palette expressions remain untouched |
| `melt_macro` | move to Properties | exact scalar setup; blob-render expression remains live |
| `twist_macro` | move to Properties | exact scalar setup; blob-render expression remains live |
| `marble_warp_macro` | move to Properties | exact scalar setup; marble-panel bind remains live |
| `spread_macro` | move to Properties | exact scalar setup; blob-layout bind remains live |
| `wire_scale_macro` | move to Properties | exact scalar setup; wire-render bind remains live |
| `feature_gain` | move to Properties | exact scalar setup; thread intensity expression remains live |
| `feature_enabled` | move to Properties | plain boolean with no spatial meaning; thread intensity output remains live |

The toggle's automated v1 Canvas route remains the 5A Tier 3 recorded-unproven
case. It is no longer a surviving Canvas control, so it does not block the 5C
gesture gate. Its Properties effect and the existing curated
`feature-enabled.png` / `feature-disabled.png` pair remain intact.

## Offline gates

- `sentinel_pipeline compile_check`: `compile_ok=true`, 13 parameters, two
  passes, zero lints.
- `tools/module-ui.ps1 validate`: `OK Strata Composition Desk (4 controls)`.
- v1 include grep: zero results in all three copies.
- `python tools/example-ui-guards.py --check-module-copies strata_control`: all
  four authored files match across bundle, workspace, and Gallery.
- The copy-set guard rejected an authority manifest with an extra line:
  `33ab4a94... != 085ca2d4...`.

## Live proof

Host: Sentinel DIST 0.5.49, interactive Windows SessionId 1.

Load count was **three project loads in three separate Sentinel processes**:

1. current-HEAD Strata saved-state baseline;
2. working Strata once for all edited gesture, group, preset, extent, health,
   and proof work;
3. current-HEAD Strata again after a relaunch, with Clean Studio explicitly
   recalled, for an exact matched-state profile.

No project was loaded twice in one Sentinel session.

### Gesture and drawn-state proof

At the wide 1222x488 dock every rail wrote 0.5 and 1.5 at normalized targets
0.25 and 0.75:

| Control | target 0.25: parameter / head | target 0.75: parameter / head |
| --- | --- | --- |
| `blob_mix` | 0.5 / 0.2539 | 1.5 / 0.7520 |
| `marble_mix` | 0.5 / 0.2520 | 1.5 / 0.7500 |
| `wire_mix` | 0.5 / 0.2539 | 1.5 / 0.7520 |
| `marks_mix` | 0.5 / 0.2520 | 1.5 / 0.7500 |

At 366x429, `blob_mix` again wrote 0.5 / 1.5 and drew heads at 0.2614 /
0.7516. The width ratio is 3.34x; `content_size` and `render_size` match and
remain nonzero at both extents. The short-width header contracts to `STRATA`;
all four control rects remain inside the panel.

### Pixel measurables

Measured on `composition-desk-sui3.png` at 1222x488:

- control-frame normal-run histogram: `{1px: 4144, 2px: 0, 4px
  intersections: 36}`;
- measured body / live-number / title glyph heights: **7 / 14 / 21 px**;
- amber pixels: **726 / 44,222 lit pixels = 1.64%**.

Tier 1 aesthetic verdict: the four-layer plot makes the desk read as one
composition instrument instead of thirteen stacked widgets. The wide sheet is
calm and the narrow sheet is dense but collision-free. Approval remains
pending.

### Group and preset proof

All seven exposed Scene Group controls were driven from
`/sentinel/groups/annotation_91/parameters/*`, observed at their module, and
restored:

- Sculpture Gloss: 1.0 -> 1.3 -> 1.0
- Sculpture Reflection: 0.5 -> 0.65 -> 0.5
- Marble Width: 0.26 -> 0.3425 -> 0.26
- Marble Height: 0.30 -> 0.3425 -> 0.30
- Thread Width: 0.5 -> 4.075 -> 0.5
- Bloom: 0.8 -> 1.95 -> 0.8
- Film Grain: 0.02 -> 0.13 -> 0.02

Clean Studio, Melted Chrome, Graphic Poster, Wire Cage, and Performance were
all recalled and captured. Each returned `success=true` with **208 applied
values** (196 parameters plus 12 bypass flags). Adjacent captures changed
**80.58%, 90.76%, 98.83%, and 98.51%** of RGB channels over threshold.
Performance stayed healthy at 720x1080 and intentionally bypassed only
`features_0`, as documented.

## Health, cost, and proof

- Matched Clean Studio, panel open at 1222x488:
  - current-HEAD v1 six-sample median: **2.0431 ms**;
  - sui3 six-sample median: **0.9440 ms**;
  - change: **-53.8%**.
- A cross-state Performance sample initially measured an 8.1949 ms median at
  57-60 panel cooks/s versus Clean Studio's 20-23 cooks/s. It was rejected as
  a before/after comparison because the preset and graph cadence differed.
  Matching Clean Studio on both sides removed the confound and showed no
  regression.
- Final Clean Studio graph sample: 12/12 nodes healthy and cooking. Performance
  was separately healthy with its documented Features bypass.
- The proof bundle contains graph, links, graph profile, health, expressions,
  and Program output. Its old/new Clean Studio diff is **40.51%**.
- Full-window screenshot remains operator-unproven: `No window found matching
  'Sentinel'`.
- Curated proof refreshed: all five preset images and
  `proof/composition-desk.png`.
- `validate-official-examples.ps1 -Projects strata`: portable, one pass, zero
  failures, zero orphans, zero absolute paths, zero stale generated headers,
  zero forbidden artifacts.
- Promotion dry run against the temporary public clone completed with
  `mode=dry-run`, 101 operations, 31 expected changes, and `pushed=false`.
  Nothing was promoted.

## Cleanup

Removed the two tracked validator-baseline orphan modules
`projects/strata/modules/post` and `projects/strata/modules/signal` (five files
total), recoverable from Git history. Removed only runtime-generated
`.sentinel/shader_cache` folders under active Strata modules.

## Pending

- Human taste approval for the Composition Desk (`approval: pending`).
- Operator-only full-window screenshot proof.
- Phase 5D through 5G. No later phase started.
