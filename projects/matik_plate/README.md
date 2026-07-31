# MATIK PLATE

An interactive black-and-white technical plate: wireframe molecular organisms growing inside
a dense field of procedural instrument panels, connective hairlines and registration marks.

Reviewed output: **`MX_Post`** (1080 x 1080).
Saved graph: `matik_plate.sentinel`. Scene Group: **MATIK PLATE** (`annotation_45`).

## Component map

```
MX_Console ──Plate──┬─────────────────► MX_Instruments ─┐
(interactive plan)  ├─────────────────► MX_Circuitry ───┤
                    │                                    ├─► MX_Composite ─► MX_Post
                    └► MX_Organism ──► MX_Wireframe ────┘        ▲
                       (Nodes)          (Wire + Coverage)         └── Plate records
```

| Node | Responsibility |
| --- | --- |
| `MX_Console` | The plan authority. Owns plate space, generates the layout, holds hand edits. Interactive editor. |
| `MX_Organism` | Grows branching molecular trees from the plan's organism anchors. Stateless; animation lives here. |
| `MX_Wireframe` | Rasterizes those trees as opaque black solids with white mesh lines. Owns the internal camera. |
| `MX_Instruments` | Draws each plan cell as one of 16 instrument types. |
| `MX_Circuitry` | Frame, registration marks, edge rails, micro-mark scatter, leader hairlines. |
| `MX_Composite` | Stacks circuitry → organisms → panels. Derives panel knockout from the records. |
| `MX_Post` | Bloom, grade, grain, edge burn. Nothing structural. |

## Contracts

**PLATE SPACE** (`modules/_shared/plate.hlsli`) is the single layout transform: `[0,1]²`,
origin top-left, +y down. It is identical to a square generator pass's `uv` and to normalized
viewport pointer coordinates, so render, pick and drag cannot drift apart. `MX_Console` is the
only node that decides placement; every consumer reads plate space straight off `uv` and must
not re-apply a global offset or scale. `MX_Organism` is where the graph leaves 2D — it maps the
unit square to world `[-1,1]` on X and Y, y flipped to world-up.

**One `Plate` buffer, 128 records of 48 bytes**, discriminated by `role`:
records 0–63 are instrument cells, 64–71 organism anchors, 127 the console's header. It is
declared `persistent` and as a `state_buffer`, so hand edits survive saves, presets and undo.

**Bonds are implicit.** A `MolNode` stores its parent index, so one buffer carries both the
spheres and the tubes. The structures genuinely are branching trees, not arbitrary graphs.

**Coverage has two different owners, deliberately.** Panel knockout is re-derived in
`MX_Composite` from the same records the panels were drawn from, so it cannot drift. The
organisms instead publish a real `Coverage` output, because a sphere's interior is black and
indistinguishable from the background by colour alone.

## Things that will bite the next person

- **`PLAN_VERSION` in `mx_console/plan.hlsl`.** The plan buffer is persistent and only rebuilds
  when its signature changes. Parameters feed that signature; shader edits do not. Bump
  `PLAN_VERSION` when you change the layout algorithm or a recompile will silently keep serving
  the previously generated plan.
- **No `fwidth` in compute passes.** The instrument perspective grid derives its line width from
  the analytic gradient of the projection. `ddx`/`ddy` are pixel-shader only.
- **Bond length must not follow radius decay.** Making both geometric collapses every branch onto
  its own root. Bond length is constant across a tree; radius tapers over ~8 generations then holds.
- **Growth needs outward persistence and soft containment.** Low persistence scatters children back
  across the parent into a featureless ball; no containment marches whole clusters off the plate.
- **Mesh lines come from generated `(u,v)`, not from `atan2` of the normal.** Deriving longitude
  from the normal puts a seam down every sphere where the line-width derivative explodes.

## Camera

`MX_Wireframe` owns Sentinel's internal camera (`features: [camera]`,
`viewport.interactions: [camera]`, `camera_ref` empty, Fly mode). Its saved pose frames plate
space 1:1 — position `(0, 0, -1.732)`, target origin, 60° FOV, so half-height is exactly 1.0 and
the wire layer registers with the instrument layer. Flying the camera is an intentional creative
move, not a mistake. RMB look, WASD move, wheel adjusts speed.

## Console interaction

Click to select a cell or anchor, drag to move it. `K` cycles kind, `X` toggles active,
`N` re-rolls that record, `R` reseeds the whole layout, `C` clears the selection.
Edits set `F_EDITED` and survive until the layout signature changes.

The console is a square fixed-resolution generator rather than a `follow_panel` Canvas on
purpose: it draws a schematic *plan*, not a fitted copy of the program image, so a 1:1
coordinate contract is worth more than a responsive dock.

## Exploration record

Two rounds were run and the losers were fixed rather than deleted, so all variants stay usable:

- **Layout preset** — *Guillotine* won (dense mixed-scale packing, closest to the source).
  Column Rack is a strong second. Ring Array was too sparse and Dense Strata produced full-width
  bands; both were reworked.
- **Mesh style** — *Lat-Long* won (the source's language, best silhouette definition).
  Hatch Shell and Ribbon Cage are good distinct alternates. Contour Bands is weakest since
  horizontal-only lines lose the silhouette.

## Performance

Seven nodes, ~1.2 ms total frame time. The wireframe draw pass is 337,920 vertices
(320 nodes × (960 sphere + 96 tube)); inactive nodes and roots emit degenerate triangles.
Both single-threaded generator passes are ~1500 iterations — noise next to any render pass.
