---
type: devlog
date: 2026-07-27
phase: 5
subphase: 5B
status: complete
approval: pending
summary: "Topographic Signal is a responsive sui3 instrument with two proven performance gestures, live group/preset proof, and three-copy authority"
---

## Done

The bundled `projects/topographic_hud/modules/signal` is the runtime authority.
It ports from v1 to the frozen sui3 kit without changing the kit, keeps the
existing signal compute contract, and syncs the workspace and Showcase Gallery
copies by normalized content hash.

The old sixteen-slider form is now a signal-bus instrument: four live transport
traces, resolved layer meters, compact authority/cue/map readbacks, and two
broad performance rails. The wide and narrow layouts use the same host-owned
control rects, crisp bitmap type, 1px instrument rules, and one restrained amber
accent.

### Control verdict — all 16 original sliders

| Control | Verdict | Reason / liveness |
| --- | --- | --- |
| `manual_energy` | keep on Canvas | performance gesture coupled directly to the live energy trace and readout |
| `manual_sweep` | keep on Canvas | performance gesture coupled directly to the live sweep trace and readout |
| `authority` | move to Properties | plain three-value enum; parameter and control-output consumer remain live |
| `cue_mode` | move to Properties | plain five-value enum; preset values and compute consumer remain live |
| `terrain` | move to Properties | plain enum; `terrain` control output still drives `field_gen.field_mode` |
| `node_density` | move to Properties | exact scalar setup; `density` output still drives `node_gen.node_count` |
| `palette` | move to Properties | plain enum; existing post-color expressions remain untouched |
| `layer_blue` | move to Properties | exact scalar setup; resolved layer meter and `blue_gain` consumer remain live |
| `layer_accent` | move to Properties | exact scalar setup; resolved layer meter and consumer remain live |
| `layer_nodes` | move to Properties | exact scalar setup; resolved layer meter and consumer remain live |
| `layer_labels` | move to Properties | exact scalar setup; resolved layer meter and consumer remain live |
| `master_mix` | move to Properties | exact scalar setup; resolved output and compositor expression remain live |
| `pulse_rate` | move to Properties | exact rate setup; compute output and downstream pulse expressions remain live |
| `sweep_rate` | move to Properties | exact rate setup; compute sweep lane remains live |
| `beat_rate` | move to Properties | exact rate setup; compute beat lane remains live |
| `beat_sharp` | move to Properties | exact shaping setup; compute beat lane remains live |

Only `viewport.controls` entries were removed. All eighteen parameters,
sixteen published control outputs, and every existing `ref()` consumer remain
in place.

## Offline gates

- `sentinel_pipeline compile_check`: `compile_ok=true`, 18 parameters, two
  passes, zero lints.
- `tools/module-ui.ps1 validate`: `OK Topographic Operations Console (2
  controls)`.
- v1 include grep: zero results in all three copies.
- `python tools/example-ui-guards.py --check-module-copies signal`: all four
  authored files match across the Topographic bundle, workspace original, and
  Gallery copy.
- The new copy-set guard was watched failing against an authority manifest
  with an extra content line:
  `63e1f1d5... != 913097c6...`.

## Live proof

Host: Sentinel DIST 0.5.49, interactive Windows SessionId 1.

Load count was **two project loads in two separate Sentinel processes**:

1. one temporary current-HEAD Topographic copy for the v1 profile/capture;
2. one working Topographic project load after a relaunch for all edited proof.

The working project was never loaded again. Shader-only `force_reload` was used
after two responsive-label fixes.

### Gesture and drawn-state proof

At the wide 1222x488 dock:

| Control | target 0.25: parameter / head | target 0.75: parameter / head |
| --- | --- | --- |
| `manual_energy` | 0.25 / 0.2539 | 0.75 / 0.7520 |
| `manual_sweep` | 0.25 / 0.2520 | 0.75 / 0.7500 |

At the narrow 366x429 dock, `manual_energy` read back 0.25 / 0.75 and its
heads measured 0.2614 / 0.7516. The width ratio is 3.34x; `content_size` and
`render_size` were nonzero and equal at both extents. The narrow title switches
to a shorter form rather than colliding with the live energy column. No control
rect clips an edge.

An explicit `end` phase now follows every harness `begin`. DIST 0.5.49 usually
releases atomically at `begin`, but the restored narrow native window retained
capture until `end`; the paired route works on both behaviors and leaves the
next target unblocked.

### Pixel measurables

Measured on `operations-console-sui3.png` at 1222x488:

- control-frame normal-run histogram: `{1px: 2082, 2px: 0, 4px
  intersections: 18}`;
- measured body / live-number / title glyph heights: **7 / 14 / 21 px**;
- amber pixels: **697 / 38,297 lit pixels = 1.82%**.

Tier 1 aesthetic verdict: the old stacked control form is replaced by a quiet,
legible transport instrument. Composition, restrained chroma, and hierarchy
read cleanly at both captured extents. Approval remains pending.

### Group and preset proof

All eight exposed Scene Group controls were driven from
`/sentinel/groups/annotation_90/parameters/*`, observed at their target module,
then restored:

- Terrain Frequency: 1.6 -> 4.005 -> 1.6
- Terrain Octaves: 5 -> 6 -> 5
- Grid Density: 30 -> 59.9 -> 30
- Contour Density: 64 -> 79.4 -> 64
- Viewport Radius: 0.94 -> 0.65 -> 0.94
- Atmosphere Density: 0.7 -> 1.3 -> 0.7
- Bloom: 0.8 -> 1.95 -> 0.8
- Vignette: 0.95 -> 1.3 -> 0.95

Every group preset was recalled and captured: Survey, Threat, Night Vision,
Minimal, and Performance. Each recall returned `success=true` with **262
applied values** (245 pipeline parameters plus 17 bypass flags). Adjacent
captures changed **57.07%, 58.81%, 52.48%, and 47.56%** of RGB channels over
the comparison threshold. Performance remained healthy at 1920x1080.

## Health, cost, and proof

- Current-HEAD v1 `signal` wall time, panel open at 1222x488: **2.1130 ms**.
- sui3 `signal` wall time, same panel extent: **1.7247 ms**.
- Change: **-18.4%**; there is no regression.
- Final graph sample: 17/17 nodes healthy, all 17 cooking, Signal at 60 Hz with
  32,083 processed frames.
- The proof bundle contains graph, links, graph profile, pipeline health,
  expressions, and Program output. Its old/new Performance diff is **32.80%**.
- Full-window screenshot remains operator-unproven: the capture action returned
  `No window found matching 'Sentinel'`. This is the phase contract's recorded
  Tier 3 operator item, not a code blocker.
- Curated proof refreshed: all five preset images and
  `proof/operations-console.png`.
- `validate-official-examples.ps1 -Projects topographic_hud`: portable, one
  pass, zero failures, zero orphans, zero absolute paths, zero stale generated
  headers, zero forbidden artifacts.
- Promotion dry run against a temporary public-repository clone completed with
  `mode=dry-run`, 119 operations, 26 expected changes, zero deletes, and
  `pushed=false`. Nothing was promoted.

## Cleanup

Removed the tracked `projects/topographic_hud/DEBRIEF.md` that the official
example validator identified as forbidden. The file remains recoverable from
Git history. Removed only runtime-generated `.sentinel/shader_cache` folders
under the Topographic module bundle.

## Pending

- Human taste approval for the Signal Canvas (`approval: pending`).
- Operator-only full-window screenshot proof.
- Phase 5C through 5G. No later phase started.
