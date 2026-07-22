# Multi-Node Scene System (Hold, Atlas, Mux, Group Presets)

Sentinel's scene system lets one graph carry several looks and switch between them live: StreamDiff variants that freeze and resume on demand, an atlas that collects aligned stills from any pipeline, a mux that switches 1-of-N inputs in real time, and whole-group presets that snapshot and recall entire graph regions. These compose: cue or quantized triggers can drive the mux, group presets can recall a scene's parameter state, and the atlas can bank stills from whichever variant is live.

## StreamDiff Hold And Single-Frame Render

Per-node parameters on `streamdiff`:

- `hold` (bool): freezes diffusion while the node stays fully live. Input mapping, pre-image processors, control and style inputs keep flowing every frame; only the diffusion step is suppressed and the last generated frame republishes. This is finer than the whole-node bypass at `/sentinel/pipelines/<id>/enabled`, which stops the node cooking entirely.
- `render_one` (momentary action, also at `/sentinel/pipelines/<id>/actions/render_one`): fires exactly `render_count` diffusions, then returns to hold.
- `render_count` (int, default 1): makes the one-shot a render-N-then-hold.

A held node that has never generated still produces its first frame. All three ride StateTree, so OSC, expressions, MCP, and group presets reach them.

Multiple StreamDiff variants can share loaded TensorRT engines (a ref-counted engine pool keyed by engine file), so N variants of the same engine cost one engine load; execution is one variant at a time.

## Mux (Select 1-of-N)

The `mux` pipeline switches its output between up to 8 video inputs in real time:

- `selected` (int): which input is live.
- `solo_upstream` (bool): when on, selecting a variant automatically holds the non-selected upstream StreamDiff nodes (via `hold`) and un-holds the selected one, so only one variant diffuses at a time and switching is instant. Non-StreamDiff upstreams fall back to the `enabled` bypass, with prior state restored when solo releases them.

Quantized scene switching: drive `selected` from an expression or set it on a Conductor quantized trigger so cuts land on the beat.

## Scene Switcher (Groups-Mode Mux)

Setting a Mux's `source_mode` to Groups turns it into a Scene Switcher that collects Scene Groups wirelessly, with no input wiring. Author each look as a Scene Group annotation containing exactly one `groupoutput` pipeline fed by that look's final texture; the Group Output sets the look's resolution and fit (Letterbox, Crop, Stretch, or Passthrough). The switcher then offers every collected group in a compact Properties look grid.

- `selected_group`: persistent Scene Group entity id; StateTree, MCP, and expressions write this path.
- `fade_time`: 0 performs a clean preroll-then-cut; positive values render a smoothstep GPU crossfade, and retargeting mid-fade continues from the current blend without a jump.
- `allowed_groups`: comma-separated group ids or case-insensitive title substrings; accepts a literal string or a pure string `ref()` expression.
- `select/<slug>`: one momentary OSC trigger per switchable look (value `1.0` selects, self-resets).

Non-selected groups fully freeze (members skip processing and republish their last frame) while the switcher owns their enable state; preset recalls and enable writes on frozen groups defer until the group is selected or ownership ends. A group with zero or multiple Group Outputs shows as a warning tile and cannot be selected.

Verified MCP authoring sequence for a two-look switcher:

1. Build each look and end it in a `groupoutput` (`sentinel_pipeline create type=groupoutput`, then `set_input` from the look's final node; a source can feed it directly).
2. Place the look's nodes together, then `sentinel_graph add_annotation` with explicit `x`/`y`/`width`/`height` covering them, and `sentinel_graph convert_to_scene_group entity_id=<annotation_id>`. The response returns the group's `/sentinel/groups/<id>` path.
3. Create a `mux` and set `/parameters/source_mode` to `1` (enum: 0 = Wired, 1 = Groups).
4. Collection is immediate: one `select/<slug>` Button parameter appears per group, slugged from the annotation title ("Look A" becomes `select/look_a`), and `selected_group` holds the selected group's entity id (an `annotation_N` value). Write `1` to a trigger or write the entity id to `selected_group`; both work from OSC, expressions, and MCP.
5. Prove the cut by capturing the mux output per look. The mux output resolution comes from its own `width`/`height` parameters (default 1920x1080), with each look fitted per its Group Output settings.

## Cameras And Camera Switching

The `camera` node is a control node owning a shared fly/orbit rig (`camera_mode`, position/target, yaw/pitch, fov, near/far; the `Tab` hotkey toggles fly/orbit in an active preview with a gizmo flash, and an axis gizmo shows the mode). Camera-capable modules bind to it through a `camera_ref` parameter, or automatically through their Scene Group when the group contains exactly one camera node; explicit `camera_ref` wins, then the group camera, then the module's internal camera. Renaming a camera updates every consumer's `camera_ref`.

The `camswitch` node cuts or blends between camera nodes for show control: `cameras` filters the collection, `selected_camera` picks the live rig (write the camera's entity id, e.g. `Cam_B`), `blend_time` 0 cuts while positive values blend position, orientation, and fov smoothly, and per-camera triggers respond to OSC and Conductor cues. Retargeting mid-blend continues from the current pose.

Verified MCP facts: `camera_ref` takes an entity id, and pointing a module's `camera_ref` at a `camswitch` makes it follow whichever camera the switcher selects. While bound, writes to the module's own `camera_*` parameters produce no output change (proven by pixel diff: a bound-module local fov write changed 0.0% of pixels while the same write on the referenced rig changed the render); clear `camera_ref` to regain local control. Driving the rig over MCP is just `sentinel_state set` on the camera node's `camera_pos_*` / `camera_yaw` / `camera_pitch` / `camera_fov` values.

### Camera ownership and control-surface guardrail

Choose exactly one owner before authoring controls:

- Use the renderer's internal camera when the camera is local to that renderer and should be manipulated in its preview.
- Use an explicit `camera` or `camswitch` when multiple consumers need a shared rig or show-level switching.

Never expose camera-related parameters (binding, mode, position, orbit, target, FOV, or renderer-local camera rows) on a Scene Group or other top-level surface. Keep camera operation on the owning renderer preview or the explicit camera node's own Properties. A Scene Group containing exactly one camera binds compatible members automatically, so adding a camera can change ownership without changing the renderer's local rows; those rows then stop affecting the image.

After grouping or changing `camera_ref`, reopen the renderer preview and exercise the chosen owner. Do not accept StateTree write success as interaction proof.

## Atlas (Multi-Pass Still Bank)

The `atlas` pipeline collects aligned stills into a block-packed RGBA16F ring grid: per captured still it packs columns for color, segmentation, depth, and encoded data from whatever passes are wired in. Key controls: `capture_now` (manual trigger), `capture_slot`, `interval_enabled` + `interval_frames` (self-timing cycle), `settle_frames` (pad so upstream settles before commit), `slot_count`, `fit_mode`. It reports `occupied_count`, per-slot `slot_sequences`, and `cycle_state`, and publishes a `Slot Occupancy` data pin that downstream modules consume.

The proven chain: StreamDiff (held, `render_one` per still) feeds matting `AlphaMatte` + depth `Raw` into the atlas; a scene-spawner module renders one depth-displaced textured card per occupied cell into a 3D scene. Use `hold` + `render_one` to fill cells one clean still at a time.

## Whole-Group Scene Presets And Nesting

Scene Groups snapshot everything inside them: a group preset auto-captures every parameter of every contained pipeline plus each node's bypass state, with no manual control exposure. Nested groups resolve membership innermost-wins, and an outer preset can recall each inner group's chosen preset then apply its own overrides (preset-of-presets). Recall rides the batch StateTree write, so presets restore parameters that expressions or OSC also touch.

Use group presets as the scene-state layer under live switching: preset recall sets the look, the mux or Conductor decides what is visible and when.

Treat exposed Scene Group parameters as a deliberately authored interface, not a convenient mirror of member parameters. Start with roughly four to eight high-impact creative controls, count compound color/XY widgets as one, open the group Properties panel, and test every exposed control. Remove inactive, redundant, confusing, or implementation-level rows.

## Snapshot, Restore, Checkpoint

For agent workflows that mutate many parameters:

- `sentinel_state action=snapshot` and `action=restore`: capture and restore StateTree value sets around an experiment.
- `sentinel_capture action=checkpoint`: bundle a capture with the state snapshot so a look can be recovered exactly.
