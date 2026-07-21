# StreamDiff Brush Canvas

An interactive Sentinel graph that turns StreamDiff into a live paint source.

## Graph

`Shape Maker -> Collage Diffusion -> Collage Cutout -> Paint Canvas -> Collage Output`

The generated subject and cutout also feed a parallel data-driven branch:

`Pattern Canvas -- video + Spawn Points --> Pattern Tracer`

- **Shape Maker** produces a matched monochrome 640x640 Video Guide and Depth Guide with six shape types, four fill modes, and direct preview positioning.
- **Paint Canvas** stamps the generated color through the Matting cutout into a persistent 1080x1350 canvas.
- **Pattern Canvas** automatically stamps the same live subject into a separate persistent 1080x1350 canvas using Random, Grid, Spiral, Wave, or Border placement.
- **Pattern Tracer** overlays an adjustable spline through the Pattern Canvas spawn history.
- **Collage Output** publishes the clean manual canvas, not the authored viewport chrome.

The graph lives inside the `STREAMDIFF BRUSH CANVAS` Scene Group.

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

## Pattern Canvas controls

- **Run** starts or pauses timed stamping; **Seconds Per Stamp** controls cadence.
- **Clear Canvas** is a one-shot toggle: every click clears once, whether the checkbox turns on or off.
- **Feedback** transforms the accumulated canvas continuously between stamps.
- **Zoom Speed**, **Rotation Speed**, and the **Drift** XY pad create fly-through, spiral, and lateral motion.
- Left-drag directly steers Drift using relative pointer movement; each mouse-wheel notch moves Zoom Speed by 2% of its full control range.
- **Control Gain** multiplies both Drift and Zoom response and defaults to 5x.
- Hold Alt for fine drag/wheel adjustment or Alt+Shift for ultra-fine adjustment. Double-click resets Drift and Zoom Speed.
- **Pivot** chooses the transform center; **Trail Fade** dissolves older imagery toward the canvas background.
- **Edges** chooses Background, Clamp, Repeat, or Mirror behavior when transformed pixels move beyond the canvas.
- **Pattern** selects Random, Grid, Spiral, Wave, or Border placement.
- **Spawn Points** publishes the latest 64 stamp centers as normalized, chronological structured records. Clear Canvas clears this history, and feedback transforms keep the points registered to the accumulated image.
- **Pattern Tracer** consumes Pattern Canvas plus Spawn Points and draws a Strata-style open Catmull-Rom thread over the recent spawn path. Trace Length and Trace Offset trim the visible portion of the path.
- Pattern Count, Phase, Seed, Position Jitter, and Follow Pattern shape the layout.
- Scale, Scale Variation, Rotation, Rotation Jitter, Opacity, matte controls, shadow, and background color tune the stamps.

Pattern Canvas is intentionally a parallel test branch. It does not replace or alter the interactive Paint Canvas -> Collage Output path.
