---
type: devlog
date: 2026-07-27
phase: 5
subphase: 5A
status: complete
approval: pending
summary: "sui3 bundles, per-kind proof routes, and the project-agnostic example UI harness are established before any panel port"
---

## Done

5A met all eight criteria before any panel source changed.

- The five frozen sui3 headers (`core`, `controls`, `text`, `theme`, `events`)
  are bundled in all five in-scope projects. `python
  tools/example-ui-guards.py --check-bundles` reports 25/25 copies equal to the
  workspace authorities by newline-normalized SHA-256.
- Live discovery used installed Sentinel DIST 0.5.49. The reconnected MCP
  surface reports 151 commands and `VIEWPORT_CONTROL_DRAG` with strict args
  `pipeline/control/phase/x/y/steps`.
- `tools/example-ui-guards.py` takes a project, pipeline, and manifest-backed
  control table. It reports the current v1/sui3 port state and proves parameter
  and drawn-pixel behavior together.
- The current-HEAD Interaction Lab suite is green at **48 passed, 0 failed, 4
  skipped**. The four skips remain the existing real-pointer hands-on checks.
  A wide-dock reticle detector fix prevents square numeric glyphs outranking
  the larger pad ring.
- Load count: Showcase Gallery once in Sentinel session 1 for the v1 route
  experiment; Interaction Lab once after a relaunch for the regression suite.
  Neither project was loaded twice in one Sentinel session.

### Per-kind proof table

Measured on the still-v1 `Fruit_LFO` at 1200x890:

| Kind | Automated route | Parameter proof | Drawn-state proof | Verdict |
| --- | --- | --- | --- | --- |
| slider | `viewport_control_drag`, atomic `begin` target | normalized 0.25 -> 0.824999 (expected 0.825); 0.75 -> 2.275 | head 0.2548 and 0.7452 | proven |
| xypad | `viewport_control_drag`, atomic `begin` target, pointer Y maps to `1-y` | (0.23, 0.71) and (0.77, 0.29) exact to displayed precision | reticle (0.2374, 0.7040) and (0.7632, 0.2948) | proven |
| toggle | no firing automation route on DIST 0.5.49 | off remained off after two attempts | 0 changed pixels, accent 0 -> 0 | Tier 3 recorded-unproven |
| button | no firing automation route on DIST 0.5.49 | 0 remained 0 | 0 changed pixels, accent 0 -> 0 | Tier 3 recorded-unproven |

For this host build the target write completes on `phase=begin`; a following
`update` or `end` reports that the target no longer owns pointer capture. The
harness records the host response so future behavior drift is visible.

### Guard discrimination

`python tools/example-ui-guards.py --self-test` watched all four guard kinds
reject deliberately broken comparisons:

| Guard | Broken result | Failing number |
| --- | --- | --- |
| bundle identity | extra content line | normalized hash mismatch |
| slider head | 0.25 capture asserted as 0.75 | error 0.4952 |
| pad reticle | (0.23, 0.71) capture asserted as (0.77, 0.29) | error 0.5326 |
| toggle accent | non-firing v1 off/on pair | 0 -> 0, below required factor |

### Validator baselines before edit

All five baselines were non-portable for pre-existing reasons, with
`generated_stale` empty throughout:

- `topographic_hud`: forbidden `DEBRIEF.md`.
- `strata`: orphan `post` and `signal` modules.
- `desert_totem`: orphan `post` and `signal` modules.
- `living_room_sdf`: two project files, one absolute path, and the recorded
  numbered orphan module set.
- `showcase_gallery`: forbidden `Fruit_LFO/.sentinel/shader_cache`.

### Control-verdict rubric

A control stays on Canvas only when Properties cannot serve it because it has
spatial meaning, gestural/performance use, or direct coupling to a Canvas
visualization. Otherwise it moves under the phase's Tier 2 rule: keep the
parameter, remove only its `viewport.controls` entry, and prove every bind or
`ref()` consumer still responds. Removing the last Canvas control, losing the
three-preset floor or `Performance`, or changing visual identity remains a
Tier 3 stop.

## Next

5B ports `topographic_hud/modules/signal`, applies the rubric to all 16
sliders, and proves the panel offline and live before 5C starts.
