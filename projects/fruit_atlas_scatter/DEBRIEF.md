# Fruit Atlas Scatter — build debrief

A generative 3D scatter scene built end to end from live StreamDiff output: fruit stills are generated on a black background, cut out with Background Removal, depth-mapped, banked into a 9-slot atlas (color + matte + depth columns), and spawned as depth-scaled cutout cards scattered in a 3D scene with orbit parallax. One toggle refills the whole scene with fresh, varied fruit in about a second.

## Graph

```
Fruit_Guide (module) ──▶ Fruit_SD (streamdiff) ──▶ Fruit_Matte (matting, mask_only) ──▶ Fruit_Atlas [Pass 1]
Fruit_LFO (module)  ─exprs─▶ Fruit_SD.prompt_position    └──▶ Fruit_Depth (depth, raw) ──▶ Fruit_Atlas [Pass 2]
                                                          └────────────────────────────▶ Fruit_Atlas [Color]
Fruit_Atlas ── Out ──────────────▶ Fruit_Scene (module) ──▶ output
            └─ Slot Occupancy ───▶ Fruit_Scene
```

- **Fruit_Guide**: a shaded ellipse blob (center / radius / squash / color params) fed into StreamDiff's video input. At denoise 0.82-0.94 the blob steers where the fruit lands, how big it is, and its color family. StreamDiff with no input free-runs on noise, which loses framing control; a soft structural guide is the difference between centered whole fruit and cropped edge-of-frame fruit.
- **Fruit_Scene**: derived from `atlas_scene_spawner`, replaces the grid layout with deterministic per-slot hash scatter (`spread_x/y`, `scatter_seed`), keeps depth-driven scale + Z + `orbit` parallax and segmentation cutout, adds `phase`/`bob_amount` for motion. Card aspect corrects for the non-square NDC of the 1280x720 output.
- **Fruit_LFO**: stock `lfo_panel`; its `lfo1` control output drives `prompt_position` through the expression `ref("Fruit_LFO/control_outputs/lfo1") * 6`, sweeping the prompt bank continuously.

## The one-toggle fill

With StreamDiff free-running (`hold=false`, `frame_skip=1`) and the LFO sweeping `prompt_position`, enabling atlas `interval_enabled` (with `interval_frames=1`, `settle_frames=0`) captures a fresh still every frame — the 9 slots fill and keep refreshing with different fruits, including embedding-blend hybrids at fractional positions. Toggle `interval_enabled` off to freeze the set.

## Settings that make or break it

- **Matting**: `outputMode = mask_only` (the spawner samples RGB luminance of the segmentation column; `alpha_matte` carries the matte in the alpha channel where it can't see it) and `smoothingAlpha = 1.0` (full EMA disable; anything lower ghosts previous fruits into the mattes during rapid capture).
- **Depth**: `outputMode = raw`, `temporalSmoothing = 0`, `adaptiveSmoothing = off` — same rapid-capture ghosting reason.
- **StreamDiff**: `feedback = 0` for independent stills (at `feedback = 1.0` every new still inherits the previous one's composition), `prompt_bank_enabled = true` with one fruit prompt per line, cycled by `prompt_position`.
- **Atlas**: `pass_count = 3` counts ALL texture columns including color (color + matte + depth). Geometry changes (`slot_count`, `pass_count`, tile size) clear captured cell pixels — refill after changing them.

## Curated-still mode

For hand-picked cells instead of the live fill: set `hold=true` on StreamDiff, set a prompt (or a bank position), fire `render_one`, then the atlas `capture` action with an explicit `capture_slot`. Each cell gets exactly the still you approved.
