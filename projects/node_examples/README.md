# Node Example Studies

This collection contains 18 small Sentinel projects for Sentinel 0.5.40 or newer. Each project isolates one node type or one closely related wiring pattern, includes an in-graph teaching card, and opens independently. Load one `.sentinel` file at a time and inspect the named controls before adapting the graph.

The human keyboard and mouse reference is [UI Interactions and Shortcuts](../../knowledge/ui-interactions.md).

## Studies

| File | Node type | Technique | Main controls | Required engines |
| --- | --- | --- | --- | --- |
| `01_pose_skeleton.sentinel` | `pose` | OpenPose-style skeleton overlay and `Keypoints` records | `confidenceThreshold`, `keypointThreshold`, `smoothingAlpha` | `auxiliary-pose` |
| `02_mediapipe_face_hands.sentinel` | `mediapipe` | Face mesh, hand skeleton, gestures, and control outputs | `trackerMode`, `face_enabled`, `hands_enabled`, `handSmoothing` | `auxiliary-mediapipe-face`, `auxiliary-mediapipe-hands` |
| `03_pose_seeded_hands.sentinel` | `pose` + `mediapipe` | Pose wrist keypoints seed MediaPipe hand search | `poseFusionEnabled`, `poseWristConfidence`, `poseWristSearchRadius` | `auxiliary-pose`, `auxiliary-mediapipe-hands` |
| `04_detection_boxes.sentinel` | `detection` | Person-class boxes and `Detections` records | `confidence_threshold`, `class_names`, `draw_boxes` | `auxiliary-detection` |
| `05_person_segmentation.sentinel` | `personseg` | Binary person silhouette mask | `threshold`, `binarize_mask`, `overlay_mode` | `auxiliary-personseg` |
| `06_birefnet_matting.sentinel` | `matting` + `module` | BiRefNet alpha matte composited over an authored background | `outputMode`, `smoothingAlpha`, composite `exposure` | `auxiliary-birefnet` |
| `07_depth_turbo.sentinel` | `depthestimation` | Turbo-colormapped monocular depth | `outputMode`, `colormap`, `contrastBoost` | `auxiliary` |
| `08_optical_flow.sentinel` | `opticalflow` | Direction and magnitude flow visualization | `output_mode`, `flow_scale`, `vis_max_flow` | None, NVIDIA Optical Flow hardware |
| `09_features_blob_corner_line.sentinel` | `features` + `module` | Blob, corner, and line records plus a `largest_size` driver | task enable toggles, thresholds, count limits | None |
| `10_mux_switch.sentinel` | `mux` | Direct texture-input cuts | `selected`, `fade_time`, `solo_upstream` | None |
| `11_scene_switcher.sentinel` | `groupoutput` + `mux` | Wireless Scene Group cuts and crossfades | `source_mode`, `selected_group`, `fade_time` | None |
| `12_atlas_still_bank.sentinel` | `atlas` | Timed multi-slot still capture and occupancy records | capture interval, `capture_now`, atlas dimensions | None |
| `13_conductor_beat_drive.sentinel` | `conductor` + `module` | Beat controls drive a look while Cue Records render in a HUD | `bpm`, `transport_run`, `beats_per_bar` | None |
| `14_camera_orbit_rig.sentinel` | `camera` + `module` | Camera-reference orbit control of a 3D scene | orbit yaw, pitch, radius, target | None |
| `15_camera_switcher.sentinel` | `camera` + `camswitch` + `module` | Three-camera cuts and blends through `camera_ref` | selected camera, blend duration | None |
| `16_hello_module.sentinel` | `module` | Minimal authored module driven by an LFO control expression | pulse/phase driver and module color response | None |
| `17_hlsl_postfx.sentinel` | `hlslshader` | Notch-style chromatic edge post-process | `ChromaticEdges`, `blend_amount` | None |
| `18_vsr_upscale.sentinel` | `vsr` | RTX Video Super Resolution at 2x linear scale | `quality`, `scale_factor` | None, RTX GPU with R550.50+ driver |

## Study notes

### 01: Pose skeleton

`Dancer Pose Skeleton` reads the bundled dancer clip, renders an OpenPose-style stick figure, and publishes 18-keypoint records. Wire its `Keypoints` data port into consumers that accept the Pose record schema.

### 02: MediaPipe face and hands

`Dancer MediaPipe` runs face and hand tracking together. Its named control outputs, including `hand_pos_x_primary` and `pinch_primary`, can drive another parameter with `ref("Dancer_MediaPipe/control_outputs/<name>")`.

### 03: Pose-seeded hands

The dancer texture feeds both trackers. `Pose Wrist Seeds/Keypoints` also feeds the `Seeded Hand Tracker/Keypoints` input, allowing confident pose wrists to guide the hand-search region. The saved thresholds were measured against a fixed clip segment and cleared the collection's improvement gate.

### 04: Detection boxes

`Dancer Person Detection` filters COCO results to `person`, draws the label and box, and publishes normalized `Detections` records. Use `confidence_threshold` to balance sensitivity and stability.

### 05: Person segmentation

`Dancer Person Mask` emits a hard `mask_only` texture. `threshold` changes the confidence cutoff and `binarize_mask` selects hard mask edges.

### 06: BiRefNet matting

`Dancer BiRefNet Matte` emits `alpha_matte`. `Matte Composite` combines that hero matte with the pattern source on its `Hero` and `BG` inputs, then publishes `Comp`.

### 07: Turbo depth

`Dancer Turbo Depth` converts the clip into a colorized depth texture. Turbo hue makes the figure-to-background depth separation easy to inspect while tuning smoothing and contrast.

### 08: Optical flow

`Dancer Optical Flow` maps vector direction to hue and magnitude to brightness. Motion in the dancer produces concentrated color while a paused source approaches a uniform low-flow frame.

### 09: Geometric features

`Dancer Features` publishes `Blobs`, `Corners`, and `Lines`. Its `largest_size` control output drives `Largest Size Target/highlight` through `ref("Dancer_Features/control_outputs/largest_size") / 200000.0`.

### 10: Direct Mux switch

Two authored looks feed numbered Mux inputs. Change `selected` between 0 and 1 to cut the `Out` texture between them.

### 11: Scene switcher

Each complete look ends in a Group Output inside a Scene Group. `Scene Switcher` uses groups mode, so `selected_group` switches the wireless looks and `fade_time` controls the transition.

### 12: Atlas still bank

The Atlas captures changing video frames into four slots. `occupied_count` reports fill progress and `Slot Occupancy` identifies populated cells.

### 13: Conductor beat drive

`Beat Conductor/beat_phase` drives `Beat Driven Glow/highlight`. The expression is visible on the target parameter. `Cue Records` also feed `Timeline HUD`, which renders the cue bars and playhead.

### 14: Camera orbit rig

`Orbit Rig` supplies a `camera_ref` to `Orbit Scene`. Adjust orbit yaw, pitch, target, and radius to move the same authored 3D scene through different viewpoints.

### 15: Camera switcher

Three Camera nodes feed `Camera Switcher`, whose `camera_ref` drives `Switched View`. Select an endpoint camera for a cut or use the blend control for an interpolated camera state.

### 16: Hello Module

`Hello LFO` publishes a changing control signal. An expression maps that signal into `Hello Module`, producing a visible pulse and color response. This is the smallest example of a compiled Module plus a live driver.

### 17: HLSL post-process

`Chromatic Edges` applies a color-separated edge treatment to the dancer clip. Compare a neutral amount with the maximum setting to identify the red/cyan edge split.

### 18: RTX Video SR

`Dancer RTX VSR` receives the 512x896 source and publishes 1024x1792 output after settling. The driver and GPU provide the inference path, so this study has no downloadable Sentinel engine pack.

## Runtime checks

Before loading an engine-backed study on a fresh machine, run `sentinel_app action=engine_status` and install any missing required pack. Then load the saved project and require:

- `unresolved_project_dirs` is empty;
- the focal node reports `stats.healthy=true` and `stats.has_preview_srv=true`;
- `framesProcessed` increases across reads at least three seconds apart;
- a focal-node capture is nonblank;
- the study-specific behavior described above is visible or measurable.

The retained results and captures are listed in [VALIDATION.md](VALIDATION.md). Open one project at a time on memory-constrained systems so engines and authored resources can release between studies.
