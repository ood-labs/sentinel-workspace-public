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

The expression engine registers a motion vocabulary that can also be implemented
in project-local Module helpers:

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

## ref() Reads Parameters, Not Only Control Outputs

`ref()` resolves any StateTree value path, including another node's **parameters**:

```text
ref("TP_Render/parameters/camera_distance")
```

That makes one node's control surface drivable from another's without a data link, a control output, or a graph edge.

## Mirroring A Camera Instead Of Sharing One

When two camera-capable renderers must show the same viewpoint, the obvious answer is one `camera` node with both nodes' `camera_ref` pointed at it. That is correct for show-level camera switching, and **wrong whenever either node needs viewport interaction**.

With `camera_ref` set, the host takes over the viewport's pointer events to drive the external camera. A Module's own event reducer will see them flagged `HOST_CONSUMED` and skip them — which is the correct thing for it to do, but it means any authored pointer interaction on that node silently stops working. A click-to-interact surface simply stops responding, with nothing in health or logs to say why.

The alternative keeps interaction intact: let the **interactive** node own its internal camera, and drive the follower's camera parameters by expression.

```text
ref("TP_Render/parameters/camera_target_x")   # and target_y/z
ref("TP_Render/parameters/camera_distance")
ref("TP_Render/parameters/camera_yaw")
ref("TP_Render/parameters/camera_pitch")
ref("TP_Render/parameters/camera_fov")
ref("TP_Render/parameters/camera_near")       # and camera_far
```

Two things to get right:

- **Match `camera_mode` as a plain value**, not an expression. A follower left in Fly mode while the leader is in Orbit builds its view from yaw/pitch and ignores the target entirely, and the result is close enough to look like a subtle projection bug rather than a mode mismatch.
- **Do not mirror derived values.** In Orbit mode `camera_pos_*` is computed from target/distance/yaw/pitch. Forcing it as well fights the follower's own solver. Mirror the inputs and let it derive the same result.

Cost: expressions evaluate a cook behind, so the follower trails by one frame **while the camera is moving** and is exact the moment it stops. For a zero-lag follower, have the leader publish its view matrix as a data output and consume it downstream in the same cook.

## Rename Safety

Use real rename operations, not delete-and-recreate, when changing node names. Sentinel rewrites stored expressions during true renames so references keep working.

## Inspecting Drivers

Useful MCP actions:

- `sentinel_expression action=get path=<state path>`
- `sentinel_expression action=clear path=<state path>`
- `sentinel_expression action=list`

Use `sentinel_pipeline info` to find parameter names and current control output summaries.
