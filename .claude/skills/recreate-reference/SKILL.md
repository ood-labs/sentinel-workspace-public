---
name: recreate-reference
description: Recreate a reference image or video clip as a modular Sentinel scene. Studies the reference with your own eyes plus a vision_eval decomposition, drafts a short build plan in plan mode, then builds it momentum-first — rough the whole scene, then refine. Use when handed a reference (image / gif / mp4 / path or URL) and asked to recreate, rebuild, or match it in Sentinel. No phase-doc, no /start-session /end-session /wrap /audit ceremony — just plan mode then build.
---

# Recreate Reference

Turn a reference clip/image into a matching modular Sentinel scene. Plain **plan mode → build**.
No `/formalize-plan`, no phase docs, no `/start-session` `/end-session` `/wrap` `/audit`.

## The one rule
**The reference image is the spec. Build the WHOLE scene rough first, then refine** — never perfect
one element before the rest exist. Your eyes on a side-by-side are the judge; `vision_eval` is a
gut-check for a gap list, **never a score to chase.**

## 1. Study the reference (minutes, not a ceremony)
- If it's a gif or a big video, transcode to a compact mp4 (ffmpeg). Make a contact sheet
  (`ffmpeg -i in -vf "fps=N,scale=W:-1,tile=CxR" sheet.png`), a couple of full-res key frames
  (`-ss T -frames:v 1`), and zoom crops of anything ambiguous. **Look at them yourself first.**
- Run **one** `vision_eval` decomposition (native 12fps Gemini path) for structure: elements
  back-to-front, what each element actually is (2D/3D), motion (pattern / cycle / seamless-loop),
  palette. Treat it as a hypothesis — reconcile with your eyes; **if it disagrees with what you see,
  your eyes win** (this is the lesson that cost 9 wasted iterations on a polyhedron).

## 2. Draft the plan (plan mode)
Keep it short. In `EnterPlanMode`, write:
- **Element → Technique → Transport** — one row per element.
- A **one-line module graph** (generator → data-lane → renderer → compositor → post).
- **Build order.**
Pick the technique per element: 2D feedback/trail buffer (draw-on strokes, paint) · cloner +
`prim_atlas` (sprite/stamp swarms) · hero raymarch SDF (one exact abstract object) ·
`sentinel_blueprint` (relational 3D object scenes) · texture-field generator (gradients) ·
spline/segment (paths, wires) · single-pass `hlslshader` post (grade/glow/chroma/grain) ·
static-texture overlay (UI chrome). Check `knowledge/technique-catalogue.md` to reuse first.
`ExitPlanMode` for approval.

## 3. Build momentum-first
- **Rough the whole scene end-to-end:** every element (rough geometry + placeholder material +
  rough motion), wired, composited, animating — all parts on screen together in one pass. Hard
  element? Stub it and keep going. Do NOT perfect any single element yet.
- **Look at the whole vs the reference — once:** one side-by-side capture (optionally one
  whole-scene `vision_eval` `mode:a_b` for the top 3–5 gaps).
- **Refine in 2–3 whole-scene passes:** biggest gaps first — geometry **character** → material →
  motion/timing — re-look each pass. Stop when it reads as the reference. Don't grind one element;
  don't chase a number.

## 4. Done
Whole scene reads as the reference at its key frames (your eyes + user sign-off). Optionally harvest
reusable modules to `modules/` and add a `knowledge/technique-catalogue.md` entry.

## Mechanics (full detail in `knowledge/reference-rebuild-guide.md`)
- **Module:** `modules/<name>/{shader.hlsl, manifest.yaml}` (write shader FIRST, manifest LAST).
  `compile_check` (offline) → `create type=module` → `compile_status` ok → `sentinel_capture`.
  Include `_shared/sdf` + `_shared/anim`; never `features:[sdf]` with the sdf headers.
- **Camera:** default Fly; use **Orbit** (`sdf_orbitRay`, target origin) for deterministic captures.
- **Params:** `sentinel_state set` ONE path at a time (`set_many` / `capture_at overrides` are broken
  through the MCP client). Live params instant; **shader/manifest edits need destroy + recreate**.
- **Motion:** `../_shared/anim/anim.hlsli` — `an_spring` (+ BOUNCY/SNAPPY/SMOOTH/HEAVY),
  `an_stagger_*`, `an_loop_noise` (seamless per period); same funcs in the expression engine. Verify
  with `sweep_record` + `motion-eval`; loop seam ≤ mean adjacent-frame diff.
- **Precise 3D object scenes:** `sentinel_blueprint validate → compile → audit`.
- **vision_eval A/B:** `files:[ref, mine] mode:a_b` — ask for a structured diff, not a score.

## Don't
- Build from the decomposition text instead of the image.
- Perfect one element before the whole scene exists.
- Per-step vision_eval score-chasing or per-element checkpoints.
- Any phase-doc / `/start-session` / `/end-session` / `/wrap` / `/audit` ceremony.
