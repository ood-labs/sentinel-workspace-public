---
type: devlog
status: complete
session_start: "13:20"
session_end: "18:05"
phase: "modular-scene-authoring / FUI reference build"
subphase: "cloner-kit workflow"
approval: approved
summary: "Recreated a dense FUI dashboard reference, evolving from a hand-placed composite to a reusable data-driven cloner kit; banked the kit + updated the modular-scene-authoring skill to steer there"
note_created: fui-dashboard-cloner-kit
updated: 2026-07-05
---

# 2026-07-05 - FUI Dashboard: from hand-placed composite to a reusable cloner kit

## Context

User asked to recreate a dense sci-fi FUI/HUD dashboard reference (circular gauges, orbital
rings, wireframe globe, data panels, warning triangle, tick-fans, corner tabs, dashed
connectors, mint-on-black) via `/modular-scene-authoring`. What started as a faithful
recreation turned into an architecture R&D session: three full rebuilds plus a refinement
pass, each driven by the user pushing for more modularity, density, and editability. The
end state is `projects/fui_dashboard/` and — the durable output — a **reusable Layout Kit**
in `modules/` plus a substantially rewritten skill.

## Work done

**v1 — composite of hand-placed procedural layers.** `hud_bg`, `hud_gauge` (hero 25% dial),
`hud_orbits` (orbits + globe), `hud_panels`, `hud_leaders`, `hud_labels` (scientifica glyph
blit), `signal` bus, `hud_comp`, reused `post`. Faithful but sparse and hardcoded.

**v2 — data-driven widget instancing.** User: "way more items, nodes that feed placement into
renderers, atlases, 3D depth." Built `prim_atlas` (32 HUD primitives baked into an 8x4 grid,
R=body/G=core), `layout_gen`+`detail_gen` (compute nodes emitting `StructuredBuffer<Widget>`
placement records), and `widget_render` (stamps atlas cells per instance, projected through a
drifting camera for real parallax + depth fog). ~290 instances, 60fps.

**v3 — the reusable Layout Kit.** User: the seed generators were "shitty… we should have one
really good reusable layout generator with tons of modes… take a grid, draw splines, spawn
points." Built a composable placement pipeline on one universal 48B record `PNode`:
`pl_grid` (7 modes: Grid/Ring/Spiral/Scatter/Line/Border/Radial) → `pl_path` (Catmull-Rom
spline shaper) → `pl_spawn` (jitter/decimate/branch) → `pl_style`/`pl_render` → `spline_render`.
Replaced both seed generators with ~6 composed `pl_grid→pl_render` chains + a
`pl_grid→pl_path→spline_render` connector chain.

**Refinement pass (user feedback, each a real improvement):**
- **Previewability:** the merged `widget_render` left every chain node a blank placeholder.
  Authored `pl_render` (pl_style mapping + atlas stamp + depth camera fused, outputs a real
  texture) so each cloner owns a renderer and its node preview shows its own layer. Retired
  `ps_*`+`widget_render`; widened `hud_comp` to 12 additive inputs.
- **point2D pads:** converted positional float pairs to XY pads in `pl_grid` (`center`,
  `extent`, explicit `line_start`/`line_end`) and `hud_orbits` (`orbit`, `globe`). Naming the
  pad to match the old `_x`/`_y` names preserved all values across reload.
- **Line mode** reworked from center±extent scatter to an explicit start→end segment.
- **Shared focal point:** `focal` control node (one `point2D` pad → x/y control outputs)
  drives both the bespoke `hud_gauge` hero and the `pg_hero` ring-halo via `ref()`
  expressions (world→UV converted in-expression). One pad moves the whole hero as a unit.
  The `25%` label position was exposed as a param and driven from `focal` too, so it tracks.
- **Signal-bus motion:** routed `signal`'s pulse/sweep/beat/slow into hero-halo rotation,
  orbit breathing, label glow, and a top-row beat pulse.
- **Boundary frame:** `pl_render` can compute the bbox of its point cloud and draw a padded
  frame around it (per-chain toggle). Enabled on the panels grid.

**Harvest + skill.** Catalogued the kit across three new/updated sections of
`knowledge/technique-catalogue.md` (Layout kit; Instancing/atlases/depth; FUI/HUD chrome).
Rewrote `modular-scene-authoring` SKILL.md with a major new section "Dense & instanced scenes:
the Layout Kit", the three rules (compose-many, render-per-chain, depth-not-layers), the
cohesion patterns (shared control source, signal bus, boundary frame), a palette-table row,
and point2D-pad parameter guidance. Mirrored to `.agents/`. Moved the superseded
`layout_gen`/`detail_gen` to `scratch/_superseded/`.

## Decisions made

- **2D composite-of-layers**, not single-scene — heterogeneous widget languages, per-layer post.
- **Data-driven placement is the default for dense instanced scenes**; hand-placement only for
  a few bespoke focal pieces (hero dial, globe).
- **Render per-chain (`pl_render`), not one merged pass** — previewability beats the marginal
  efficiency of a single kernel; cost is identical (same total records/pixel), split across nodes.
- **One universal `PNode` record** for the whole placement kit so any stage chains to any other.
- **Shared control nodes** (`focal`, `signal`) as the single source for anything multiple nodes
  must agree on (position, motion) — driven by `ref()` expressions.
- Kept `hud_gauge`/`hud_orbits`/`hud_labels` bespoke (focal detail), everything else clonered.

## Approvals & locks

- User approved the full-rewire scope (build the kit, replace both seed generators + connectors)
  and keeping the hero/orbits bespoke (plan `radiant-stirring-cerf.md`). Signed off the end
  result as "fucking great" and requested this end-session + skill steer.

## Issues encountered

- **Texture input + data inputs in one pass need DISTINCT pass-binding slots.** `widget_render`
  had `_Tex0` undeclared because the atlas texture and data:0 both used pass binding slot 0;
  the `_Tex`/`_Data` names come from the `source:` but the binding slot must be unique.
- **Expanding a compositor's input count shifts pin slots.** After widening `hud_comp`, existing
  links wired by index now fed the wrong pins (gauge/labels/splines landed on the wrong slots;
  `r_mark` ended up on the Gauge slot and the real gauge was disconnected). Re-point by pin NAME
  after any input-count change.
- **A merged buffer-consuming renderer defeats per-node previews** — the whole reason for the
  `pl_render` rewrite. Design consequence, caught only by the user trying to edit a chain.
- **`sentinel_state action=set_many`** returned "Missing 'values'" for both object and array
  forms through the MCP bridge; fell back to many individual `set` calls.
- Live-editing by the user mid-session left a couple of chains (fan, panels) hand-dragged into
  odd states (kind 30 solid discs); reset the affected chain rather than the whole scene.

## Next steps

- Promote `projects/fui_dashboard/` to a blessed example show (add `!projects/fui_dashboard/` to
  `.gitignore`) after cleaning the bundle — 3 saves left suffixed `_2`/`_3` module dupes and
  `proof*/` capture folders; re-bundle once cleanly first.
- Convert the remaining `hud_gauge` `sec_*`/`fan_*` float pairs to pads for full consistency.
- Optional: make `25%` a live number (osBlitInt driven by hero value) instead of a static glyph.
- Optional: the interactive "draw a line the points adhere to" module the user floated — it
  would slot in as another `PNode` source feeding `pl_path`.
- `set_many` MCP bug is worth handing to whoever owns the server (recurs from prior debriefs).

## Cross-references

- [[2026-07-05-workspace-repo-and-hud-debrief]] — prior session; the topographic_hud build that
  seeded the FUI/HUD chrome and signal-bus techniques this build extended.
- `knowledge/technique-catalogue.md` — Layout kit / Instancing / FUI chrome sections.
- `.claude/skills/modular-scene-authoring/SKILL.md` — the "Dense & instanced scenes: the Layout
  Kit" section is this session's distilled workflow.
- Plan: `~/.claude/plans/radiant-stirring-cerf.md`. Memory: `fui-dashboard-system`.
