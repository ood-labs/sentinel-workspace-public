# StreamDiff

Pipeline type: `streamdiff`

StreamDiff is Sentinel's real-time image generation pipeline. It uses TensorRT engine packs and runs best on high-end NVIDIA RTX GPUs.

## First Use

StreamDiff needs large engine packs. On a fresh install:

1. Use `sentinel_app action=engine_status` to see `gpu_arch` and missing packs.
2. Install the required StreamDiff pack for the host GPU using `download_pack` or `install_pack`.
3. Poll `engine_status` until the relevant packs are `complete`.
4. Create the `streamdiff` pipeline and inspect it with `sentinel_pipeline info`.

For a small first-run engine test, `depthestimation` with pack `auxiliary` is faster than StreamDiff.

## Engine Families

StreamDiff packs include:

- shared SDXL core engines;
- resolution-specific IP-Adapter UNet engines;
- optional ControlNet + IP-Adapter engines;
- optional FP8 engines on supported Ada or Blackwell GPUs.

Use the engine dropdown in the UI or inspect parameters through MCP to select available profiles. Download size can be several GB.

## Inputs And Outputs

Slot 0 is the main generated output. Some configurations expose additional outputs such as depth. Use `sentinel_pipeline info` to inspect available output slots.

StreamDiff is heavy. A healthy node can still take several seconds to load engines or reinitialize after engine/profile changes.

## Hold And Render One

`hold` is a persistent bool parameter that keeps the node live while suppressing new diffusion. Use it to freeze a generated still without bypassing the whole node.

`render_count` is a persistent int, default 1. `render_one` is a momentary button/action at `/sentinel/pipelines/<id>/actions/render_one` and `/sentinel/pipelines/<id>/parameters/render_one`; it queues `render_count` diffusion frames, then returns to hold.

## Atlas Still Capture Tuning

For atlas still capture and single-image generation, use a separate tuning bundle from the smooth live-video defaults:

| Parameter | Value |
|-----------|-------|
| `seed_travel_enabled` | `false` |
| `seed_locked` | `false` |
| `frame_skip` | `1` |
| `denoise` | `0.972` |
| `feedback` | `1.0` |
| `ipadapter_enable` | `false` |
| `zoom` | `0.0` |
| `image_noise_strength` | `0.0` |
| `sharpen` | `0.0` |
| `render_count` | `1` |

This was captured from the live `Atlas Still Capture` preset on 2026-07-05. Treat prompt text as user content, not as part of the generic atlas default. An atlas capture controller should apply this behavior bundle, set `hold=true` while it owns capture, and invoke `render_one` once per cell.

## Good Automation Checks

After creating or changing StreamDiff, verify:

- `stats.healthy` is true;
- `stats.statusMessage` says ready or equivalent;
- `framesProcessed` climbs;
- the node has a preview SRV;
- captures are nonblank.

Do not treat a successful create call as proof that engines loaded.

## Hold And Single-Frame Render

- `hold` (bool parameter): freezes diffusion while the node stays live. Input mapping, pre-image processors, and control/style inputs keep flowing; the last generated frame republishes. Finer than the `/enabled` bypass, which stops the node cooking entirely.
- `render_one` (momentary action at `/sentinel/pipelines/<id>/actions/render_one`): fires exactly `render_count` diffusions then re-holds.
- `render_count` (int, default 1): render-N-then-hold.

All three are StateTree parameters, so OSC, expressions, MCP, and scene-group presets reach them. Use hold plus `render_one` for one-clean-still-at-a-time workflows such as filling an `atlas` node.

## Multiple Variants, Shared Engines, Mux

Several StreamDiff variants using the same engine files share loaded TensorRT engines through a ref-counted pool, so N variants cost one engine load (execution is one at a time). Switch between variants live with a `mux` node (`selected` picks 1-of-8 inputs); enable the mux's `solo_upstream` so the non-selected variants auto-hold and only the visible one diffuses. See `knowledge/scene-system.md`.
