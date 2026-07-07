# Reference Rebuild Guide

Recreate a reference clip as a **modular Sentinel scene** — multiple modules, the right technique
per element, wired and composited. Momentum-first: **build the whole thing, then refine.**

## Principles
1. **The reference image is the spec.** The decomposition JSON is a hypothesis/shot-list, not a
   blueprint. Keep reference stills open; compare with your own eyes.
2. **Every clip is a modular scene, not one hero module.** Element → technique → transport, wired
   into a graph (generator → data-lane → renderer → compositor → post). Skill: `modular-scene-authoring`.
3. **Rough the WHOLE scene before polishing any part.** Get every element on screen, wired,
   animating, in one fast pass. Seeing it together is what tells you what actually matters. Don't
   perfect a single element before the rest exist.
4. **Refine in whole-scene passes, biggest gaps first** (geometry character → material → motion).
   Your eyes on a side-by-side are the judge. `vision_eval` is an *occasional whole-scene gut-check*
   for a gap list — never a per-step score to optimize.
5. **Momentum over gating.** Never get stuck on one element — stub it, finish the scene, come back.
   No per-step checkpoints, no per-element iteration ceremony.

## The per-clip loop
1. **Quick read + plan (minutes).** Glance at a couple of reference frames. List the elements and
   pick a technique+transport for each — terse `projects/<clip>/PLAN.md` (Element → Technique →
   Transport table + a one-line module graph). Note each element's obvious silhouette/character so
   you don't build the wrong thing. Don't over-analyze.
2. **Rough the whole scene end-to-end.** Build every element fast (rough geometry + placeholder
   material + rough motion), wire the graph, composite. All parts on screen together, animating, in
   one pass. Hard element? Stub it and keep going.
3. **Look at the whole vs the reference — once.** One side-by-side capture (optionally one
   whole-scene `vision_eval` for a structured gap list). Pull the top 3–5 mismatches.
4. **Refine in 2–3 whole-scene passes.** Fix the biggest gaps across the scene — geometry character
   first, then material, then motion/timing — re-look at the whole each pass. Stop when it *reads as
   the reference*. Don't chase a number; don't grind one element.
5. **Harvest.** Reusable modules → `modules/`; assembled scene → `projects/<clip>/<clip>.sentinel` +
   terse `PLAN.md`; add `technique-catalogue.md` entry for anything novel; short devlog; mark DONE.

## Checkpoints (minimal)
- **Clip C1 (calibration):** one checkpoint after the rough whole scene is up, and final sign-off.
- **Clips C2–C11:** **final sign-off only.** Self-verify against the reference side-by-side; escalate
  only if genuinely stuck or the reference reading is ambiguous.

## Technique lanes (pick per element)
- **2D feedback / trail buffer** — draw-on strokes, fluid smears, paint.
- **Cloner + `prim_atlas`** (`pl_grid→pl_spawn→pl_path→pl_render`) — sprite/stamp swarms.
- **Hero raymarch SDF** (hand CSG, `_shared/sdf`) — one exact abstract object.
- **Precise blueprint** (`sentinel_blueprint` → PNodes → `sdf_scene_render`) — 3D scenes of objects
  with real dimensions + relations (tucked/supported_by/flush/facing).
- **Texture-field generator** — gradients, height fields. **Spline/segment** — paths, wires.
- **Single-pass HLSL post** (`hlslshader`) — grade/glow/chroma/grain. **Static overlay** — UI chrome.
Check `technique-catalogue.md` for reuse first.

## Motion (use the shared system, not hand-rolled sines)
Include `../_shared/anim/anim.hlsli`: `an_spring` (+ presets BOUNCY/SNAPPY/SMOOTH/HEAVY),
`an_stagger_*`, `an_anticipate`, `an_squash`, **`an_loop_noise`** (seamless per period). Same
functions in the expression engine (`spring`/`stagger`/`loop_noise`). Seamless loops: phase-accumulate
rate changes (`phase += rate*dt`, never `time*live_rate`); retarget-stamp with `an_spring_v`. Timed/
beat-locked: `conductor` + cue sheet (`sentinel_conductor`), visualize with `timeline_hud`. Verify:
`sweep_record` → `motion-eval`; loop seam ≤ mean adjacent-frame diff (`tools/verify_motion_energy.py`).

## Tools & mechanics (validated)
- **Scaffold:** `modules/<name>/{shader.hlsl, manifest.yaml}`; shader FIRST, manifest LAST.
  `features:[camera]` for 3D; include `_shared/sdf` + `_shared/anim`; never `features:[sdf]` with the
  sdf headers (name collision).
- **Loop:** `compile_check` (offline) → `create type=module` → `compile_status` ok → `capture`.
- **Camera:** default Fly; **Orbit** (`sdf_orbitRay`, target origin) for deterministic captures.
- **Params:** `sentinel_state set` one path at a time (`set_many` / `capture_at overrides` are broken
  here). Live params instant; **shader/manifest edits need destroy + recreate** (camera modules crash
  on `force_reload`).
- **Precise geo:** `sentinel_blueprint validate → compile(create:true) → audit`; wire `PNodes` →
  `sdf_scene_render`. **Data:** `get_data_schemas` then `sentinel_graph add_link` by pin.
- **Stills:** transcode GIFs→mp4; ffmpeg `fps,scale,tile` sheets, `-ss T -frames:v 1` frames, crop zooms.

## Failure modes (do not repeat)
- Building from the JSON instead of the image.
- Treating a scene as one hero module.
- **Over-gating: per-element vision_eval, chasing a score, per-step checkpoints, getting stuck on one
  element instead of roughing the whole scene first.** ← the current correction.
- Polishing material/detail before the whole scene exists and reads roughly right.
- Hand-rolling springs/loops instead of `anim.hlsli`.

## Definition of done (per clip)
Whole scene reads as the reference (silhouette/composition, material, seamless-loop motion) at its key
frames — your eyes + final sign-off. Harvested: modules in `modules/` + `.sentinel` scene + terse
`PLAN.md` + catalogue entry + devlog; clip marked DONE.
