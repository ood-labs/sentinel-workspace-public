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

## Atlas (Multi-Pass Still Bank)

The `atlas` pipeline collects aligned stills into a block-packed RGBA16F ring grid: per captured still it packs columns for color, segmentation, depth, and encoded data from whatever passes are wired in. Key controls: `capture_now` (manual trigger), `capture_slot`, `interval_enabled` + `interval_frames` (self-timing cycle), `settle_frames` (pad so upstream settles before commit), `slot_count`, `fit_mode`. It reports `occupied_count`, per-slot `slot_sequences`, and `cycle_state`, and publishes a `Slot Occupancy` data pin that downstream modules consume.

The proven chain: StreamDiff (held, `render_one` per still) feeds matting `AlphaMatte` + depth `Raw` into the atlas; the `atlas_scene_spawner` module renders one depth-displaced textured card per occupied cell into a 3D scene. Use `hold` + `render_one` to fill cells one clean still at a time.

## Continuous Generative Atlas Fill (Live Scatter Scene Workflow)

The one-toggle recipe for filling an atlas with fresh generated cutouts every frame, proven by `projects/fruit_atlas_scatter/` (see its `DEBRIEF.md`):

1. **Chain**: StreamDiff -> matting (`outputMode=mask_only`) -> atlas `Pass 1`; StreamDiff -> depth (`outputMode=raw`) -> atlas `Pass 2`; StreamDiff -> atlas `Color`; atlas `Out` + `Slot Occupancy` -> a spawner module that cuts out cards by the segmentation column and places them by the depth column.
2. **Kill temporal smoothing first.** Depth `temporalSmoothing=0` and `adaptiveSmoothing=off`; matting `smoothingAlpha=1.0`. With any smoothing active, rapid capture blends previous frames' mattes and depths into every cell (ghost blobs).
3. **StreamDiff for independent stills**: `feedback=0` (at 1.0 each new generation inherits the previous composition), `frame_skip=1`, `hold=false` for free-running fill. A small guide module (shaded blob on black) on the video input at denoise 0.82-0.94 keeps subjects centered, whole, and in a chosen color family.
4. **Vary the subject per frame** with the prompt bank: one prompt per line, `prompt_bank_enabled=true`, and an expression sweeping `prompt_position` (for example an `lfo_panel` control output times the line count). Fractional positions generate embedding-blend hybrids. See `knowledge/streamdiff.md`.
5. **One toggle**: atlas `interval_enabled=true` with `interval_frames=1` and `settle_frames=0` captures every frame; all slots fill in about a second and keep refreshing. Toggle off to freeze the set. Do not step prompts over serial IPC writes while this runs — the slot ring wraps several times per second and only the last prompt survives; continuous cycling belongs in an expression.
6. **Curated mode** instead: `hold=true`, set the prompt or bank position, `render_one`, then the atlas `capture` action with an explicit `capture_slot` per cell.

Atlas geometry gotchas: `pass_count` counts ALL texture columns including color (color + matte + depth = 3), and changing `slot_count` / `pass_count` / tile size clears captured cell pixels — refill after any geometry change.

## Whole-Group Scene Presets And Nesting

Scene Groups snapshot everything inside them: a group preset auto-captures every parameter of every contained pipeline plus each node's bypass state, with no manual control exposure. Nested groups resolve membership innermost-wins, and an outer preset can recall each inner group's chosen preset then apply its own overrides (preset-of-presets). Recall rides the batch StateTree write, so presets restore parameters that expressions or OSC also touch.

Use group presets as the scene-state layer under live switching: preset recall sets the look, the mux or Conductor decides what is visible and when.

## Snapshot, Restore, Checkpoint

For agent workflows that mutate many parameters:

- `sentinel_state action=snapshot` and `action=restore`: capture and restore StateTree value sets around an experiment.
- `sentinel_capture action=checkpoint`: bundle a capture with the state snapshot so a look can be recovered exactly.
