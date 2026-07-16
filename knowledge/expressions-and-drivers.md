# Expressions And Drivers

Sentinel has two parameter-linking mechanisms, both controlled through `sentinel_expression`:

- **Expressions** compute a value from a formula every frame. One-directional: the formula drives the target. Use them when a value is derived (a hand pinch scaled into a shader amount, a beat phase shaping a size).
- **Binds** keep two or more parameters equal in both directions. Writing any bound endpoint moves every endpoint. Use them when several handles should stay the same value (a group control and its member parameter, two modules sharing one speed). See the Parameter Binds section below.

## Use sentinel_expression

Use the typed MCP expression tool with:

- `path`: full StateTree parameter path.
- `expression`: formula text.

Example:

```json
{
  "action": "set",
  "path": "/sentinel/pipelines/ripple_module/parameters/wave_amount",
  "expression": "0.2 + ref(\"hand_track/control_outputs/pinch_primary\") * 2.0"
}
```

Regular StateTree `set` is not enough for drivers. It writes a value, but it does not compile or register an expression.

## Expression Basics

Expressions can use:

- `time`: seconds since app start.
- `dt`: frame delta time.
- `frame`: frame counter.
- `self`: the current parameter value.
- math functions such as `sin`, `cos`, `abs`, `clamp`, `min`, `max`, `sqrt`, `floor`, and `ceil`.
- `ref("...")` to read another parameter or control output.

Common forms:

```text
sin(time * 2.0) * 0.5 + 0.5
clamp(ref("features_0/control_outputs/largest_size") * 3.0, 0.0, 1.0)
0.1 + ref("mediapipe_0/control_outputs/pinch_primary") * 4.0
```

## Control Output Refs

Control outputs live under:

```text
/sentinel/pipelines/<pipeline_id>/control_outputs/<name>
```

In expression strings, use the compact `ref()` form:

```text
ref("mediapipe_0/control_outputs/pinch_primary")
ref("features_0/control_outputs/blob_count")
ref("module_lfo/control_outputs/speed")
```

Expressions can also target bool parameters (nonzero drives true, e.g. StreamDiff `hold`), and string filter parameters such as Mux `allowed_groups` accept a pure string `ref()` expression.

## Motion Functions

The expression engine registers a shared motion vocabulary matching the Module shader header `modules/_shared/anim/anim.hlsli`:

- `spring(t, m, k, c)`: closed-form spring progress 0 to 1.
- `spring_v(t, x0, v0, m, k, c)`: spring from a stamped initial value and velocity.
- `stagger(index, count, span, style)`: per-instance delay.
- `anticipate(t, bias)`: back-ease anticipation.
- `loop_noise(t, period, radius, seed)`: seamless looping noise.

Use these instead of hand-written spring or easing math so expressions, shaders, and tests share one set of equations. For rate-driven motion, integrate phase (`phase += rate * dt` semantics) rather than multiplying a live rate by absolute time; see `knowledge/motion-choreography.md`.

## Conductor References

A `conductor` node publishes clocks, cue envelopes, and macros as control outputs that expressions can read:

```text
ref("Conductor/control_outputs/beat_phase")
ref("Conductor/control_outputs/total_beats")
ref("Conductor/control_outputs/enter_phase")
ref("Conductor/control_outputs/tightness")
```

Cue sheets loaded with `sentinel_conductor action=load_sheet` generate these expressions automatically and register live-tweakable sheet parameters; see `knowledge/motion-choreography.md`.

## Parameter Binds

A bind is an undirected network of two or more parameter paths. Writing any endpoint (UI drag, OSC, authored viewport control, preset recall, MCP `sentinel_state set`) propagates the value to every other endpoint. There is no master side.

Create, inspect, and remove binds with `sentinel_expression`:

```json
{ "action": "set_bind", "path": "/sentinel/pipelines/warp_a/parameters/speed", "peer_path": "/sentinel/pipelines/warp_b/parameters/speed" }
```

```json
{ "action": "set_bind", "endpoints": [
  "/sentinel/pipelines/warp_a/parameters/speed",
  "/sentinel/pipelines/warp_b/parameters/speed",
  "/sentinel/pipelines/glow_0/parameters/pulse_rate"
] }
```

```json
{ "action": "list_binds" }
```

```json
{ "action": "list_binds", "path": "/sentinel/pipelines/warp_a/parameters/speed" }
```

```json
{ "action": "clear_bind", "path": "/sentinel/pipelines/warp_a/parameters/speed" }
```

Rules and behavior:

- `set_bind` accepts `path` + `peer_path` for a pair, or `endpoints` with two or more paths. Binding a parameter that is already bound merges the networks into one.
- `list_binds` returns every network (`id` plus `endpoints`), or just the network containing `path`. The response includes flush statistics for diagnostics.
- `clear_bind` removes the ENTIRE network containing `path`, not just that endpoint.
- Endpoints must be existing parameter paths of the same type, and enum parameters must have identical option lists. Button and String parameters, `enabled`, control outputs, and read-only or hidden paths are rejected with a specific error.
- Propagation runs once per frame on the main thread. A write from an off-main source such as OSC can lag its peers by one frame.
- Undoing a write to a bound parameter reverts the whole network in one step.
- Binds persist in the project file and survive node rename, delete with undo, project import, and module hot reload. If a bound module parameter registers late because its shaders are still compiling, it receives the network's value when it appears.

Binds and expressions interact under one rule: a bind network may carry AT MOST ONE expression-driven endpoint, and that expression drives the whole network. Setting a second expression anywhere on the same network is rejected with an error naming the rule, in the UI and over MCP. Dragging a bound parameter never removes the bind; dragging an expression-driven parameter still clears that expression (override on touch).

Scene Group exposed parameters are binds. The group parameter and the member parameter form a two-endpoint network (one per component for color and XY compounds), so the member's own slider and the group widget move together and the link survives touching either side. Projects saved before binds existed, where exposes were one-way `ref()` expressions, migrate automatically on load.

In the Properties panel, bound rows show a bind badge, and the row context menu lists the bound peers and offers unbind.

Binds are absent on installs at or below 0.5.34. If `set_bind` is not in the live IPC capabilities, control the parameters individually instead.

## Rename Safety

Use real rename operations, not delete-and-recreate, when changing node names. Sentinel rewrites stored expressions during true renames so references keep working.

## Inspecting Drivers

Useful MCP actions:

- `sentinel_expression action=get path=<state path>`
- `sentinel_expression action=clear path=<state path>`
- `sentinel_expression action=list`
- `sentinel_expression action=list_binds` (all bind networks, or one with `path`)
- `sentinel_expression action=clear_bind path=<state path>` (removes that path's whole network)

Use `sentinel_pipeline info` to find parameter names and current control output summaries.
