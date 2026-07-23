# Tracking Suite

Sentinel includes model-backed and model-free tracking nodes. Use `sentinel_pipeline action=list_types` to confirm what is available in the current build.

## MediaPipe

Pipeline type: `mediapipe`

MediaPipe is the main composable face and hand tracker. It can run face tracking, hand tracking, or both in one node.

Data ports:

- `Face Landmarks`
- `Hand Landmarks`

Hand gesture control outputs:

- `pinch_primary`, `pinch_left`, `pinch_right`
- `fist_primary`, `fist_left`, `fist_right`
- `open_palm_primary`, `open_palm_left`, `open_palm_right`
- `point_primary`, `point_left`, `point_right`
- finger curls
- hand position
- index finger direction

Use these outputs with `sentinel_expression action=set` and `ref()` to drive other parameters.

The old `facemesh` type is a hidden compatibility alias for old projects. Prefer `mediapipe` for new work.

## Features

Pipeline type: `features`

The Features node is model-free classic computer vision. It avoids model-engine downloads, but it is not automatically cheap. Input resolution and permissive thresholds can make candidate generation extremely expensive.

Tasks:

- Blob detection
- Corner detection
- Line detection

Data ports:

- `Blobs`
- `Corners`
- `Lines`

Control outputs include counts, strongest/largest feature positions, dominant line angle, and line coverage. Use `sentinel_pipeline info` for the exact outputs exposed by the current build.

### Safe Tuning Order

Start with every task disabled, establish a graph-profile baseline, then enable and tune one task at a time while the real Features preview is open.

- Blobs: begin with a restrictive luma threshold, meaningful `min_area`, and a small `max_count`. Settings that fragment most of the frame or produce one nearly full-frame component are both warning signs.
- Corners: keep quality conservative, minimum distance reasonably large, and count bounded. Low quality plus a tiny separation radius can create a dense candidate field and severe CPU spikes.
- Lines: leave disabled unless the composition needs real line records. Low edge thresholds, short minimum lengths, permissive gap bridging, and high counts can become extremely expensive.
- Edges: leave disabled unless their control outputs or preview are required. Tune thresholds and pre-blur deliberately; do not enable edges merely as a prerequisite for unrelated visuals.

After each material change, wait for settled frames and run `sentinel_graph action=profile summary=true sort_by=wall_time_ms`. Check `stats.healthy`, `framesProcessed`, output counts, and real UI responsiveness. Immediately revert a setting that causes a large wall-time or interaction regression. Published count limits are not a substitute for threshold discipline because candidate generation may happen before truncation.

### Analysis-Resolution Branch

When the intended creative chain is 1280x720 but Features cannot meet its budget at that size, use an explicit proxy:

```text
1280x720 source ─────────────────────────────→ full-resolution visual renderer
       └→ 480x270 analysis proxy → Features ─→ Blobs / Corners / Lines
```

The proxy downsamples only the texture sent into Features. Features therefore previews and reports coordinates in 480x270 analysis space; consumers must normalize with that exact resolution before mapping into the full-resolution render. Keep the proxy next to Features in graph order and give it a meaningful preview. This is an external graph workaround, not an internal Features setting, unless the live build explicitly advertises an internal analysis scale.

### Using Feature Data Visually

Assign semantic roles before drawing:

- blobs are well suited to macro regions, density, displacement fields, flow centers, and broad motion;
- corners are well suited to local accents, seeds, handles, and restrained topology;
- lines should be consumed only when the real line task is intentionally enabled and inside budget.

Do not connect every corner to one dominant blob or render every record as a large literal marker. For networks, add a data-planning stage with confidence ranking, temporal smoothing, distance limits, maximum degree, and hysteresis. That planner needs its own preview before a downstream renderer is accepted.

## Detection

Pipeline type: `detection`

Detection emits object records from a YOLOX-S model. It requires the `auxiliary-detection` engine pack.

Data port:

- `Detections`

Basic smoke recipe:

1. Confirm the pack is ready with `sentinel_app action=engine_status`. If `auxiliary-detection` is missing, call `sentinel_app action=download_pack pack_id=auxiliary-detection` or `sentinel_app action=install_pack pack_id=auxiliary-detection`, then poll `engine_status`.
2. Create a camera, image, video, or Spout source with people or common COCO objects visible.
3. Create `sentinel_pipeline action=create type=detection name=object_track`.
4. Wire the image/video source to the detection node with `sentinel_pipeline action=set_input` or `sentinel_graph action=add_link`.
5. Inspect `sentinel_pipeline action=info pipeline_id=object_track`; the `Detections` data port reports boxes, confidence, and class fields.
6. Use `sentinel_capture action=pipeline pipeline_id=object_track` for a visual overlay proof, or `sentinel_pipeline action=capture_data_port pipeline_id=object_track port=Detections` for records.

## Pose

Pipeline type: `pose`

Pose emits human keypoints. It can feed MediaPipe hands through a data-port link when you want pose wrists to help seed hand crops.

Data port:

- `Keypoints`

## Depth And Segmentation

Pipeline types:

- `depthestimation`
- `personseg`
- `matting`

These produce image-like outputs, not scalar gesture signals. The user-facing name for `matting` is Background Removal. Use them as texture inputs downstream, or combine them with modules/shaders for compositing.
