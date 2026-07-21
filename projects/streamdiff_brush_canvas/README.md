# StreamDiff Brush Canvas

An interactive Sentinel graph that turns StreamDiff into a live paint source.

## Graph

`Shape Maker -> Collage Diffusion -> Collage Cutout -> Paint Canvas -> Collage Output`

- **Shape Maker** produces a matched monochrome 640x640 Video Guide and Depth Guide with six shape types, four fill modes, and direct preview positioning.
- **Paint Canvas** stamps the generated color through the Matting cutout into a persistent 1080x1350 canvas.
- **Collage Output** publishes the clean canvas, not the authored viewport chrome.

The five nodes live inside the `STREAMDIFF BRUSH CANVAS` Scene Group.

## Shape Maker controls

- Drag anywhere in the preview to position the shape.
- Choose Round, Rounded Box, Capsule, Triangle, Star, or Blob.
- Character A and B expose the most useful shape-specific variation.
- Fill modes are Solid, Radiating Rings, Scrolling Stripes, and Scrolling Checker.
- Pattern scale, angle, and bidirectional motion control the animated fills.
- Edge softness, depth shape, and depth strength tune the paired conditioning outputs.

## Paint Canvas controls

- Left click: stamp the current generated subject.
- Left drag: paint evolving generated dabs.
- Middle drag: pan the artboard.
- Mouse wheel: pointer-anchored zoom.
- Alt + mouse wheel: change the effective brush size.
- `F`: fit/reset the artboard view.
- `X` or the top-right **Clear** button: clear the canvas.
- Brush size, aspect, opacity, rotation, spacing, feather, stroke alignment, subject anchor, and ground color are available in Properties.

The viewport follows the panel size without stretching. The persistent poster storage and clean output remain fixed at 1080x1350. `subject_anchor` is expression-driven from Shape Maker's position so the visible conditioned subject lands under the pointer.
