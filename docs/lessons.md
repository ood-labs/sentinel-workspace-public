---
type: lessons
updated: 2026-07-26
---


# Lessons

## 2026-07-26 - Invoking module-ui.ps1 from the Bash tool needs the call operator

**Symptoms**: `pwsh -NoProfile -File tools/module-ui.ps1 ...` fails with `pwsh: command not found`.
Switching to `powershell -NoProfile -File tools/module-ui.ps1 ...` then fails inside the script:
`Split-Path : Cannot bind argument to parameter 'Path' because it is an empty string` at
`tools/module-ui.ps1:10`.

**Cause**: Two separate things. PowerShell 7 is not on PATH in this workspace, only Windows
PowerShell 5.1. And `powershell -File <relative-path>` leaves `$PSScriptRoot` empty, so the script's
`[string]$Root = (Split-Path -Parent $PSScriptRoot)` default dies before the body runs.

**Fix**: Use the PowerShell tool with the call operator and an absolute path:
`& "C:\...\tools\module-ui.ps1" generate -Module modules/<name>`.

**Frequency**: always, for this script

**Discovered**: 2026-07-26

## 2026-07-27 - One flag for two facts: fixing a dropped command created a corrupted drag

**Symptoms**: A drag would accelerate away from the pointer instead of following it, and the pre-drag
undo point was destroyed. Introduced by the fix for the opposite defect (a dropped command), and
invisible to a 42-guard suite that was fully green.

**Cause**: `pending` was made to mean two different things. As an ARM flag it means "an edit is
queued and its undo snapshot still needs taking". The queueing fix also started using it to mean
"a command arrived while the cook was busy", which is true on every cook of a live drag: cook k
drains it into `exec`, the next pointer move re-queues behind that, forever.
`modules/spline_desk/snapshot.hlsl` gated on `pending` alone, so it re-captured the drag base every
cook, and `update.hlsl:36` computes `base = drag_snapshot[i] + (pointer - drag_start)` with
`drag_start` frozen at pointer-down. An advancing base makes the knot land at `base0 + sum(deltas)`.

**Fix**: Split the two facts. `armed` (spline_desk/types.hlsli) is set only on a cook where the
command is queued AND nothing is executing; the snapshot gates on that. Splitting them also revealed
a second bug the single flag was hiding: a structural edit queued behind a busy cook used to execute
with no snapshot ever taken.

**Frequency**: recurring - it is the generic hazard of a state field whose name describes the value
rather than the question it answers. "Is something pending" and "is the undo point ready" felt like
the same question until a drag made them differ on every frame.

**Discovered**: 2026-07-27

## 2026-07-27 - A guard can be written for a defect it cannot reach

**Symptoms**: A new guard for the `spline_desk` arm-then-execute queueing fix passed. Reverting the
fix, recompiling and re-running it: still PASS.

**Cause**: The guard fired an automation door six times with no settle, expecting the commands to
collide. Each MCP round trip is slower than the 16 ms cook, so every command got a cook to itself.
The defect needs a NON-SNAP command landing on the cook right after a snap command armed, and the
only non-snap command a pointer produces is a drag move (`modules/spline_desk/interaction.hlsl:190`).
There is no automation path to it.

**Fix**: Kept the guard for the invariant it does assert, renamed it to match, recorded the negative
result in its docstring, and marked the fix unguarded in the devlog. The general rule: a new guard
is not evidence until you have watched it FAIL against the reverted fix. Passing on a build that
already works proves nothing.

**Frequency**: recurring

**Discovered**: 2026-07-27

## 2026-07-27 - Probing live GPU state needs to know what the probe perturbs

**Symptoms**: Two false FAILs from guards that had passed minutes earlier - a gizmo reseed sentinel
reading 0.0, and spline anchors "differing after reset".

**Cause**: Two different wrong assumptions about live state. `do_reset` runs `initialize()` and
reseeds to four FIXED anchors (`modules/spline_desk/update.hlsl:11`); it does not restore what was
on screen, so asserting a round trip asserted the wrong thing. And a persistent structured buffer
can be recreated by the host, reading all zeros for the single cook before the shader's reseed lands.

**Fix**: Assert the seed, not a round trip. For the sentinel, re-read a few times before failing,
because recovery is the property under test and one sample cannot distinguish "never seeded" from
"seeded next frame". Also: a guard that fires automation doors must restore everything it moved,
including the active lane, which `do_reset` alone does not cover.

**Frequency**: recurring

**Discovered**: 2026-07-27


Gotchas worth knowing before re-hitting the same wall. Newest at top.

## 2026-07-23 - Scaled feedback passes need their actual texture extent

**Symptoms**: Seed Lab markers and the later amber guide line appeared at the correct normalized coordinates, but the Biotic Source deformation appeared at doubled positions and stopped responding outside the upper-left quarter.

**Cause**: The `organism` feedback buffer runs at `scale: 0.5`, while its evolution pass calculated bounds, UVs, and aspect from the root 1280x720 `_Resolution` (`modules/scientific_biotic_source/evolve.hlsl:13`). The later full-resolution overlay consumed the same records correctly and concealed the upstream mismatch.

**Fix**: Query the feedback texture with `_Tex0.GetDimensions`, use that extent for dispatch bounds, UV normalization, aspect, and Laplacian clamping, then prove alignment on the raw Field output with seeds beyond `0.5` on both axes (`modules/scientific_biotic_source/evolve.hlsl:18`).

**Frequency**: recurring

**Discovered**: 2026-07-23

## 2026-07-22 - Zero-control Canvases must not include control-state helpers

**Symptoms**: The Material Library compiled with authored controls, but removing its last Canvas control failed with `undeclared identifier '_ViewportControlFlags'` even though the preview never called `suiInteraction`.

**Cause**: `sui_v2.hlsli` includes `sui_interaction.hlsli`, whose helper bodies reference the host-injected control flag array. Sentinel does not inject that array when the manifest declares zero viewport controls (`modules/procedural_building_materials/preview.hlsl:1`).

**Fix**: For a truly control-free Canvas, include only the required theme, core, layout, and typography headers and define the small local panel helper used by the preview (`modules/procedural_building_materials/preview.hlsl:10`).

**Frequency**: recurring

**Discovered**: 2026-07-22

## 2026-07-22 - Migrate persistent normalized state when expanding a Canvas

**Symptoms**: Expanding an editor from a right-hand subpanel to a full Canvas would either leave existing light handles clustered in the old region or change their world-space lighting meaning.

**Cause**: The durable light state stored absolute normalized Canvas coordinates, while the lighting emitter interpreted those coordinates through the old panel-to-world transform (`modules/procedural_building_lighting/update.hlsl:3`).

**Fix**: Version the state marker and migrate once through `old canvas -> world -> new canvas`, then use shared `lcCanvasToWorld`/`lcWorldToCanvas` functions everywhere (`modules/procedural_building_lighting/update.hlsl:6`, `modules/procedural_building_lighting/types.hlsli:7`).

**Frequency**: recurring

**Discovered**: 2026-07-22

## 2026-07-22 - Render, pick, and drag must share one spatial mapping

**Symptoms**: A facade marker could be clicked and dragged, but the highlighted brick was offset from the marker and pointer motion did not feel one-to-one.

**Cause**: The elevation renderer, selection descriptors, picker, and drag inversion used related but non-identical normalized transforms and vertical conventions.

**Fix**: Centralize the edit rectangle and semantic/canvas conversion functions, including the discrete bay/floor mapping, and use them from preview, descriptors, pick, interaction, and update (`modules/procedural_building_facade/types.hlsli:4`, `modules/procedural_building_facade/types.hlsli:16`).

**Frequency**: always

**Discovered**: 2026-07-22

## 2026-07-22 - StreamDiff needs display color and native depth as separate lanes

**Symptoms**: Architectural StreamDiff color looked incorrectly exposed and ControlNet failed to preserve the procedural structure when the same renderer image fed Video, Style, and Control Image.

**Cause**: The renderer's linear HDR working image was not a suitable display-referred video input, and a duplicated color texture does not provide depth conditioning.

**Fix**: Keep the internal render in `RGBA16F`, publish a tone-mapped sRGB `RGBA8` color output and a separate camera-aligned `RGBA8` depth output, then feed only native depth to Depth ControlNet (`modules/procedural_building_render/manifest.yaml:6`, `modules/procedural_building_render/manifest.yaml:85`).

**Frequency**: always

**Discovered**: 2026-07-22

## 2026-07-22 - Use Properties instead of duplicating dense Canvas parameter rails

**Symptoms**: Authored slider rails became awkwardly spaced or cramped as Canvas panels changed aspect ratio, and maintaining separate visual and host hit rectangles added complexity without improving the spatial editors.

**Cause**: Sentinel 0.5.44 viewport controls use fixed normalized rectangles. Dense sliders were duplicating functionality already provided by Properties while competing with the actual massing, elevation, material, and lighting canvases.

**Fix**: Keep Canvas controls only for spatial tools and direct manipulation; keep dense dimensions, counts, colors, response, energy, and quality parameters in Properties. Revisit authored responsive control stacks only as a deliberate host capability.

**Frequency**: recurring

**Discovered**: 2026-07-22

## 2026-07-15 - Project import does not carry Scene Group authority

**Symptoms**: Imported example graphs looked structurally correct, but parameters driven by `/sentinel/groups/annotation_*` expressions snapped toward zero and the imported Gallery looks diverged from their standalone active presets.

**Cause**: Project import recreated pipelines and links but did not recreate source annotations, Scene Group presets, or their ids. Expressions retained references to the absent source group paths (`tools/repair-showcase-gallery-imports.ps1:87`).

**Fix**: Bake each standalone group's active preset into the mapped Gallery pipelines, preserve the preset's enabled/bypass map, and remove only expressions that reference `/sentinel/groups/`. Keep internal LFO/control-output expressions intact.

**Frequency**: recurring

**Discovered**: 2026-07-15

## 2026-07-15 - Read UTF-8 project JSON explicitly in Windows PowerShell

**Symptoms**: A Gallery repair pass changed every annotation separator from `·` to visible mojibake even though the JSON remained syntactically valid.

**Cause**: `Get-Content -Raw` under Windows PowerShell can decode UTF-8-without-BOM using the active ANSI code page before the script rewrites the entire project as UTF-8 (`tools/repair-showcase-gallery-imports.ps1:8`).

**Fix**: Read with a strict `UTF8Encoding`, write a same-directory temporary file without a BOM, and atomically replace the destination with a disposable backup. Verify all expected Unicode markers after a disposable regeneration.

**Frequency**: always

**Discovered**: 2026-07-15

## 2026-07-15 - Serialize contention-prone Gallery Module reloads

**Symptoms**: A 51-Module Gallery cold load timed out `Fruit_LFO` and `dada_render`; a later sequence of clean-checkout project loads exited Sentinel during Topographic HUD startup.

**Cause**: The two Module timeouts were compile contention rather than source errors because both compiled successfully alone. The exact cause of the later process exit remains unresolved and belongs in Sentinel application diagnostics.

**Fix**: For Gallery recovery, wait for the compile queue to settle and force-reload the slow Modules one at a time. Treat a process exit as an application blocker, preserve the load sequence, relaunch without a kill action, and do not claim the interrupted runtime sweep passed.

**Frequency**: recurring

**Discovered**: 2026-07-15

## 2026-07-08 - `force_reload` drops data-port links, expression drivers, and resets params

**Symptoms**: After every `force_reload` (or manifest hot-reload) of a module, downstream stopped
working: a `data_input`/`data_output` link (e.g. `Face_Stitch → Face_Cutout` Anchors,
`Face_Cutout → Clone_Overlay` Clones) was gone, a `ref()` expression driver on a param had been
cleared, and the node's parameters had snapped back to manifest defaults.

**Cause**: `force_reload` re-registers the node from scratch. **Video (`set_input`) links survive**,
but **typed data-port links (`add_link`) do not**, expression drivers on that node's params are
dropped, and param values reset to manifest `default:`. Recurs on every reload of a data-producing
or -consuming module.

**Fix**: After any `force_reload`, immediately: (1) re-add every `sentinel_graph add_link` into/out of
the node, (2) re-`sentinel_expression set` any drivers on its params, (3) restore non-default param
values. `add_link` is idempotent (`created:false` if it already exists), so re-adding is safe.

**Frequency**: recurring

**Discovered**: 2026-07-08

## 2026-07-08 - Cross-frame accumulation needs a persistent buffer, not a graph self-loop

**Symptoms**: Wiring a module's own output back into its input to build an accumulation canvas
(feedback) produced only the *current* frame's content — imprints never piled up, no matter the
decay. Expected an ever-growing accumulation; got a single frame.

**Cause**: A naive graph cycle (`Node.Out → Node.In`) provides at most one frame of history and does
not chain into a persistent canvas. `docs/module-pipeline.md` distinguishes "persistent **buffers**"
(cross-frame) from "multi-pass **feedback**" (within a frame) — cross-frame texture persistence is the
former, not a self-loop.

**Fix**: Accumulate into a **persistent structured buffer** (they survive frames and aren't cleared):
a compute pass reads the incoming layer + the buffer and writes the buffer back (ping-pong via a
scratch buffer to avoid in-pass read/write races when transforming). See
`projects/face_collage/modules/accum/` (`paint.hlsl`/`transform.hlsl`/`present.hlsl`); same pattern as
`strata_control`'s phase accumulation.

**Frequency**: recurring

**Discovered**: 2026-07-08

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

## 2026-07-26 — A `follow_panel` layout must be authored for arbitrary extents, and one defect class causes most of the failures

**Symptoms**: Six separate layout bugs across three rebuilt stations, all the same shape — a caption
printed straight through the control above it, a title crossing a lane band, a label landing on a
neighbouring plate. Each appeared only at one particular panel size.

**Cause**: A caption is a fixed number of PIXELS tall sitting in a NORMALIZED gap. The gap shrinks
with the panel; the caption does not. Everything looks right at the extent you authored at.

**Fix**: Give every station a `capFits(gapPx, scale)` helper and **drop** any label whose gap cannot
hold it, rather than drawing it. Demand real clearance, not a coincidence: 12px for an 11px glyph
run left a title sitting one pixel off a frame; 15px is clearance. Derive text scale from
`min(W/1280, H/720)` — height alone picks 2x on a canvas only 1.25x bigger, and puts giant glyphs in
a wide, short dock. Related: to test a forced extent you need a throwaway node, because an open
panel owns its module's render size and editing `resolution:` then reloading does nothing.

**Frequency**: recurring (every `follow_panel` module)

**Discovered**: 2026-07-26

## 2026-07-26 — `type: button` parameters are a dead end for anything that must be recalled

**Symptoms**: A `type: button` parameter global reads as a permanent `1.0` once fired and survives
`force_reload`. Separately, `expose_scene_group_parameter` refuses them outright:
`Error: Button parameters cannot be exposed`.

**Cause**: The button global is a latch, not an impulse, and a Scene Group control surface is built
from ordinary parameter rows.

**Fix**: Never drive an action from a `type: button` parameter. Use a `bool` read as a rising edge,
or an `int` on a bank for anything that is really a mode. Those undo, preset, save with the project,
take OSC and expose on a group. Where a module draws its own clickable plate, read that control's
`down` bit from the interaction-flags array instead of the parameter. A mode backed by an ordinary
`int` also sidesteps the latch entirely.

**Frequency**: always

**Discovered**: 2026-07-26

## 2026-07-26 — In a cyclic pass graph, snapshot-for-undo on the command frame records the wrong state

**Symptoms**: Undo fires — the command is observably emitted — and nothing moves.

**Cause**: `snapshot` reads the durable buffer and `update` writes it, while `update` reads the
snapshot and `snapshot` writes it. The scheduler runs `update` first, so a snapshot taken on the
command frame captures the state AFTER the edit. Undo then restores the document to where it
already is. A drag-only editor never exposes this, because it snapshots at drag-begin where pre and
post happen to be equal; the accident does not survive a discrete edit like "delete" or "close".

**Fix**: Arm on one cook, execute on the next, and snapshot on the arm cook — which mutates nothing,
so it is order-independent by construction rather than by scheduler luck. Second, related trap: if
undo preserves a whole flags word to protect the selection, any document state packed into those
same flags becomes un-undoable. Preserve only the selection bit.

**Frequency**: recurring (any module with a feedback pass cycle and undo)

**Discovered**: 2026-07-26

## 2026-07-26 — `sentinel_graph action=profile` is CPU wall-clock; per-node numbers track the active panel, not drawing cost

**Symptoms**: A 2D UI station reported 0.58 ms early in a session and 8.7 ms later with no code
change. Disabling roughly forty percent of its drawing changed the number by nothing. Closing its
floating window changed nothing either.

**Cause**: It is a CPU wall-clock profiler for graph triage, exactly as documented. For a
`follow_panel` canvas the dominant term follows whichever station currently owns the active panel.

**Fix**: Use the profile to find a node that has fallen over, not to tune a shader. Before
attributing cost to a code path, bisect by disabling that path and re-measuring — and never quote a
per-node figure without saying what extent and panel state it was measured under. A profile taken
while nodes report `framesProcessed = 0` is not a measurement; confirm frames are climbing across
the sample window.

**Frequency**: recurring

**Discovered**: 2026-07-26

## 2026-07-26 — A "live source" node must consume its own published values

**Symptoms**: A station whose whole purpose was publishing theme metrics had a control that moved
4 pixels. The value was published, printed in its own readout table, and correct everywhere it was
displayed.

**Cause**: The metric was never passed into the layout function. Nothing was wrong with the
publishing path, which is exactly why it survived review — the readout proved the value existed,
not that anything used it.

**Fix**: For any node claiming to be a source of truth, assert that changing each published value
changes the node's own render by a substantial pixel count. A readback proves a value exists; only
a render diff proves it is consumed. Watch for quantization masking this too: integer glyph scales
mean `1.8` renders identically to `1.0`, so test at values that must cross a step.

**Frequency**: recurring (any parameter-publishing module)

**Discovered**: 2026-07-26

## 2026-07-26 — Sphere tracing with a fixed step floor makes overshooting rays miss forever

**Symptoms**: A scatter of single black pixels, one near the centre of every raymarched object —
precisely where the surface faces the camera dead-on.

**Cause**: `if (abs(d) < 0.0018)` paired with `travel += max(d, 0.004)`. A ray that overshoots lands
inside the surface at `d = -0.004`, the floor keeps pushing it deeper, `abs(d)` grows, and the hit
test never fires again.

**Fix**: Scale the hit epsilon with distance and tie the step floor to it, and test `d < eps` rather
than `abs(d) < eps` so crossing the surface counts as a hit. Detect it by counting near-black pixels
whose four neighbours are all lit, rather than by eye. Related palette trap: an additive coloured
rim on an already-lit body clips the brightest channel first and drifts the hue — blend toward the
colour instead of adding it.

**Frequency**: recurring (any SDF raymarcher)

**Discovered**: 2026-07-26

## 2026-07-26 — `bundle_modules` never reuses an existing bundled directory

**Symptoms**: Re-saving a bundled project produces `Motion_Console_1`, `Spline_Output_1`, and on the
next save `_2`, while the `.sentinel` points at the newest suffix and the earlier folders become
orphans.

**Cause**: Each save copies module folders in fresh and de-duplicates by renaming rather than
overwriting.

**Fix**: Delete every bundled station directory (keeping `_shared/`) before a re-save, then save
once. Verify afterwards that the `project_dir` values in the saved file are relative and that the
directory list matches the node list exactly. Note `_shared/` is still not copied by the bundler —
see the 2026-07-05 entry — so check its contents are current against the workspace copy before
treating the bundle as portable.

**Frequency**: recurring (every re-save of a bundled show)

**Discovered**: 2026-07-26

## 2026-07-26 — A control with two visible numbers needs zero conversions, not one

**Symptoms**: An XY pad reticle sitting 68% down its well with `0.32` printed beside it. The
Properties row said `0.68`, the canvas readout said `0.32`, and the published control output said
`0.32`. Every one of them was "correct" by its own local rule.

**Cause**: A "flip Y exactly once, at publish" convention. The renderer drew the raw parameter so
the reticle would land under the pointer, and the publish pass inverted it so downstream consumers
would get "up = more". Nothing was wrong in isolation; the two rules simply described the same
control with different numbers, and the readout was fed from the published side.

**Fix**: Zero conversions. The pad's value is the host parameter, unmodified, on every surface —
Properties row, drawn reticle, printed readout, published output. A consumer that wants the other
direction inverts at the point of use, where the inversion is visible in the consumer's own code.
"Once" is not a checkable property: nothing stops a second renderer from flipping again, and
counting flips across a state pass, a render pass and a shared header is exactly the accounting
that fails. Zero is checkable — any `1.0 -` on a pad component is a bug on sight. Related trap:
do not infer the host widget's direction by measuring where your own renderer drew the marker.
That measures the renderer.

**Frequency**: always (every pad, slider or gizmo with both a drawn position and a printed value)

**Discovered**: 2026-07-26

## 2026-07-26 — A pixel diff proves a control is wired, never that the result is usable

**Symptoms**: `body_scale` was published, printed in the readout, and never passed into the layout
function. Wiring it was proven with a pixel diff: "4 changed pixels to 139,985", recorded as a fix
and committed. The operator then reported the sheet's type as visibly worse and controls spilling
off the left edge of the frame.

**Cause**: The stored project value was 2.0, tuned while the parameter was inert. Making it
load-bearing made a value nobody had ever seen applied suddenly double every body glyph. The pixel
diff measured *that the pixels changed*, which was never in doubt once the plumbing was connected.
Two further defects rode in behind it: outer padding was a published PIXEL metric being multiplied
again by the glyph scale, and section captions were fit-tested at the body scale while being drawn
at the section scale.

**Fix**: When you connect a parameter that was previously inert, re-examine every stored value of
it — a saved setting tuned against a no-op is not a setting anyone chose. And close the loop with
an actual look at the render, not a diff count: assert what the image must *contain* (captions
present and clear of their controls, nothing outside the frame), which is the standard the phase
doc already sets for captures and which a diff count quietly sidesteps. A layout metric published
in pixels is spent in pixels; a caption is fit-tested at the scale it is drawn at, and shrinks to
fit before it is dropped.

**Frequency**: recurring

**Discovered**: 2026-07-26

## A control agreeing with itself is not a control agreeing with the host

The Style Authority pad was reported flipped, fixed, and reported flipped again.
The first fix removed a `1 - raw` so the reticle, the readout, the published
output and the stored parameter all carried the same number. Every one of those
surfaces belongs to the module. The Properties row does not, and the module was
upside down against it, so making the module self-consistent changed nothing the
operator could see.

The host's XY pad is **Y-up**: value 1 is the top. Canvas pixels run the other
way, so `lerp(r.xy, r.zw, val)` -- the obvious thing to write -- draws every pad
inverted against the widget for the same parameter. The kit now maps value to
pixel through one function, `sui3PadPoint`, which is where the inversion lives.

Two habits come out of it. Derive a convention from the thing you must match,
never from your own renderer: Phase 3A measured where its own module drew the
marker and concluded the direction from that, which is circular and got the
wrong answer. And when a guard compares a component only to itself, it cannot
see a whole-component offset -- the pad guard asserts a *rendered* reticle
position against the host convention, and reverting the one line makes it read
0.9 as 0.10.

## A section caption may never outrank the title

Style Authority's title gives back size when the band above the first control is
thin; at 1355x826 a requested 3x title renders at 1x. Section captions had no
such give-back, so PUBLISHED, METERS and PRIMITIVES kept their full 2x and came
out double the height of the page title. Nobody reads that as "section scale is
2"; they read it as the sheet looking wrong. Any type scale that can be clamped
by available space needs every smaller rank clamped against it, not just against
its own request.
