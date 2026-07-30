# StreamDiff Workflow Studies

This collection packages six small StreamDiff graphs as focused technique examples. They are intentionally not full show scenes: there are no required Scene Groups, Group Outputs, or preset banks. Open one `.sentinel` file at a time, inspect the short graph, and change the highlighted parameters directly.

StreamDiff engine swaps are expensive. Close or replace the current project before opening another study instead of importing all six into one graph. On lower-VRAM systems, wait for the current StreamDiff engine to finish unloading before loading a study that uses a different resolution or engine tier.

## Studies

| File | Technique | Main controls | Required engines |
| --- | --- | --- | --- |
| `01_2d_feedback_zoom.sentinel` | Pure image-space feedback zoom with no depth or external guide | `zoom`, `feedback`, `denoise`, seed travel | SDXL 896x512 IP-Adapter tier, FP8 |
| `02_depth_parallax_zoom.sentinel` | The same feedback idea stabilized by auto-depth ControlNet and depth reprojection | `zoom`, `parallax_height`, `controlnet_scale`, `denoise` | SDXL ControlNet 896x512, FP16 |
| `03_backrooms_flythrough.sentinel` | A tuned environmental flythrough using stronger zoom, slower diffusion cadence, and liminal-space prompting | `zoom`, `frame_skip`, `cadence_fade_frames`, `denoise` | SDXL ControlNet 896x512, FP16 |
| `04_direct_variant_mux.sentinel` | Three independent StreamDiff variants feeding a regular input-mode Mux with `solo_upstream` | Mux `selected`, each variant's prompt and motion controls | SDXL 896x512 IP-Adapter tier, FP8 |
| `05_video_depth_control.sentinel` | A looping motion clip drives depth and person matte; the generated dancer is composited over the original footage | distance cutoff, matte refinement, `controlnet_scale`, `denoise` | Auxiliary depth + matting + SDXL ControlNet 512x896, FP16 |
| `06_procedural_warp_map.sentinel` | An authored RGB flow field driving StreamDiff's Warp Map input | flow mode/frequency/strength, `warp_scale`, `denoise` | SDXL ControlNet 896x512, FP16 |

The saved precision matches the engine packs used to author and prove each study. Use `sentinel_app action=engine_status` before loading a study on a fresh machine. The FP8 studies require Ada, Blackwell, or another supported FP8 GPU; on other hardware, install the corresponding FP16 896x512 pack and change **Engine Precision** before relaunching the node.

## 01 - 2D feedback zoom

This is the baseline. StreamDiff feeds its previous result back into the next diffusion step while `zoom=0.06` enlarges the feedback image. With depth, ControlNet, and warp disabled, every apparent push is a flat image transform.

Use it to learn the interaction between:

- `zoom`: geometric motion applied to the feedback image;
- `feedback`: how much of the previous frame survives;
- `denoise`: how strongly diffusion redraws the transformed frame;
- seed travel: how quickly new visual identity enters the loop.

The aggressive teeth prompt makes image-plane stretching easy to see. Replace the prompt without changing the graph.

## 02 - depth-parallax zoom

This study keeps the feedback loop but enables integrated depth estimation, depth reprojection, and auto-depth ControlNet. The prior generated frame supplies its own structural guide, so near and far regions move differently and the model is encouraged to preserve the projected layout.

Compare it directly with study 01. The important change is not simply a different prompt or a larger zoom: `depth_parallax`, `parallax_height`, `controlnet_enabled`, and `controlnet_auto_depth` form a closed temporal structure loop.

`frame_skip=3` leaves two interpolation frames between diffusion updates. `cadence_fade_frames=2` softens those update boundaries.

## 03 - backrooms flythrough

This is a subject-specific tuning of the depth-parallax pattern for long corridors and rooms. It uses a stronger zoom (`0.08`), high denoise, six-frame diffusion cadence, and five-frame cadence fades. Those values trade fine temporal detail for a more forceful, readable advance through architecture.

The lesson is that a reusable motion architecture still needs content-aware tuning. Corridors tolerate slower semantic updates because the large vanishing-point structure carries motion between diffusion frames.

## 04 - direct variant Mux

Three StreamDiff nodes feed Mux inputs 0-2:

```text
Teeth Zoom -------\
Dog Zoom ----------> Direct Variant Mux
Squirrel Pullback -/
```

The Mux uses normal input mode (`source_mode=Inputs`) and `solo_upstream=true`. Selecting an input automatically holds the two hidden StreamDiff nodes, so only the visible variant spends diffusion time. The three variants deliberately use different prompts, denoise values, cadence, and positive/negative zoom.

This is not the final Scene Group switching reference. It teaches the lightweight case where several variants are already individual texture-producing nodes. The separate Scene Group example should use one Group Output per complete look and a groups-mode Mux to switch whole shader chains wirelessly.

## 05 - video depth control

The included `assets/dancer_vert.mp4` is the 24.76-second, 512x896 dancer source used to author
this study. The final reviewed Downloads copy was byte-for-byte identical to this tracked file.
The saved graph uses the relative asset path, so it opens with the intended motion guide on another
machine.

```text
Dancer -> Video Depth Guide -> Depth Threshold -> Marble Dancer Control Image
   |                                              |
   +-> Background Removal -> Original Matte      +-> Generated Image
   |                                              |
   +-----------------> Original Footage ----------+-> Generated Over Original
```

Depth Estimation converts motion into a temporally smoothed grayscale structure map. Depth
Threshold removes darker distant values while preserving the retained depth map, and StreamDiff
uses that result as its depth Control Image. The same original clip feeds Background Removal; its
person matte masks the generated StreamDiff image, and the final Module composites that generated
subject over the untouched source footage.

The final compositor exposes `Generated Foreground`, `Edge Grow / Shrink`, `Edge Feather`, and
`Edge Contrast`. These refine the original-video matte without changing the generated image.

For a new clip:

1. Select the source node and choose a portrait video.
2. Confirm Depth Estimation is producing a stable grayscale preview.
3. Keep StreamDiff at the matching 512x896 engine resolution.
4. Tune `controlnet_scale` first, then `denoise`; excessive values can lock the output to noisy depth edges.

## 06 - procedural warp map

`Procedural Flow Map` is a bundled Module that encodes signed XY displacement around neutral gray:

- red: horizontal flow, centered at `0.5`;
- green: vertical flow, centered at `0.5`;
- blue: optional magnitude or interference texture;
- alpha: opaque.

Its three geometric layers can generate rings, waves, spirals, flowers, lattices, polygons, ripples, pinwheels, curl noise, fractal rings, or cells. The saved study uses one restrained ring layer so the source of the motion is readable. StreamDiff consumes the result through its Warp Map pin with `warp_enabled=true`.

The Module and its shared timeline include are bundled under `modules/`; the project contains no absolute author-machine paths.

## Runtime checks

After a study settles, inspect its final pipeline and require:

- `stats.healthy=true`;
- `framesProcessed` increasing;
- `stats.has_preview_srv=true`;
- a nonblank output capture;
- no unresolved project directory on load.

For study 04, the Mux output should advance while only the selected StreamDiff variant continues diffusing. For study 05, both the source and Depth Estimation previews must move. For study 06, `Procedural Flow Map` must compile before StreamDiff can consume its Warp Map.

## Why these are a collection instead of one project

Loading every StreamDiff configuration simultaneously would obscure the lessons and can create large engine-memory spikes, especially when switching between 896x512 and 512x896 ControlNet profiles. Small projects make the exact parameter bundle visible and keep each experiment cheap to open, copy, and modify.
