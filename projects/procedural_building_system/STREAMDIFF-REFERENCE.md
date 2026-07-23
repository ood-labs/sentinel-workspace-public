# Procedural Building StreamDiff Reference

This project preserves a useful real-time architectural relight experiment. The
procedural renderer is the primary validated output; StreamDiff remains an
optional downstream interpretation layer whose settings are worth retaining for
future systems.

## Wiring

- `05_Architectural_Renderer / sRGB Building` -> `06_Detail_and_Relight / Video Input`
- `05_Architectural_Renderer / sRGB Building` -> `06_Detail_and_Relight / Style Reference`
- `05_Architectural_Renderer / Native Depth` -> `06_Detail_and_Relight / Control Image`

Do not feed the color output into Control Image. The renderer tone-maps its
linear HDR working pass and publishes an 8-bit sRGB color texture for ordinary
video consumers. Its separate 8-bit inverse-depth output shares the exact camera
and geometry with the color render and is the structural guide.

## Proven Settings

- Engine: `sdxl/896x512`, ControlNet + IP-Adapter tier, FP16
- Processing: `896 x 512`
- ControlNet enabled: `true`
- ControlNet type: `depth` (`1`)
- ControlNet scale: `0.7`
- ControlNet auto depth: `false`
- Denoise: `0.897`
- IP-Adapter enabled: `false` in the saved example
- IP-Adapter scale: `0.543` retained as a useful reference value when enabled
- IP-Adapter update interval: `30`
- Prompt weight: `0.9`
- Color match enabled: `true`, MKL, strength `0.55`
- Sharpen: `0.3`, radius `1.0`
- Feedback: `0.0`
- Hold: `false`
- Frame skip: `1`
- Seed: `42`, locked
- Steps: `1`
- VSR enabled: `true`, quality `3`

## What this proved

- Display-referred color must be 8-bit sRGB before entering Video Input or Style Reference. Feeding the linear HDR working pass produces the wrong contrast and color response.
- Control Image must receive native renderer depth, not another copy of color. Disable automatic depth so the exact procedural camera and geometry drive ControlNet.
- `hold: false` and `frame_skip: 1` preserve the intended real-time feedback while the camera moves.
- The saved balance permits substantial material reinterpretation, so it is a creative branch rather than a geometry-authoritative final renderer.

See `proof/streamdiff-reference.png` for the saved branch and
`proof/renderer-srgb.png` for the primary deterministic output.
