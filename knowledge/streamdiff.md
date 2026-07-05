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
