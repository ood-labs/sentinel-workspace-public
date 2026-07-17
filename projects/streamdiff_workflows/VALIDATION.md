# Validation record

Validated against Sentinel 0.5.38 on 2026-07-17. Captures were kept in ignored local scratch storage so the technique collection remains lightweight.

## Static and portability

- All six `.sentinel` files parse as JSON.
- Every graph link resolves to existing pins and every saved input references an existing pipeline or source.
- Saved dock layouts are empty; no unrelated historical windows are restored.
- No project, module, media, or text file contains an absolute author-machine path.
- The bundled flow-map Module resolves through `modules/Expressive_Flow_Layers`.
- `assets/motion_guide.mp4` is H.264, 512x896, 25 fps, six seconds, and 24,054 bytes.

## Module compile

`modules/Expressive_Flow_Layers` passed Sentinel `compile_check`:

- manifest: valid;
- passes: 1/1;
- parameters: 53;
- lints: none.

## Runtime

| Study | Result |
| --- | --- |
| 01 - 2D Feedback Zoom | Healthy FP8 896x512 engine, live preview, 33+ frames, successful output capture |
| 02 - Depth-Parallax Zoom | Healthy FP16 ControlNet 896x512 engine, live preview, successful output capture |
| 03 - Backrooms Flythrough | Healthy FP16 ControlNet 896x512 engine, live preview, six-frame cadence active, successful output capture |
| 04 - Direct Variant Mux | Healthy Mux; selecting input 1 disabled input 0, enabled only input 1, and left input 2 frozen; successful Mux capture |
| 05 - Video Depth Control | Fresh-process cold load passed: source connected at 512x896/25 fps, depth healthy, StreamDiff healthy at about 26.7 fps, successful output capture |
| 06 - Procedural Warp Map | Relative Module resolved, compile state `ok`, Module and StreamDiff healthy, successful output capture |

## Known application crash

Switching directly from a healthy 896x512 ControlNet project to the 512x896 Video Depth Control project crashed/restarted Sentinel twice. Loading Video Depth Control first in the fresh restarted process succeeded, isolating the failure to the cross-profile transition rather than the saved project or media asset.

The crash was submitted as [Sentinel bug #59](https://github.com/ood-labs/sentinel-bugs/issues/59).
