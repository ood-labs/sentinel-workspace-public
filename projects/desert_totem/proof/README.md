# Desert Totem proof

Proof captured on 2026-07-15 from the live Sentinel project.

- `01-monument.png`, `02-dali-melt.png`, `03-cubist-glitch.png`, `04-painterly.png`, `05-fidelity.png`, and `06-performance.png` show six bounded and visibly distinct whole-group looks.
- `camera-hero.png`, `camera-detail.png`, `camera-orbit.png`, and `camera-silhouette.png` show four distinct wireless Camera Switcher framings.
- `warp-deck.png` shows the responsive ochre/black full-bleed Canvas at 960x540; its normal closed backing size is 480x270 and the panel uses `follow_panel`.
- `assembly-editor.png` shows the four selectable logical assemblies and the selected-assembly outline.
- `hero.png` is the final settled Monument output.

Runtime assertions recorded during capture:

- The editor published four selectable descriptors with stable ids 1-4 and capability flags for move, rotate, and scale.
- A real synthetic pick selected Base. Real begin/preview/commit transactions produced a Base offset, Crown rotation, and Mid Shelf scale while every child primitive moved coherently.
- GPU readback proved `Monument Baseline` at zero offset/rotation and scale 1.0 for all four records. `Asymmetric Study` recalled the edited 128-byte durable state with no skipped fields.
- Stale viewport events are deduplicated, and reset clears both the transform buffer and pending edit command; repeated post-reset readbacks remained stable.
- All six Scene Group presets applied 215 member parameters, eight exposed controls, and twelve bypass flags with no nested group state. Automated sequential recall of all six completed without a crash or TDR and every inspected output remained healthy.
- The Performance preset uses 608x912, an 80-unit march distance, disabled shadows, and 24 accent records. Fidelity uses 760x1140, a 120-unit march distance, shadows, and 72 accent records.
- The live graph ran around 60 FPS during the bounded preset audit. The lightweight profiler occasionally attributed the frame's GPU synchronization wait to the Canvas node; every node remained healthy and frames continued increasing.
- All six authored Module directories passed Sentinel's real offline `compile_check` with zero lints.
- A cache-free project reload resolved all six relative module paths, cold-compiled the renderer without timeout, and restored the healthy 760x1140 final output.
- Final structure: six authored Modules, four Camera nodes, one Camera Switcher, one Group Output, one flat Scene Group, zero child groups, eight exposed controls, six group presets, and five project-scoped node presets.

No engine packs are required.
