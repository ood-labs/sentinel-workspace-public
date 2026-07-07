---
name: recreate-reference
description: Recreate a reference image or video clip as a MODULAR Sentinel scene (a graph of separable modules, never a monolith). Studies the reference with your own eyes plus a vision_eval decomposition, then designs and builds it through the modular-scene-authoring skill (and procedural-geometry-authoring for SDF/3D elements, shader-authoring for post, module-authoring for data/multipass). Momentum-first: rough ALL the plates and wire them, then refine. Use when handed a reference (image / gif / mp4 / path or URL) and asked to recreate, rebuild, or match it in Sentinel. Plain plan mode then build — no phase-doc / session ceremony.
---

# Recreate Reference

Turn a reference clip/image into a matching **modular Sentinel scene**. Plain **plan mode → build**.
No phase docs, no `/start-session` `/end-session` `/wrap` `/audit`.

## Two rules, both non-negotiable

1. **The reference image is the spec.** Not the vision_eval JSON (that's a lossy hypothesis — if it
   disagrees with what you see, your eyes win). Keep stills open; judge by side-by-side.
2. **It is a MODULAR SCENE — a graph of separable modules — NEVER a monolith.** Every distinct
   visual language in the reference (e.g. leaves vs clusters vs petals vs wires vs frame vs
   background vs post) is its **own module/plate**, wired by typed data ports
   (generator → data-lane → renderer → compositor → post), each independently previewable. If you
   ever find two distinct languages sharing one `sceneMap`/shader, STOP and split them. One big
   shader-with-everything is the exact anti-pattern this skill exists to prevent.

## 1. Study the reference (minutes)
- Gif/big video → transcode to compact mp4 (ffmpeg). Make a contact sheet
  (`ffmpeg -i in -vf "fps=N,scale=W:-1,tile=CxR" sheet.png`), a couple of full-res key frames
  (`-ss T -frames:v 1`), zoom crops of anything ambiguous. **Look yourself first.**
- Run **one** `vision_eval` decomposition (12fps Gemini) for structure: elements back-to-front,
  what each is (2D/3D), motion (pattern/cycle/seamless-loop), palette. Reconcile with your eyes.

## 2. Design + build THROUGH the authoring skills (do not freelance a monolith)
- **Invoke the `modular-scene-authoring` skill — always.** It governs the design-first workflow:
  decide 2D-vs-3D and the data contract, and produce the **Element → Technique → Transport table +
  module graph** (one module per element/visual-language). This is the plan.
- **Per element, invoke the right authoring sub-skill and follow it:**
  - 3D / SDF geometry (hero objects, instanced 3D, exact dimensions) → **`procedural-geometry-authoring`**
    (shared `_shared/sdf` library, `sceneMap` contract, `sentinel_blueprint` for relational scenes).
    Build SDF the way that skill prescribes — do not hand-roll a one-off.
  - Full-frame post (grade/glow/chroma/grain) → **`shader-authoring`** (`hlslshader`).
  - Multi-pass / compute / structured-buffer data lanes, cloners, atlases → **`module-authoring`**.
  - Vector/trail/laser content → **`laser-content-authoring`**.
- Pick the technique per element (2D feedback/trail buffer · cloner + `prim_atlas` · hero SDF ·
  blueprint · texture-field · spline/segment · post shader · static overlay). Reuse from
  `modules/` and `knowledge/technique-catalogue.md` first.
- Draft the plan in `EnterPlanMode` (the module graph + build order, short), `ExitPlanMode` to approve.

## 3. Build momentum-first — rough ALL the plates, then refine
- **Momentum ≠ monolith.** Momentum means: stand up **every module rough** (rough geometry +
  placeholder material + rough motion) and **wire them into the compositor graph** in one fast pass,
  so the whole composed scene is on screen. A hard plate? Stub the module and keep going — but it is
  still its own module. Never collapse plates to save time.
- **Look at the whole vs the reference — once** (side-by-side; optionally one whole-scene
  `vision_eval mode:a_b` for the top 3–5 gaps).
- **Refine in 2–3 whole-scene passes:** biggest gaps first — geometry **character** → material →
  motion/timing — re-look each pass. Fix the responsible plate. Don't grind one element; don't chase
  a score.

## 4. Done
The composed scene reads as the reference at its key frames (your eyes + user sign-off). Harvest
reusable modules to `modules/` + a `knowledge/technique-catalogue.md` entry.

## Mechanics (full detail in `knowledge/reference-rebuild-guide.md`)
- Module: `modules/<name>/{shader.hlsl, manifest.yaml}` (shader FIRST, manifest LAST); `compile_check`
  → `create type=module` → `compile_status` ok → capture. Include `_shared/sdf` + `_shared/anim`;
  never `features:[sdf]` with the sdf headers. Wire data: `get_data_schemas` then
  `sentinel_graph add_link` by pin; `auto_layout`.
- Camera: default Fly; Orbit (`sdf_orbitRay`, target origin) for deterministic captures.
- Params: `sentinel_state set` one path at a time (`set_many`/`capture_at overrides` broken here);
  shader/manifest edits → destroy + recreate.
- Motion: `../_shared/anim/anim.hlsli` (`an_spring`, `an_stagger_*`, `an_loop_noise` for seamless
  loops); `sweep_record` + `motion-eval`; loop seam ≤ mean adjacent-frame diff.
- vision_eval A/B: `files:[ref, mine] mode:a_b` — ask for a diff, not a score.

## Don't
- **Build a monolith.** One module/`sceneMap`/shader carrying multiple distinct visual languages.
- Skip `modular-scene-authoring`, or hand-roll SDF instead of following `procedural-geometry-authoring`.
- Build from the decomposition text instead of the image.
- Perfect one element before the whole graph exists; per-step vision_eval score-chasing.
- Any phase-doc / `/start-session` / `/end-session` / `/wrap` / `/audit` ceremony.
