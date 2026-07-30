# Face Collage

Face Collage turns a generated portrait into a moving editorial composition. A procedural face guide seeds StreamDiff, MediaPipe supplies facial landmarks, and the Module chain cuts, repeats, accumulates, and connects facial details before a restrained post pass.

## Open and play

1. Open `face_collage.sentinel`.
2. Select the `FACE COLLAGE // EDITORIAL PORTRAIT` Scene Group.
3. Start with the `Editorial Drift` group preset.
4. Adjust the six exposed controls: clone count, stamp scale, motion mode, temporal history, fresh-layer mix, and micro glitch.

The other group presets are:

- `Performance` — fewer clones and minimal post processing.
- `Temporal Echo` — delayed source history and longer accumulation.
- `Dense Study` — a denser, more graphic composition.

The Scene Group contains exactly one Group Output, which is the sole final endpoint for wireless Scene Switcher collection.

## Prompt LFO panel

`Prompt_LFO` drives StreamDiff's prompt-bank position through one visible
expression. Open the node to see a full-bleed oscilloscope Canvas with the
selected waveform, completed and upcoming phase, quarter-cycle guides, a live
phase cursor, and the current value point.

The Canvas uses `follow_panel`, so its real render target tracks the dock
content size instead of stretching the default 320 x 96 texture. Stroke and
marker weights scale within a restrained pixel range as the panel grows. Exact
waveform, rate, range, and phase controls remain in Properties; the Canvas is a
responsive visualization rather than a duplicate control surface.

## Requirements

- StreamDiff engine pack compatible with the installed GPU.
- MediaPipe face tracking support.
- Sentinel 0.5.33 or newer.

All referenced Module folders are bundled under `modules/`. The final composition remains portrait-oriented at 720 × 1280.

## Troubleshooting

- If tracking or cutouts are empty, confirm the MediaPipe node has a live camera/video input and that one face is clearly visible. Inspect its health and face-record count before changing the authored Modules.
- If StreamDiff reports a missing or incompatible engine, open Sentinel's engine status and install the registered StreamDiff pack for this GPU architecture. The node should report the missing pack explicitly; downstream nodes may hold or show black, but the project should remain responsive.
- If the final output is black with both inputs ready, inspect `Face_Cutout`, `Accum`, and `Overlay_Comp` in that order, then confirm `Face Collage Group Output` is enabled. No extra Spout/output node is required.

## Runtime proof

Capture the Group Output and inspect graph health, links, profile, and active
expressions in the running build. Generated proof media is intentionally not
distributed with the project.

## Component map

There is no bundled media file; provide a meaningful live camera or video input
to the face-analysis route.

| Component | Type | Receives | Publishes or contributes |
| --- | --- | --- | --- |
| `Face_Guide` | Module | authored parameters | initial face guide image |
| `SD_Face` | StreamDiff | `Face_Guide` | photographic generated face |
| `Face_DS` | Module | `SD_Face` | analysis-sized face texture |
| `Face_Track` | MediaPipe | `Face_DS` | face landmarks and tracking records |
| `Face_Stitch` | Module | face image and tracking records | aligned stitch/control image |
| `Face_Cutout` | Module | `Face_DS` and `Face_Stitch` | isolated face layer |
| `Accum` | Module | `Face_Cutout` | persistent collage history |
| `Clone_Overlay` | Module | `Face_Cutout` | current clone/guide overlay |
| `Overlay_Comp` | Module | accumulation, cutout, and overlay | assembled collage |
| `Editorial_Post` | Module | `Overlay_Comp` | final editorial treatment |
| `Prompt_LFO` | Module | time and authored controls | prompt/modulation control outputs |
| `Face_Collage_Group_Output` | Group Output | `Editorial_Post` | reviewed Scene Group texture |

StreamDiff needs a compatible generation pack. MediaPipe itself does not.
Study the separation between tracking, isolation, accumulation, and editorial
composition; invent a new visual system for new source material.
