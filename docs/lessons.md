---
type: lessons
updated: 2026-07-07
---


# Lessons

Gotchas worth knowing before re-hitting the same wall. Newest at top.

## 2026-07-07 - Screenshot window title matching is substring-based

**Symptoms**: A Sentinel screenshot request with `window_title: "Sentinel"` captured the terminal window instead of the app, because the terminal title also contained the word `sentinel`. An element screenshot for `Node Graph` also failed because that was not the registered element name.

**Cause**: `sentinel_screenshot window` matches by window-title substring. Broad title filters can hit unrelated windows such as terminals, browsers, or editors.

**Fix**: Use the exact Sentinel app title from `Get-Process sentinel | Select MainWindowTitle`, for example `Sentinel - Untitled`, before capturing proof screenshots. For graph layout proof, also keep `sentinel_graph get summary=true` as the authoritative coordinate/link record.

**Frequency**: recurring

**Discovered**: 2026-07-07

## 2026-07-06 - `line` is a reserved HLSL keyword

**Symptoms**: A Module shader failed to compile with `error X3003: unexpected token 'line'`
on a plain local declaration `float line = smoothstep(...)`. The line looked completely valid.

**Cause**: `line` (also `point`, `triangle`, `lineadj`, `triangleadj`) is a reserved
geometry-shader primitive keyword in HLSL — you can't use it as an identifier even in a
compute shader. (`projects/strata/modules/marks/marks.hlsl`, `wire_render/wire.hlsl`.)

**Fix**: Rename the variable (`line` → `strk`). Watch for `point`/`triangle` too.

**Frequency**: recurring (any time you name a stroke/line variable the obvious thing)

**Discovered**: 2026-07-06

## 2026-07-06 - Never declare the engine-injected buffers (`_Data0`, `_Tex0`, `LinearSampler`)

**Symptoms**: `error X3003: redefinition of '_Data0'` (and would be the same for `_Tex0`)
when a Module shader declared its own `StructuredBuffer<T> _Data0 : register(t0)` /
`Texture2D _Tex0` / `SamplerState`.

**Cause**: The Module injection preamble already declares the data-input buffer as `_Data0`
(+`_Data0_Count`) for each `data:N`, and the video-input texture as `_Tex0..N` + a
`LinearSampler` for each `inputs:N`. Declaring them again collides. (Confirmed by the working
`dada_render`/`post` shaders, which declare neither — only the record `struct`.)

**Fix**: Declare ONLY the record `struct` (whose fields match the schema) and use `_Data0[i]`
/ `_Tex0.SampleLevel(LinearSampler, uv, 0)` directly. Do not declare the buffer/texture/sampler.

**Frequency**: always (every data/video-input Module)

**Discovered**: 2026-07-06

## 2026-07-06 - `sentinel_state set_many` values field doesn't transmit via this MCP client

**Symptoms**: `sentinel_state action=set_many` always returned `Missing 'values': {path:
value, ...}` regardless of whether `values` was passed as an object or an array-of-`{path,value}`,
strings or numbers.

**Cause**: The current MCP client drops the `values` object/array parameter before it reaches
the server (client-side serialization, not a schema error).

**Fix**: Use individual `sentinel_state action=set` calls (batch them in parallel in one
message). Works fine.

**Frequency**: recurring (until the client is fixed)

**Discovered**: 2026-07-06

## 2026-07-05 - Engraving a groove into an SDF needs a `+eps` surface bridge

**Symptoms**: Carving recessed formwork grooves into a raymarched box lattice did
*nothing* — panels_on 0 vs 1 gave byte-identical renders, params had no effect. Looked at
first like a stale/cached render (framerate and param reads were live and correct).

**Cause**: The cutter's near-surface slab was `shell = max(d, -d - depth)`, which evaluates
to `0` exactly at the surface (`d≈0`). So the cutter was only negative for points *inside*
the solid — but a ray marching from outside stops at `d≈0` and never samples interior
points, so the subtraction never moved the zero-crossing. The engrave only affected
geometry the ray never visits. (`modules/steel_lattice/steel.hlsl`, `carveOne`.)

**Fix**: Make the removal slab straddle the surface with a small outward bridge:
`shell = max(d - eps, -d - depth)` (eps ≈ 0.02). Now the cutter is negative from a hair
*outside* the surface down to `depth` inside, so `d = max(d, -cutter)` actually pushes the
surface inward → a real recess. Same principle for any SDF engrave/emboss.

**Frequency**: recurring (any time you subtract surface detail from a marched SDF)

**Discovered**: 2026-07-05

## 2026-07-05 - Artist-facing XY controls should be Y-up, not raw UV-down

**Symptoms**: Abstract poster placement pads technically worked, but dragging Y felt inverted.
The scene also had a deeper editability problem: the smaller shape generators exposed many
placement controls, while the hero ribbon still hid its structure inside shader math.

**Cause**: The poster generators exposed direct UV-space positions (`y=0` at the top) as user
handles. That is natural for screen-space renderers but wrong for artist-facing layout controls.
The FUI dashboard modules used the better convention: Y-up/world-like controls in generators, with
renderers or record emitters converting to UV (`0.5 - y`) at the boundary.

**Fix**: Convert user-facing point pads to Y-up values and hide UV/Y-down conversion inside the
generators. For the abstract poster, `abstract_shape_gen` and `abstract_triangle_gen` now convert
inside record emission, while the hero ribbon uses a Y-up `abstract_ribbon_path` generator feeding a
data-consuming material renderer.

**Frequency**: recurring

**Discovered**: 2026-07-05

## 2026-07-05 — A merged buffer-consuming renderer defeats per-node previews

**Symptoms**: Built a data-driven cloner system where N placement generators fed ONE renderer
(`widget_render`) that merged all their buffers into a single pass. Correct output, but every
generator node's preview showed only a flat placeholder colour — the artist couldn't see what
any individual chain contributed, so tuning a chain meant editing blind.

**Cause**: A node's preview shows its own output texture. When rendering is centralised in one
downstream consumer, the upstream placement nodes produce only data buffers (no visual), and
the one renderer's preview shows the merged result, not any single chain.

**Fix**: Fuse mapping + rendering into a per-chain renderer (`modules/pl_render/`) so **each
cloner owns a renderer and outputs its own layer texture**; a wide additive compositor sums the
layers. Cost is identical (same total records/pixel, just split across nodes) and every chain is
now individually previewable and editable. Keep a merged renderer only for the rare "one big
pass" case.

**Frequency**: recurring (any instanced/cloner scene the artist needs to tune per-source)

**Discovered**: 2026-07-05

## 2026-07-05 — Mixing a texture input and data inputs in one Module pass needs distinct pass-binding slots

**Symptoms**: `widget_render` failed to compile with `X3004: undeclared identifier '_Tex0'`
even though the manifest declared a texture input and the pass referenced `input:0`.

**Cause**: The pass listed `{slot: 0, source: "input:0"}` (texture) AND `{slot: 0, source:
"data:0"}` — both on pass binding slot 0. The `_Tex0` / `_Data0` names derive from the `source:`,
but the pass `slot:` is the binding index and must be unique across all inputs in that pass; the
duplicate slot 0 clobbered the texture binding so `_Tex0` was never injected.

**Fix**: Give every input in a pass a unique binding slot — texture on `slot: 0`, data on
`slot: 1`, `slot: 2`, … (`modules/widget_render/manifest.yaml`). `_Tex0`/`_Data0`/`_Data1`
naming is unaffected because it follows `source:`, not the binding slot.

**Frequency**: recurring (any Module pass consuming a texture + one or more data buffers)

**Discovered**: 2026-07-05

## 2026-07-05 — Widening a compositor's input list shifts pin slots and mis-wires existing links

**Symptoms**: After expanding `hud_comp` from 6 to 12 inputs, the scene lost the hero gauge and
markers rendered where the gauge belonged. `list_links` showed `hud_gauge` disconnected and
`r_mark` wired into the Gauge slot.

**Cause**: Existing links were addressed by numeric `to_slot`. Inserting new inputs renumbered
the pins, so links that pointed at slots 2–5 now fed different named inputs than intended.

**Fix**: After any change to a node's input count, re-point its links by **pin NAME**
(`to_slot: "Gauge"`), not index, and verify with `sentinel_graph list_links`. Bonus gotcha:
`point2D` params convert cleanly from `_x`/`_y` float pairs *without* losing values precisely
because their state paths stay `name_x`/`name_y` — the same slot-vs-name distinction, in reverse.

**Frequency**: recurring (any time you add inputs to an already-wired node)

**Discovered**: 2026-07-05

## 2026-07-05 — `save_project bundle_modules` doesn't copy `modules/_shared/`

**Symptoms**: A bundled `.sentinel` show that `#include`s shared HLSL (e.g. the scientifica font from
`modules/_shared/fonts/`) is fine while the original workspace copy is loaded, but would fail to
compile if reloaded purely from the bundle — the `../_shared/...` include path resolves to a
`_shared/` dir that was never copied into `projects/<show>/modules/`.

**Cause**: `bundle_modules=true` copies only the Module folders referenced by pipelines; a shared
include directory that modules reference by relative path is not a pipeline and isn't followed, so
it's left out of the bundle.

**Fix**: After bundling a show whose modules include from `_shared/`, manually copy
`modules/_shared/` into `projects/<show>/modules/_shared/` (preserving `fonts/` and the `.hlsli`
files). Verify the bundle compiles standalone before treating it as portable.

**Frequency**: recurring (any bundled show using shared includes)

**Discovered**: 2026-07-05
