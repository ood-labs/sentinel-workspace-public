---
type: devlog
date: 2026-07-27
phase: 5
subphase: 5D
status: complete
approval: pending
summary: "Desert Warp Deck is a responsive sui3 deformation instrument with four proven rails, live bind consumers, six presets, and three-copy authority"
---

## Done

The bundled `projects/desert_totem/modules/dada_control` is the runtime
authority. It ports to the frozen sui3 kit, keeps all twelve macro parameters
and fifteen published outputs, and syncs the workspace and Showcase Gallery
copies by normalized content hash.

The Canvas is now a deformation instrument rather than a twelve-row Properties
form: a live field plot, compact setup readbacks, and four broad gesture rails.
Exact assembly, twist, surface, palette, haze, and accent shaping stays in
Properties.

### Control verdict — all 12 sliders

| Control | Verdict | Reason / liveness |
| --- | --- | --- |
| `melt_macro` | keep on Canvas | live deformation-axis gesture coupled to the field plot; `dada_render.melt_amt` followed and restored |
| `sag_macro` | keep on Canvas | live deformation-axis gesture coupled to the field plot; `dada_render.sag_amt` followed and restored |
| `warp_primary` | keep on Canvas | live primary-warp gesture coupled to the field plot; `dada_render.w1_amt` followed and restored |
| `warp_secondary` | keep on Canvas | live secondary-warp gesture coupled to the field plot; `dada_render.w2_amt` followed and restored |
| `spread_macro` | move to Properties | exact assembly setup; `dada_layout.spread` followed 0.959 and restored |
| `explode_macro` | move to Properties | exact assembly setup; `dada_layout.explode` followed 0.444 and restored |
| `twist_macro` | move to Properties | exact scalar setup; `dada_render.twist_amt` followed -0.26 and restored |
| `painterly_macro` | move to Properties | exact surface setup; `dada_render.painterly_amt` followed 0.37 and restored |
| `facet_macro` | move to Properties | exact surface setup; `dada_render.facet_amt` followed 0.37 and restored |
| `hue_macro` | move to Properties | exact palette setup; `dada_render.hue_shift` followed 0.37 and restored |
| `heat_macro` | move to Properties | exact haze setup; `dada_render.heat_amt` followed 0.37 and restored |
| `scatter_macro` | move to Properties | exact integer field setup; `dada_scatter.scatter_count` followed 30 and restored |

All twelve source-to-consumer bind pairs were driven, observed at the bound
consumer, and restored. No bind or expression was removed or re-pointed.

## Offline gates

- `sentinel_pipeline compile_check`: `compile_ok=true`, 12 parameters, two
  passes, zero lints.
- `tools/module-ui.ps1 validate`: `OK Desert Warp Deck (4 controls)`.
- v1 include grep: zero results in all three copies.
- `python tools/example-ui-guards.py --check-module-copies dada_control`: all
  four authored files match across bundle, workspace, and Gallery.
- The self-test rejected a Dada authority manifest with an extra content line:
  `4242c9a8... != 00ae29ac...`.

## Live proof

Host: Sentinel DIST 0.5.49, interactive Windows SessionId 1.

Load count was **three project loads in three separate Sentinel processes**:

1. current-HEAD Desert Totem saved-state baseline;
2. working Desert Totem once for all edited gesture, group, preset, extent,
   health, and proof work;
3. current-HEAD Desert Totem again after a relaunch, with Performance
   explicitly recalled after every module compiled, for an exact matched-state
   profile.

No project was loaded twice in one Sentinel session.

### Gesture and drawn-state proof

At the wide 1222x488 dock every rail wrote its expected quarter and
three-quarter parameter values and drew the rail head at the same fraction:

| Control | target 0.25: parameter / head | target 0.75: parameter / head |
| --- | --- | --- |
| `melt_macro` | 0.15 / 0.2539 | 0.45 / 0.7520 |
| `sag_macro` | 0.15 / 0.2520 | 0.45 / 0.7500 |
| `warp_primary` | 0.30 / 0.2539 | 0.90 / 0.7520 |
| `warp_secondary` | 0.25 / 0.2520 | 0.75 / 0.7500 |

At 366x429, `melt_macro` again wrote 0.15 / 0.45 and drew heads at 0.2614 /
0.7516. The width ratio is 3.34x; `content_size` and `render_size` match and
remain nonzero at both extents. The narrow proof exposed a surface-readback
collision; the responsive branch now hides that non-control telemetry below
700 px, leaving all four rails and labels collision-free.

### Pixel measurables

Measured on `warp_secondary_0.75_1222x488.png`:

- control/plot frame-normal samples: **6,946 at 1 px**, zero ordinary 2 px,
  with 38 classified crossings/intersections;
- measured body / live-number / title glyph heights: **7 / 14 / 21 px**;
- warm-accent pixels: **690 / 73,274 lit pixels = 0.94%**.

Tier 1 aesthetic verdict: the field plot makes the four gesture axes read as
one deformation desk. The wide sheet is restrained and legible; after the
responsive telemetry fix, the narrow sheet is compact and collision-free.
Approval remains pending.

### Bind, group, and preset proof

Every macro bind is covered in the control-verdict table. All eight exposed
Scene Group controls were also driven from
`/sentinel/groups/annotation_92/parameters/*`, observed at their module, and
restored:

- Layout Seed: 2 -> 17 -> 2
- Scatter Seed: 3 -> 19 -> 3
- Layout Jitter: 0.05 -> 0.62 -> 0.05
- Fog Density: 0.8 -> 1.35 -> 0.8
- Sun Azimuth: 62 -> 137 -> 62
- Sun Elevation: 48 -> 33 -> 48
- Bloom: 0.45 -> 1.4 -> 0.45
- Film Grain: 0.025 -> 0.11 -> 0.025

Monument, Dali Melt, Cubist Glitch, Painterly, Fidelity, and Performance were
all recalled and captured. Each returned `success=true` with **156 applied
values** (149 parameters plus 7 bypass flags). Adjacent normalized captures
changed **22.34%, 25.12%, 24.61%, 23.79%, and 0.66%** of pixels over threshold.
The last transition also changes the output extent from 760x1140 to the
documented 608x912 Performance target. All seven nodes remained healthy and
cooking there.

## Health, cost, and proof

- Matched Performance, panel open at 1222x488:
  - current-HEAD v1 six-sample median: **7.0055 ms**;
  - sui3 six-sample median: **3.5425 ms**;
  - change: **-49.4%**.
- The proof bundle contains graph, links, profile, health, expressions, and
  Program output. Its old/new Performance diff is **78.06%**.
- Full-window screenshot remains operator-unproven:
  `No window found matching 'Sentinel'`.
- Curated proof refreshed: all six preset images and `proof/warp-deck.png`.
- `validate-official-examples.ps1 -Projects desert_totem`: portable, one pass,
  zero failures, zero orphans, zero absolute paths, zero stale generated
  headers, zero forbidden artifacts.
- Promotion dry run against the temporary public clone completed with
  `mode=dry-run`, 105 operations, 32 expected changes (13 adds, 13 updates,
  6 deletes), and `pushed=false`. Nothing was promoted.

## Cleanup

Removed the two tracked validator-baseline orphan modules
`projects/desert_totem/modules/post` and
`projects/desert_totem/modules/signal` (five files total), recoverable from Git
history. Removed only runtime-generated `.sentinel/shader_cache` folders under
the active Desert Totem modules and the Gallery Dada copy.

## Pending

- Human taste approval for the Desert Warp Deck (`approval: pending`).
- Operator-only full-window screenshot proof.
- Phase 5E through 5G. No later phase started.
