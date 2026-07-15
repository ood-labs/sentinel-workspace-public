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

## Requirements

- StreamDiff engine pack compatible with the installed GPU.
- MediaPipe face tracking support.
- Sentinel 0.5.33 or newer.

All referenced Module folders are bundled under `modules/`. The final composition remains portrait-oriented at 720 × 1280.

## Troubleshooting

- If tracking or cutouts are empty, confirm the MediaPipe node has a live camera/video input and that one face is clearly visible. Inspect its health and face-record count before changing the authored Modules.
- If StreamDiff reports a missing or incompatible engine, open Sentinel's engine status and install the registered StreamDiff pack for this GPU architecture. The node should report the missing pack explicitly; downstream nodes may hold or show black, but the project should remain responsive.
- If the final output is black with both inputs ready, inspect `Face_Cutout`, `Accum`, and `Overlay_Comp` in that order, then confirm `Face Collage Group Output` is enabled. No extra Spout/output node is required.

## Proof

The compact runtime proof is in `proof/`, including the final capture, graph, links, profile, pipeline health, and active-expression report.
