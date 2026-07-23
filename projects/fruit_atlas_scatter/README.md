# Fruit Transit Chamber

Fruit Transit Chamber is a live generative instrument built from StreamDiff, Background Removal, Depth Estimation, Atlas, and authored Modules. A continuously refreshed 24-slot bank becomes a swarm of roughly 70 depth-aware fruit particles flying through a monochrome tunnel.

## What to open

Open `fruit_atlas_scatter.sentinel`. The complete graph lives in one flat `FRUIT TRANSIT CHAMBER` Scene Group; there are no nested groups and `Fruit_Group_Output` is the sole final endpoint.

The default **Live Fill** preset is intentionally active: Atlas interval capture stays enabled and commits a fresh generated fruit every 120 frames. New identities replace old slots while the renderer keeps the swarm in motion.

## Main controls

- **Motion World**: `Flythrough` is the hero tunnel, `Fruitfall` drops and bounces fruit onto a floor, and `Orbit` forms a slower gallery ring.
- **Camera**: `Fruit_Scene` uses its built-in camera; keep **Camera Ref** empty and tune the camera controls directly on the renderer.
- **Swarm Clones**: renders 1–4 visual particles per occupied Atlas identity. The default is 3.
- **Fruit Scale** and **Lifecycle Rate**: control visual density and forward speed.
- **Interval Enabled** and **Capture Slot**: switch between continuous replacement and deliberate slot curation.
- **Card Tool**: choose Move, Rotate, or Scale for a selected Atlas identity.

`Fruit_LFO` is the authored **Fruit Motion Console**. It is a responsive full-bleed monochrome Canvas with four waveform lanes, live meters, segmented waveform selectors, a motion-bias XY pad, mute, and burst feedback. It owns its LFO parameters; those parameters are deliberately not duplicated in the Scene Group.

The four lanes publish control outputs for prompt position, motion energy, camera drift, and pulse. Expressions connect them to StreamDiff and the fruit renderer.

## Presets

- **Live Fill** — continuous 24-slot generation and three-clone flythrough.
- **Curated Stills** — interval capture off, explicit slot 0, single-card orbit presentation.
- **Frozen Gallery** — interval capture off and StreamDiff held while the scene continues rendering.
- **Hero Scatter** — three-clone fruitfall with stronger bounce and a front camera.
- **Performance** — two clones and StreamDiff frame skip 2.

The project also includes project-scoped node presets for the Motion Console and Transit Chamber. The renderer preset carries the persistent card-state payload.

## Select and arrange fruit

Visible occupied slots publish stable object ids `1..24`. Click a fruit to select its Atlas identity, then drag with the selected Card Tool. The persistent state stores a per-slot position offset, rotation, and scale; every clone of that identity follows the edited transform. Keys `1`, `2`, and `3` select Move, Rotate, and Scale, and Escape cancels an active edit.

## Curate one slot

1. Recall **Curated Stills**.
2. Choose `Capture Slot`.
3. Set the desired prompt-bank position and fire StreamDiff `render_one`.
4. Invoke the native Atlas `capture` action.
5. Confirm that only the chosen slot and its rendered card identity update.

Recall **Live Fill** to resume continuous spawning.

## Graph

```text
Fruit_Guide -> Fruit_SD -> Fruit_Matte --\
                       -> Fruit_Depth ---+-> Fruit_Atlas -> Fruit_Scene -> Fruit_Group_Output
                       ------------------/        |              ^
Fruit_LFO -- expressions -> prompt/motion         +-- occupancy--+
```

## Runtime checks

`Fruit_SD`, `Fruit_Matte`, `Fruit_Depth`, `Fruit_Atlas`, and `Fruit_Scene` should all report healthy. Atlas should report nonzero occupancy climbing toward `24/24`; its output is `1920x1120` for 24 slots × three pass columns at `128x224` per cell. If fruit appears as rectangles, confirm Matting feeds Atlas pass 1 and `segmentation_enabled` is on. If the bank stops changing, confirm Atlas `interval_enabled=true` and StreamDiff `hold=false`.

The deterministic motion proof records the normalized lifecycle twice. It showed smooth forward swarm motion, no bounce in Flythrough, no dropped frames, and an effectively seamless loop.
