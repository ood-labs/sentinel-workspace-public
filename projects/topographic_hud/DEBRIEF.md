# Topographic HUD — Build Debrief

A modular Sentinel scene recreating a sci-fi topographic-HUD reference (flowing blue elevation
contours, orange accents + orbit arc, glowing data nodes + connector vectors, warped grid, tiny
tech labels, radar rings, teal atmosphere, bloom). Built as a 15-module graph, not a monolith.

*The build metrics below were recorded during the original authoring run.*

---

## By the numbers

| Metric | Value |
| --- | --- |
| Modules | 15 (~40 shader/manifest files) |
| `create` calls | 15 |
| `compile_check` calls | 17 |
| Compile results with an **error signature** | **0** |
| Compile results OK | 19 |
| Shaders needing a post-authoring **Edit** | **2** (`grid.hlsl` ×2, `expand_links.hlsl` ×1) |
| Live parameter `set` calls (aesthetic tuning) | 22 |
| `capture pipeline` look-cycles | 16 |
| Control-output expressions (the "signal bus") | 4 |
| `add_link` data wires / `set_input` texture wires | 6 / 14 |
| Hard tool errors, whole build | 3 (`set_many` ×2, `auto_layout` confirm ×1) |
| Final runtime | 60 fps · 1.55 ms/frame · 0 hotspots |

The headline: **almost nothing was rewritten.** Every shader compiled clean on first authoring;
only two files needed a code Edit afterward, and both were behavioral (grid warp continuity, link
distance selection), not compile fixes. All of the *look* was dialed with 22 live parameter sets —
zero shader recompiles for aesthetics.

---

## What worked

1. **`compile_check` as an offline gate.** Writing all shader files, then `compile_check` on the
   module dir *before* creating or reloading anything in the live graph, meant shaders were validated
   against the real injection preamble without touching running state. Result: 0 compile-error
   signatures across the whole build. This one discipline removed almost all iteration churn.

2. **A shared height-field spine.** One `field_gen` RGBA16F texture (R=elevation, G=region, B=slope,
   A=detail) is the single source of terrain. `contour_blue`, `contour_accent`, `grid_warp`, and
   `node_gen` all *derive* from it. Change the field once → the whole scene re-terrains coherently.
   This is the "pass the height map downstream for more specific accents" idea, realized.

3. **Three transports, never crossed.** Texture lanes (`set_input`) for the continuous field;
   structured-buffer data ports (`add_link`, cyan pins) for hard vector records (nodes, bezier links,
   labels); control outputs (`ref()` expressions) for reactivity. Each element used the transport it
   actually wanted — isolines from a field, connectors from spline records, text from a glyph atlas.

4. **The signal bus (the favorite).** One tiny `signal` module runs 4 LFOs and publishes them as
   control outputs (`pulse`, `sweep`, `beat`, `slow`). Four unrelated nodes then pull from that bus
   via compiled expressions:
   - `node_render/intensity = 0.42 + ref("signal/control_outputs/pulse") * 0.4`
   - `field_gen/warp_amount = 0.8 + ref("signal/control_outputs/slow") * 0.35`
   - `contour_accent/glow  = 0.8 + ref("signal/control_outputs/beat") * 1.6`
   - `frame_hud/rot_speed_a = 0.015 + ref("signal/control_outputs/slow") * 0.05`

   This **decouples animation authority from the animated nodes.** The nodes don't know what drives
   them; swap the `signal` module for an audio/OSC source and the whole scene becomes reactive with no
   rewiring. It's a publish/subscribe bus expressed through the expression graph — the cleanest part of
   the build.

5. **Expressive-by-parameter paid off.** Because every meaningful knob was an exposed, typed parameter
   (enums for modes, colors, counts, scales), *all* aesthetic iteration was `state.set`, never a code
   change. 22 sets across `compositor`, `node_render`, `contour_blue`, `post` fixed over-bright nodes,
   chroma speckle, and layer balance. The look is **data, not code** — which is exactly what "modular
   and expressive" is supposed to buy you.

6. **Prove buffers, don't trust schemas.** `capture_data_port` confirmed record counts / active flags /
   positions before wiring consumers, catching contract mismatches at the producer instead of as a
   blank downstream texture.

---

## What didn't — friction points

1. **`set_many` is broken.** Both object and array forms returned `Missing 'values'` — the `values`
   argument doesn't survive the MCP bridge. Every tuning change became an individual `set` round-trip:
   **22 calls that should have been ~5 batches.** This was the single biggest ergonomic tax of the build.

2. **Layout doesn't happen on its own.** Nodes spawn at (0,0) and stack invisibly; `auto_layout` must
   be invoked manually and then needs `confirm=true` once any node has a set position. The graph became
   unreadable mid-build and required explicit user intervention to fix. Layout is a chore that recurs
   after every create.

3. **Tuned values are trapped in the `.sentinel`.** The 22 live sets persist in the saved project but
   are **not** written back to the module `manifest.yaml` defaults. A fresh `create` of any of these
   modules ignores everything we dialed in. There is no "promote live → defaults" path, so the tuned
   look is fragile and non-portable at the module level.

4. **Manual capture/tune/capture loop.** Iteration was 16 plain `capture pipeline` calls interleaved
   with 22 `set` calls. `capture_at` (apply overrides → render → capture → restore, and it accepts
   *lists* of values to produce a contact sheet) would have collapsed much of that into single calls —
   it was underused because the plain capture path is the obvious one.

5. **Wiring is manual and pin-name-sensitive.** Texture inputs (`set_input`) and data ports
   (`add_link` by pin name) are separate mechanisms; you must know which lane an edge is and the exact
   pin name. Easy to get right here, but it's cognitive load that a smarter connect could absorb.

---

## MCP tooling gaps — ergonomics wishlist

Ranked by how much friction each would have removed on this build:

1. **Fix batch parameter set** (`set_many`, or a new `set_params`). Highest impact. Tuning a scene is
   inherently many-params-at-once; the 1-at-a-time fallback dominated the tuning phase.

2. **"Bake live → manifest defaults."** An action that writes a module's current live parameter values
   back into its `manifest.yaml` defaults. Makes a tuned look portable and a fresh `create` reproduce
   it. Right now the only record of the design is the project blob.

3. **Layout-on-create / no more (0,0) stack.** Either auto-place a new node relative to a parent hint
   at create time, or an opt-in "auto-layout after each create" mode. The recurring manual `auto_layout`
   (and the resulting layout interruption) is pure avoidable friction.

4. **A signal-bus / control-output inspector.** List every control output in the graph and every
   expression that `ref()`s it — a routing view for the exact pattern that worked best here. Today the
   bus is real but invisible; you have to read expressions one node at a time to see the wiring. Making
   it first-class would turn the favorite pattern into a discoverable feature.

5. **A "tune loop" front door.** Surface `capture_at` with a param dict as *the* iteration primitive
   ("apply these overrides, give me a contact sheet, restore"), instead of the capture/set/capture dance.

6. **Smarter connect.** One `connect A→B` that auto-resolves texture-lane vs data-port, picks the pin by
   type, and validates producer count == consumer bound — folding `set_input` + `add_link` +
   `get_data_schemas` into one safe call.

7. **Capture diffing.** `proof_bundle` is excellent; a companion that diffs two captures (or A/B's a
   single param across values into one sheet) would close the loop on "did that change help?"

---

## One-line takeaway

The modular decomposition and the control-output signal bus were the two decisions that made this fast
and expressive; the friction was almost entirely in *parameter ergonomics* (no batch set, no bake-back)
and *graph hygiene* (manual layout) — all tooling gaps, none of them design problems.
