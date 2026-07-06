# 2026-07-05 - Generative Skyscraper (single SDF module, max detail)

## Context

Detail stress-test of the SDF geometry lane: push a single raymarched Module as far as
it goes. One compute pass renders a seed-driven generative skyscraper with facade-level
detail, individual lit windows at night, a bounded context skyline, and a day/night
sweep. Lives at `projects/skyscraper/` (workbench), reusing `modules/_shared/sdf/` via a
`../../` relative include (Phase 69.B include walker preserved the path; no local copy
needed).

## Result

Reads convincingly as a detailed skyscraper across seeds. Independent day->night motion
eval scored 8/10 (clear setbacks, podium, spire+beacon, curtain-wall grid, believable
scattered window lighting, stable — no popping or blank faces). 61.6 fps at 720p on the
heaviest config (dusk + skyline + sun shadows), RTX 5090. Proof stills in the project:
`preview_hero_dusk.png`, `preview_seed42_day.png`, `preview_seed88_day.png`.

Detail stack in one `sceneMap`: seed-driven setback massing (tall base, decreasing tier
heights, gentle wedding-cake setbacks, Auto plan biased to Square/Chamfered/Cross) ->
ribbon-window facade -> inset glass core -> seed/param crown (Spire+beacon / Stepped /
Mech deck+water tower) -> bounded context skyline -> per-window night lighting with a
day/night parameter driving sun, sky, and window emission.

## The load-bearing lesson: punched windows can't survive setbacks

First facade attempt cut a global 3D grid of window boxes and subtracted them. It blanked
entire tier faces: a flat wall at `x = halfW` only shows a window if `halfW mod pitch`
lands in the window band, so each narrower setback tier is all-or-nothing depending on its
width. Two wrong fixes (narrowing pier columns, loosening pitch) just moved which tier
went blank. The fix that holds: **horizontal ribbon window bands** (`abs(frac(y/fh)-0.5)*fh
- wy`), which span the full face and are phase-independent, so every floor always reads.
Vertical mullions and per-window lighting are then done in shading from the face-tangent
column index, not geometry. This also made the look more universally "skyscraper"
(curtain wall) than the punched-Deco attempt. Rule for the skill: never gate facade
detail on a coordinate that is near-constant across a face.

## Gotchas hit (candidates for real fixes in the dev repo)

- **bool StateTree->cbuffer sync looks broken.** Setting a `type: bool` param to false at
  runtime via `set_many` reported `value: false` in StateTree but the shader kept reading
  the default `true` (context skyline would not turn off). Worked around by switching the
  gate to a `float` param (`context_amount`, syncs reliably). Worth reproducing in the dev
  repo — if confirmed it affects every runtime bool toggle. Params set at their manifest
  default were fine; the failure was flipping a bool away from its default.
- **Editing a live camera-feature module's files crashes the app.** The file-watch
  hot-reload fires on save and recompiles a live `features: [camera]` compute module; this
  session it crashed with an access violation in `nvwgf2umx.dll` (NVIDIA D3D driver). The
  safe iteration loop is destroy node -> edit files -> compile_check -> recreate. Never
  edit shader/manifest while the node exists. (Matches the earlier SDF-lane crash note.)
- Multiple agent sessions can share one running Sentinel; a foreign `Scene_*`/Phase-70
  node in the graph means another session owns the app. Check `sentinel_app status` pid
  and skip `save_project` when foreign nodes are present.

## Deferred / harvest

- Facade is robust but flat: window emissive has no interior depth (judge noted this);
  parallax-interior or varied light temperature would push realism.
- If the ribbon-facade + seed-massing approach is reused, harvest a `sdf_building`
  vocabulary entry into `modules/_shared/sdf/` + the catalogue (not done this pass —
  it currently lives as a project, not a library technique).
- Field-driven cities: feed `field_gen` elevation into per-instance tower height in
  `sdf_scene_render` for a skyline whose massing follows a field.
