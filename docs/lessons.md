---
type: lessons
updated: 2026-07-05
---


# Lessons

Gotchas worth knowing before re-hitting the same wall. Newest at top.

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
