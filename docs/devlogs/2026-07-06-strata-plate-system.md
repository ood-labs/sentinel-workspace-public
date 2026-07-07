---
type: devlog
status: complete
session_start: "19:30"
session_end: "21:12"
approval: approved
summary: "Built strata — a multi-plate procedural distortion system (glossy blobs + melted marble + graphic framing) that recreates two abstract refs and is infinitely variable from one master seed; shipped as a blessed example + harvested 8 techniques"
note_created: true
updated: 2026-07-06
---

# 2026-07-06 - strata: multi-plate procedural distortion system

## Context

New build from two abstract 3D art references (glossy inflated gradient blobs on a gray studio
void framed by sharp graphic marks; a melted marble panel framed by a chrome wire cage). User
brief: make "tons of intricate, well-arranged geometry" beautiful FIRST, then distort — multiple
procedural passes on alpha, composited, each with different amounts/kinds of distortion, sharp
lines framing distorted things, one palette, infinitely variable. Builds directly on
[[desert_totem]]'s domain-warp toolkit.

## What we did

- **Designed a plate system, not a monolith.** Composite-of-plates architecture where every plate
  outputs **premultiplied-alpha RGBA coverage** so independently-distorted 3D raymarch plates and
  flat 2D graphic plates stack in one 2D compositor. This is the headline new technique (the
  "matte-aware SDF plate" contract).
- **Built 8 modules** under `projects/strata/`: `blob_layout` + `blob_render` (glossy op_smin blob
  mass, SSAA coverage matte, warp toolkit ported from `dada_render`), `marble_panel` (domain-warped
  fbm fluid card), `wire_render` (2D rings/strands/tri-cage), `marks` (red rules/squares/rivets/
  registration frame), `strata_bg` (studio void), `plate_comp` (premult-over multi-plate
  compositor), `strata_control` (master-seed + distortion macros), plus reused `signal` + `post`.
  New shared headers: `_shared/sdf/sdf_blob.hlsli` (glossy blob vocabulary) + `_shared/palette.hlsli`
  (the 10-colour language every plate draws from).
- **Beauty before distortion.** Got the arranged undistorted composite to a 95/100 independent
  reference-match score (vision_eval vs ref #7) BEFORE touching warp, exactly as the brief demanded.
- **Infinitely variable.** `strata_control` publishes a master seed + melt/twist/marble-warp macros
  as control outputs; `ref()` expressions drive every plate's seed + warp from it. One knob
  reshuffles the whole composition (proved seeds 5/12/27 → completely different, palette+framing
  intact). Twist even turns the checker cube into a harlequin diamond. Runs 60fps, 10 nodes healthy.
- **Shipped + harvested.** Added `!projects/strata/` to the allowlist gitignore (blessed example
  show, like desert_totem). Harvested the reusable techniques into top-level `modules/` and added a
  new "Plate system" section to `knowledge/technique-catalogue.md`.

## Decisions Made

- **Orbit-only camera on `blob_render`** (no `features:[camera]`) — a compositor plate wants fixed
  studio framing + MCP-drivable capture, and it sidesteps the known camera-feature reload crash.
- **Premultiplied-alpha everywhere** — the one contract that makes the whole plate system compose.
- **One shared `palette.hlsli`** — cohesion backbone; every plate reads `str_palette()` so all seeds
  read as one artist.
- **Marble composited UNDER the blobs** (slot 2) — reads as a backdrop card the mass sits on,
  matching ref #8's panel-behind-subject.

## Approvals & Locks

- User approved the plan up front (portrait 2:3, recreate ref #7 first then open the seed system).
- Final: "this one came out so good its ridiculous... a very good example" → ship it.

## Issues Encountered

- `line` is a reserved HLSL keyword (geometry-shader primitive) — `float line = ...` is a syntax
  error. Renamed to `strk` in `marks`/`wire_render`.
- Engine injects `_Data0`/`_Data0_Count` (from `data:N`) and `_Tex0..N`/`LinearSampler` (from
  `inputs:N`). Declaring them in-shader is a redefinition error — never declare, just use.
- `sentinel_state set_many`'s `values` field doesn't transmit through this MCP client (returns
  "Missing 'values'"); fell back to individual `set` calls.

## Next Steps

- Optional polish flagged by eval: tighter checker-cube UV, a touch more wire complexity, sharper
  spec glints.
- Could record a seed/warp sweep MP4 (motion-eval), push blob count higher for denser masses, or
  wire `signal`/OSC in for audio-reactivity.

## Cross-References

- [[desert_totem]] — the warp toolkit + DadaPart assemblage this builds on
- `knowledge/technique-catalogue.md` — new "Plate system" section
- `projects/strata/` — the shipped example show
