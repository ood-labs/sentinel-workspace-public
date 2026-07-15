# Expressions And Drivers

Expressions make Sentinel parameters update every frame. Use them when one node should drive another node, such as a hand pinch controlling a shader amount.

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

## Rename Safety

Use real rename operations, not delete-and-recreate, when changing node names. Sentinel rewrites stored expressions during true renames so references keep working.

## Inspecting Drivers

Useful MCP actions:

- `sentinel_expression action=get path=<state path>`
- `sentinel_expression action=clear path=<state path>`
- `sentinel_expression action=list`

Use `sentinel_pipeline info` to find parameter names and current control output summaries.
