# StreamDiff Brush Canvas

An interactive Sentinel graph that turns StreamDiff into a live paint source.

## Graph

`Shape Maker -> Collage Diffusion -> Collage Cutout -> Paint Canvas -> Collage Output`

The generated subject and cutout also feed a parallel data-driven branch:

`Pattern Canvas -- video + Spawn Points --> Pattern Tracer`

- **Shape Maker** produces a matched monochrome 640x640 Video Guide and Depth Guide with six shape types, four fill modes, and direct preview positioning.
- **Paint Canvas** stamps generated color, matte, and live subject depth into registered persistent 1080x1350 color/depth/mask canvases.
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
- Hold `K` for the Paint Canvas feedback kick. **K Kick** multiplies the ongoing zoom, rotation, and drift, while **Kick Zoom** adds an independent zoom pulse even when Zoom Speed is zero. Attack, Decay, Sustain, and Release shape the envelope.
- Brush size, aspect, opacity, rotation, spacing, feather, stroke alignment, subject anchor, and ground color are available in Properties.
- **Feedback** applies one shared zoom, rotation, drift, pivot, edge, and fade transform to color, depth, and mask so the relief stays registered while flying in or out.
- **Audio Kick** gates the same envelope from the driven kick level; this project binds it to `Audio_Bands/control_outputs/kick`.
- **Source Depth Mix**, **Solid Depth**, **Depth Gain**, and **Depth Offset** shape each painted relief stamp.
- **Depth Blend: Over** follows paint opacity and stays responsive on overlapping strokes. **Max** only raises the existing relief; **Add** builds height cumulatively.
- Paint Canvas publishes **Canvas**, **Depth**, and **Mask** outputs directly to **Pattern Depth SDF**. This manual relief branch does not require detections.

The viewport follows the panel size without stretching. The persistent poster storage and clean output remain fixed at 1080x1350. `subject_anchor` is expression-driven from Shape Maker's position so the visible conditioned subject lands under the pointer.

## Pattern Canvas controls

- **Run** starts or pauses timed stamping; **Seconds Per Stamp** controls cadence.
- **Run Trigger** replaces the Run toggle with a held-key gate: focus the Pattern Canvas and hold `X` to spawn at the current Seconds Per Stamp cadence; release `X` to stop immediately.
- **Clear Canvas** is a one-shot toggle: every click clears once, whether the checkbox turns on or off.
- **Feedback** transforms the accumulated canvas continuously between stamps.
- **Zoom Speed**, **Rotation Speed**, and the **Drift** XY pad create fly-through, spiral, and lateral motion.
- Left-drag directly steers Drift using relative pointer movement; each mouse-wheel notch moves Zoom Speed by 2% of its full control range.
- **Control Gain** multiplies both Drift and Zoom response and defaults to 5x.
- Hold `X` for the feedback kick/zoom. **X Kick** controls the multiplier, while Kick Attack, Decay, Sustain, and Release shape its ADSR envelope. Drift, Zoom, Rotation, and the published Spawn Points all consume the same envelope, so the tracer remains registered to the transformed canvas through the kick and release tail.
- Hold `Z` to release StreamDiff hold and spawn immediately, then continue spawning at **Seconds Per Stamp** until release. Press `C` to toggle persistent auto-run on or off. With **Sync StreamDiff** enabled, auto-run also publishes a one-frame `diffusion_pulse` every **Diffusion Every N Stamps**.
- `Film Grade Post` sits after `Pattern Spatial SDF` as a separate filter with filmic tone, organic per-frame grain, broad lens dirt, chromatic aberration, edge resolve, quarter-resolution separable Gaussian glow, and a separately softened anamorphic flare convolution. Grain Size reaches 20, and the frame counter reseeds the grain every cooked frame instead of translating it.
- Hold Alt for fine drag/wheel adjustment or Alt+Shift for ultra-fine adjustment. Double-click resets Drift and Zoom Speed.
- **Pivot** chooses the transform center; **Trail Fade** dissolves older imagery toward the canvas background.
- **Edges** chooses Background, Clamp, Repeat, or Mirror behavior when transformed pixels move beyond the canvas.
- **Pattern** selects Random, Grid, Spiral, Wave, or Border placement.
- **Three-Frame Reveal** optionally freezes each incoming subject and layers a black outer ring, white inset, then final color across three frames; **Reveal Border** controls the spacing. When disabled, stamping uses the original single-frame cadence with no reveal staging.
- **Spawn Points** publishes the latest 64 stamp centers as normalized, chronological structured records. Clear Canvas clears this history, and feedback transforms keep the points registered to the accumulated image.
- **Pattern Tracer** consumes Pattern Canvas plus Spawn Points. Spline preserves the original Strata-style chronological Catmull-Rom thread; Chain, Loop, Proximity, Nearest, and Cage provide alternate connection topologies.
- **Link Distance** controls the Proximity web and **Links Per Point** controls Cage density. Trace Length and Trace Offset retain the original path-trimming behavior.
- **Main Point Dots** can draw Solid, Ring, or Ring + Dot anchors independently of the trace window, with separate size, color, and opacity controls.
- Pattern Tracer's **Displacement** group warps the underlying canvas outward from the visible line. Amount and Radius set the field, Ripple and Bands shape the radiating waves, and Phase/Speed provide scrubbed or continuous motion.
- Pattern Count, Phase, Seed, Position Jitter, and Follow Pattern shape the layout.
- Scale, Scale Variation, Rotation, Rotation Jitter, Opacity, matte controls, shadow, and background color tune the stamps.

Pattern Canvas remains a parallel procedural test branch. The interactive Paint Canvas still feeds Collage Output, and now also drives Pattern Depth SDF with its registered color/depth/mask outputs.
