# Scientific UI helpers

`scientific_ui.hlsli` is a small shader-native UI kit for authored Module viewports. It uses the shipped Scientifica bitmap glyph data and keeps structural chrome independent from rollover state. A Module can opt into one control's pressed bit when it needs local momentary feedback, while host hit testing stays aligned without native UI code.

Included primitives:

- shared scientific dark palette, axis colors, panels, grids, lines, rings, and rounded boxes;
- Scientifica glyph and integer rendering;
- static framed buttons, value-aware sliders and toggles, XY pads, and an explicit pressed-button helper;
- helpers that render at a fixed design resolution while the Module output scales normally.

To use it from a sibling Module project:

```hlsl
#include "../_shared/ui/scientific_ui.hlsli"
```

Declare the matching controls under `viewport.controls` in the Module manifest. The rectangle in the manifest is normalized viewport space; the HLSL helper rectangle is in the renderer's design-space pixels.

The kit deliberately has no application-side dependency. It is reusable authored HLSL, not a Sentinel feature or native widget library.

On Sentinel 0.5.32 or newer, a standalone authored interface can occupy the complete pipeline panel and render at the live panel extent:

```yaml
panel:
  mode: canvas
  output: UI
  resolution: follow_panel
```

Canvas retains the dock tab but removes host chrome below it. The shared template uses this contract by default; remove the `panel` block when targeting an older build or a standard preview window.
