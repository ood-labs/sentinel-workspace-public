---
type: lessons
updated: 2026-07-26
---


# Lessons

Gotchas worth knowing before re-hitting the same wall. Newest at top.

## 2026-07-26 - A tool that defaults to one of two targets will silently measure the wrong one

**Symptoms**: Six consecutive full-corpus runs showed every lane collapsing
(kick -0.24, hat -0.32, BPM ~103 on all eleven patterns). It survived reverting
the change under test, a clean project reload, `--no-reset`, and byte-comparing
both module copies against the committed sources. It read as the committed score
table having stopped being reproducible.

**Cause**: `tools/audio_test/score_detector.py` had
`--lane-map default="lane_map.json"`, and that map names `pulse_baseline` -- the
Phase 1 detector. Every run measured the wrong module and printed the result
under a pulse2 subphase heading. The numbers were entirely plausible *for that
detector*, which is exactly why it survived four rounds of bisection: nothing
looked corrupt, it just looked worse.

**Fix**: `--lane-map` is now required with no default; the chosen map is written
into every score table; and comparing against a baseline whose `detector` field
differs from the current run is a hard error rather than a table.

**This was already known and written down, which is the actual lesson.** The 2C3
devlog records the same trap, and `sweep_inhibit.py` carries a shouting header
about it ("LANE MAP IS EXPLICIT AND NOT OPTIONAL"). Both documented the footgun
and neither removed it, so it fired again and cost six full-corpus runs plus a
clean project reload. A documented footgun is still a footgun; if the fix is a
one-line `required=True`, write the fix rather than the warning.

**The transferable part**: when two similar targets exist and a tool picks one by
default, a wrong answer is indistinguishable from a real result. Before
bisecting a surprising measurement, confirm WHAT was measured -- the provenance
fields, not the numbers.

**Frequency**: one-time (fixed), but the class is recurring

**Discovered**: 2026-07-26

## 2026-07-26 - An exponential tracker converges to the mean; summaries report the median

**Symptoms**: A dual-loop PLL settled at 93.6 hops while the tempo it tracked
published 88.2 -- 6% slow, while locked and correcting every cook. Reported as
an unexplained defect, since an exponential tracker's only fixed point is its
observation.

**Cause**: Both things were true and neither was a bug. The observation's median
was 88.16 but its **mean was 95.83**: the comb intermittently returned a
metrical relative (131.8 hops, a 3:2 dotted quarter) on about one cook in six.
The loop tracked the mean faithfully. Every summary I had written -- and the
`diag_tempo_stability` output -- reported medians, which are precisely the
statistic that hides this.

**Fix**: `modules/pulse2_analyzer/pll.hlsl` -- reject observations outside a
relative window (`tempo_reject`, 0.18) rather than averaging them. Counter
decays on agreement instead of resetting, or one agreeing sample in a wrong
period holds the loop there forever (measured: syncopated_funk_105 parked at
80.3 hops against an observed 107.2, counter climbing to 146 and being knocked
to zero repeatedly).

**The transferable part**: when a filter's output disagrees with its input,
compare it against the same statistic the filter computes. A median-vs-mean gap
IS the finding, not noise around it.

**Frequency**: recurring (any smoothing over a multi-modal estimator)

**Discovered**: 2026-07-26

## 2026-07-26 - force_reload does not reset module parameters to manifest defaults

**Symptoms**: A live `beat_snap` of 0.15, left behind by an earlier experiment,
survived every `force_reload` and silently scored a whole corpus against a
mechanism that ships disabled.

**Cause**: `reset_detector` in `tools/audio_test/sentinel_ipc.py` documented that
force_reload "resets params to manifest defaults" (attributed to a 2026-07-08
lesson). It does not. It drops data-port links and clears `ref()` drivers;
parameter values persist.

**Fix**: `reset_detector` now reads the manifest from the module's `project_dir`
and WRITES every numeric default before applying overrides. Defaults are no
longer assumed.

**Related**: this also surfaced that `classify_mode` defaulted to Off while the
shipped project ran it at 1, so scoring from manifest defaults dropped snare F1
by 0.33 while kick and hat reproduced at +0.000. A module whose own default does
not reproduce its own published numbers is a trap; the default was corrected.

**Frequency**: always

**Discovered**: 2026-07-26

## 2026-07-26 - Control-loop gains applied per cook are frame-rate dependent

**Symptoms**: A beat-tracking PLL reported the correct period (80.9 hops = 140
BPM, confirmed by control output) yet completed only 28 phase cycles where that
period implied 46, with not one beat suppressed by either gate. Continuity
scores stayed low no matter how the gains were tuned; lowering one traded jitter
for drift and raising it traded back.

**Cause**: `modules/pulse2_analyzer/pll.hlsl` applied its correction once per
COOK. A cook covers roughly three analysis hops while a beat spans eighty-odd,
so a nominal gain of 0.15 acted as a loop gain near 3.0 per beat. The loop
became overdamped, parked the accumulator on the observation, and resisted
advancing past it, which changes the emitted beat RATE rather than merely its
smoothness. Cooks-per-beat depends on frame rate, so the same code tracked
differently at 60 fps than at 30.

**Fix**: Scale every gain by the fraction of a beat actually elapsed during that
cook (`advanced = (limit - start) / period`), making the gains mean "fraction of
the error corrected per beat" and removing the cook-rate dependency. Note the
span must be the range the accumulator actually advanced, not the range of new
hops available.

**Frequency**: always, for any control loop in a per-cook shader pass

**Discovered**: 2026-07-26

## 2026-07-26 - Circular smoothing of a quantity that rotates by construction

**Symptoms**: Circular (phasor) averaging was added to smooth a noisy phase
estimate. The resulting vector strength sat at 0.14-0.16 on EVERY pattern,
steady four-on-the-floor and dense breakbeat alike. Identical numbers across
material that differs wildly is the tell.

**Cause**: The comb filter reports phase as an offset measured backwards from
the newest analysis hop. As the newest hop advances, a perfectly stationary beat
grid still makes that offset sweep through a full turn. The quantity rotates by
construction, so its circular mean is uniform and averaging it destroys the
signal rather than the noise.

**Fix**: Smooth the phase ERROR (observation minus accumulator), which is the
stationary quantity while locked. Coherence went from 0.15 to 0.997 on steady
patterns. General rule: before circularly averaging, confirm the quantity is
stationary in the frame you are averaging it in.

**Frequency**: one-time, but the class recurs wherever a value is measured
relative to a moving reference

**Discovered**: 2026-07-26

## 2026-07-26 - A cut that depends on ordering breaks silently when you re-sort

**Symptoms**: A twelve-lane regression-gate failure (per-lane F1 drops of
0.011-0.022) appeared after a harness change with no detector change behind it.
The obvious suspect was a detector parameter that had been raised in the same
session; it was innocent.

**Cause**: `tools/audio_test/sentinel_ipc.py` drops records left over from the
previous playthrough by scanning for a BACKWARDS STEP in sample position, which
only exists while records are in detection (serial) order. Adding a second data
ring with its own independent serial sequence prompted sorting the merged list
by sample position first, which makes a backwards step impossible. The scan
silently became a no-op and stale records survived as false positives.

**Fix**: Cut per lane in serial order, then merge and sort by position. The
function was extracted to `cut_pre_restart()` specifically so it could be unit
tested without a running app; `tools/audio_test/test_ipc_cut.py` asserts the
failure mode directly.

**Frequency**: one-time

**Discovered**: 2026-07-26

## 2026-07-26 - Continuity metrics that divide by the estimate count reward silence

**Symptoms**: Beat continuity scores looked implausibly healthy on some
patterns while the beat train was visibly wrong.

**Cause**: `tools/audio_test/metrics.py` normalised the longest correct run by
`len(est)` alone. A tracker emitting three beats against a hundred reference
beats scored a perfect 1.0, indistinguishable from one that got all hundred
right, because its three beats happened to be consecutive and correct.
Under-emission is the most likely silent failure of a beat clock and the metric
was paying a bonus for it.

**Fix**: Normalise by `max(len(ref), len(est))`, matching mir_eval. Unit tests
in `tools/audio_test/test_metrics.py` pin the behaviour.

**Frequency**: one-time

**Discovered**: 2026-07-26

## 2026-07-26 - A regression gate on one metric blesses defects in every other

**Symptoms**: Five separate beat-tracking defects landed and were caught only by
manual inspection. Every one of them left all three onset-lane F1 scores at
exactly +0.000 against the committed baseline, so the regression gate passed
each time.

**Cause**: `score_detector.py`'s gate iterated lane F1 only, while the table it
guards also carries BPM error, metrical level and continuity. Onset detection
and beat tracking are independent subsystems sharing one score table; gating one
says nothing about the other.

**Fix**: Extend the gate to BPM error and metrical level. Continuity was
deliberately left ungated: repeat runs on unchanged code swing by 0.3 CMLc, so
any threshold tight enough to catch a real regression fires constantly on noise.
Gate what is stable, report what is not, and say which is which.

**Frequency**: recurring

**Discovered**: 2026-07-26

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
