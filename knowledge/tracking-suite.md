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

The Features node is model-free classic computer vision. It is useful when you need lightweight geometry from video without downloading engines.

Tasks:

- Blob detection
- Corner detection
- Line detection

Data ports:

- `Blobs`
- `Corners`
- `Lines`

Control outputs include counts, strongest/largest feature positions, dominant line angle, and line coverage. Use `sentinel_pipeline info` for the exact outputs exposed by the current build.

## Detection

Pipeline type: `detection`

Detection emits object records from a YOLOX-S model. It requires the `auxiliary-detection` engine pack.

Data port:

- `Detections`

Basic smoke recipe:

1. Confirm the pack is ready with `sentinel_app action=engine_status`. If `auxiliary-detection` is missing, call `sentinel_app action=download_pack pack_id=auxiliary-detection` or `sentinel_app action=install_pack pack_id=auxiliary-detection`, then poll `engine_status`.
2. Create an image source from `examples/example.jpg`, or use a camera/Spout source with people or common COCO objects visible.
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
