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

## Prompt Bank (Multi-Prompt By Line)

The prompt box doubles as a prompt bank for rapid prompt cycling and blending:

- `prompt_bank_enabled` (bool): treat each LINE of the prompt as a separate prompt. The Properties panel switches to numbered per-line rows with add/remove buttons; the active row is highlighted.
- `prompt_position` (float 0-63): the whole part selects a line (wrapping past the last), the fractional part BLENDS the CLIP embeddings toward the next line. `3.0` is exactly line 3; `4.5` is a semantic halfway point between lines 4 and 5 (blends generate coherent hybrids, not double exposures).

Every line is encoded once when the bank is enabled or edited, and the embeddings are cached on the GPU. Position changes cost no text-encoder work, so `prompt_position` can change every frame. It is a normal float parameter: drive it from an expression (for example `ref("<lfo_module>/control_outputs/lfo1") * <line_count>`), OSC, or Conductor cues to cycle prompts continuously. Combined with atlas `interval_enabled`, a swept position fills an atlas with a different subject per captured frame.

Editing the bank re-encodes all lines (roughly tens of ms per line, once per edit). Disabling the toggle returns to whole-text prompting.

## Multiple Variants, Shared Engines, Mux

Several StreamDiff variants using the same engine files share loaded TensorRT engines through a ref-counted pool, so N variants cost one engine load (execution is one at a time). Switch between variants live with a `mux` node (`selected` picks 1-of-8 inputs); enable the mux's `solo_upstream` so the non-selected variants auto-hold and only the visible one diffuses. See `knowledge/scene-system.md`.
