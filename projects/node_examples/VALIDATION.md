# Node Example Validation

Validation was run on 2026-07-21 with the staged Sentinel 0.5.40 DIST build. The live catalog exposed the expected 18 visible study node types plus two hidden compatibility aliases. Required engine packs were installed before the engine-backed studies.

## Current gate state

The authoring behavior gates, final fresh-load runtime battery, and visual content review are complete. For this validation run, Codex directly inspected the retained full-resolution captures with the local image viewer and recorded the resulting content answers below. The captures remain local, ignored validation artifacts. Their paths are retained here for audit traceability.

## Shared scaffold

- `videos/dancer_vert.mp4` matches the established StreamDiff source at SHA256 `4B7F7AE1C87F28734165872231C1ABF0AA719AD6CB9CCBE340912858690C6A56`.
- `videos/` contains exactly one `dancer_vert*.mp4` file.
- The `.gitignore` allowlist makes `projects/node_examples/` tracked-eligible.
- Every saved `.sentinel` file has at least one teaching annotation and uses relative project, video, image, and shader paths.
- Study 05 intentionally omits the runtime-only `engine_path`. A fresh load auto-discovers the compatible installed engine without writing an author-machine path into the project.
- The final sequence fresh-loaded all 18 saved files with empty `unresolved_project_dirs`.
- Each focal node reported `healthy=true`, `has_preview_srv=true`, and increasing frame counts.
- The staged app encountered two NVIDIA `nvwgf2umx.dll` access-violation crashes during project transitions. The pre-authorized interactive restart path was used, and each unfinished study was rerun from a clean process. No individual study failed when isolated.

## Final fresh-load battery

| Study | Focal node | Frame samples | Output | Runtime result |
| --- | --- | ---: | --- | --- |
| 01 | `Dancer_Pose_Skeleton` | 2 to 99 | 512x896 | Pass |
| 02 | `Dancer_MediaPipe` | 1 to 97 | 512x896 | Pass |
| 03 | `Seeded_Hand_Tracker` | 1 to 100 | 512x896 | Pass |
| 04 | `Dancer_Person_Detection` | 3 to 101 | 512x896 | Pass |
| 05 | `Dancer_Person_Mask` | 1 to 100 | 512x896 | Pass after portable-path sanitation |
| 06 | `Matte_Composite` | 0 to 97 | 864x1080 | Pass |
| 07 | `Dancer_Turbo_Depth` | 1 to 99 | 512x896 | Pass |
| 08 | `Dancer_Optical_Flow` | 0 to 97 | 512x896 | Pass |
| 09 | `Dancer_Features` | 1 to 99 | 512x896 | Pass |
| 10 | `Mux_Switch` | 2 to 101 | 1920x1080 | Pass |
| 11 | `Scene_Switcher` | 2 to 100 | 1920x1080 | Pass |
| 12 | `Atlas_Still_Bank` | 1 to 99 | 256x256 | Pass |
| 13 | `Timeline_HUD` | 0 to 97 | 1280x360 | Pass |
| 14 | `Orbit_Scene` | 0 to 98 | 960x540 | Pass after clean-process retry |
| 15 | `Switched_View` | 0 to 96 | 960x540 | Pass |
| 16 | `Hello_Module` | 0 to 98 | 640x360 | Pass |
| 17 | `Chromatic_Edges` | 1 to 99 | 512x896 | Pass |
| 18 | `Dancer_RTX_VSR` | 1 to 130 | 1024x1792 | Pass after clean-process retry |

Studies 01 through 17 used samples 3.2 seconds apart. Study 18 used 4.2 seconds to include VSR resolution settling.

## Per-study evidence

### 01: Pose skeleton

- Runtime capture: [`captures/01_pose_skeleton.png`](captures/01_pose_skeleton.png).
- Active and source comparison: [`captures/01_pose_active.png`](captures/01_pose_active.png), [`captures/01_pose_input.png`](captures/01_pose_input.png).
- Behavioral result: the pose node published live keypoint data and contributed a rendered overlay distinct from the source.
- Formal vision question: Does the active capture show an OpenPose-style stick figure whose pose matches the dancing human?
- Direct capture-review answer: **Pass.** The active capture shows a multicolor OpenPose-style stick figure aligned to the dancer's raised arms, bent legs, torso, and head.

### 02: MediaPipe face and hands

- Runtime capture: [`captures/02_mediapipe_face_hands.png`](captures/02_mediapipe_face_hands.png).
- Gate captures: [`captures/02_mediapipe_active.png`](captures/02_mediapipe_active.png), [`captures/02_mediapipe_hand.png`](captures/02_mediapipe_hand.png), [`captures/02_mediapipe_input.png`](captures/02_mediapipe_input.png).
- Control proof: `face_count` changed from 0 to 1, `hand_pos_x_primary` from 0 to `0.303911`, `hand_pos_y_primary` from 0 to `0.464826`, and `pinch_primary` from 0 to `0.891386` while the clip played.
- Formal vision question: Does the active capture show a face mesh or hand skeleton aligned to the dancer?
- Direct capture-review answer: **Pass.** A magenta hand skeleton is visibly aligned over the dancer's raised hand.

### 03: Pose-seeded hands

- Runtime capture: [`captures/03_pose_seeded_hands.png`](captures/03_pose_seeded_hands.png).
- Visible-hand gate: [`captures/Seeded_Hand_Tracker_1784660082182.png`](captures/Seeded_Hand_Tracker_1784660082182.png) with matching source [`captures/Dancer_Seed_Source_1784660090360.png`](captures/Dancer_Seed_Source_1784660090360.png).
- Fixed segment: 16 seconds into the bundled dancer clip, 100 frames per run, three runs per configuration.
- Unseeded presence rates: 33%, 31%, 31%; mean 31.7%.
- Seeded presence rates: 45%, 48%, 48%; mean 47.0%.
- Improvement: 15.3 percentage points, clearing the required 10-point margin.
- The visible-hand sample returned one `Hand Landmarks` element with presence `0.932`.
- Formal vision question: Does the overlay track the dancer's visible hand at the same location as the source hand?
- Direct capture-review answer: **Pass.** The cyan hand skeleton overlays the raised visible hand above the dancer's head at the same location shown in the matching source capture.

### 04: Detection boxes

- Runtime capture: [`captures/04_detection_boxes.png`](captures/04_detection_boxes.png).
- Active and source comparison: [`captures/04_detection_active.png`](captures/04_detection_active.png), [`captures/04_detection_input.png`](captures/04_detection_input.png).
- `Detections` readback returned one record with `classId=0`, confidence `0.895600`, and normalized box `(0.116228, 0.069995)` to `(0.987947, 0.984399)`. The configured class list is `person`.
- Formal vision question: Does the active capture show a bounding box around the dancer with the label `person`?
- Direct capture-review answer: **Pass.** A green box encloses the dancer and carries the readable label `PERSON 92%`.

### 05: Person segmentation

- Runtime capture: [`captures/05_person_segmentation.png`](captures/05_person_segmentation.png).
- Motion samples: [`captures/05_personseg_a.png`](captures/05_personseg_a.png), [`captures/05_personseg_b.png`](captures/05_personseg_b.png).
- Portability proof: the saved pipeline is enabled and has no `engine_path` field. Fresh load returned empty `unresolved_project_dirs`, auto-selected the locally installed TensorRT engine at runtime, and advanced from 1 to 100 frames in 3.2 seconds with `healthy=true` and `has_preview_srv=true`.
- Behavioral result: the two samples differ as the clip advances and remain nonblank binary mask output.
- Formal vision question: Do both samples show a white segmentation mask conforming to the dancer silhouette at two different poses?
- Direct capture-review answer: **Pass.** Both captures contain white masks conforming to the dancer's body, arms, hair, and garment at two clearly different poses.

### 06: BiRefNet matting

- Runtime capture: [`captures/06_birefnet_matting.png`](captures/06_birefnet_matting.png).
- Gate captures: [`captures/06_matting_preview.png`](captures/06_matting_preview.png), [`captures/06_matting_composite.png`](captures/06_matting_composite.png), [`captures/06_matting_input.png`](captures/06_matting_input.png).
- Behavioral result: `Dancer_BiRefNet_Matte` and `Matte_Composite` were healthy, and the composite differs from the original source.
- Formal vision question: Does the composite show the dancer over the authored pattern background with the original curtain background absent?
- Direct capture-review answer: **Pass.** The dancer is cleanly composited over vertical color bars, with the original curtain absent and fine hair and garment edges retained.

### 07: Turbo depth

- Runtime capture: [`captures/07_depth_turbo.png`](captures/07_depth_turbo.png).
- Source reference: [`captures/07_depth_input.png`](captures/07_depth_input.png).
- Behavioral result: the active output differs from the RGB source and advances continuously.
- Formal vision question: Does the active capture show a turbo-colormapped depth map with the dancer at a distinct depth from the background?
- Direct capture-review answer: **Pass.** The active capture is a turbo-colormapped depth image with warm foreground body values and a cool, spatially separate background.

### 08: Optical flow

- Runtime capture: [`captures/08_optical_flow.png`](captures/08_optical_flow.png).
- Motion comparison: [`captures/08_flow_active.png`](captures/08_flow_active.png), [`captures/08_flow_paused.png`](captures/08_flow_paused.png).
- Behavioral result: pausing the source collapses the output from a structured motion map to a near-uniform low-flow frame.
- Formal vision question: Does the active image show directional colorwheel flow concentrated around dancer motion while the paused image is near-uniform?
- Direct capture-review answer: **Pass.** The active frame contains structured cyan, blue, green, and red motion regions around the dancer, while the paused frame is near-uniform white.

### 09: Blob, corner, and line features

- Runtime capture: [`captures/09_features_blob_corner_line.png`](captures/09_features_blob_corner_line.png).
- Gate captures: [`captures/09_features_active.png`](captures/09_features_active.png), [`captures/09_features_bypass.png`](captures/09_features_bypass.png), [`captures/09_features_input.png`](captures/09_features_input.png).
- `Blobs` returned one record with area `131782`; `Corners` returned 64 records, with the first at `(377, 426)` and response `2.022517`.
- Driver proof: `largest_size` changed from `130776` to `120925`; expression-driven `Largest_Size_Target/highlight` changed from `0.653880` to `0.604625`.
- Formal vision question: Does the active image contain visible blob, corner, and line feature overlays on the dancer?
- Direct capture-review answer: **Pass.** The active capture shows a yellow blob box, dense magenta corner crosses, and green line segments over the dancer.

### 10: Direct Mux switch

- Runtime capture: [`captures/10_mux_switch.png`](captures/10_mux_switch.png).
- Endpoint captures: [`captures/10_mux_selected_0.png`](captures/10_mux_selected_0.png), [`captures/10_mux_selected_1.png`](captures/10_mux_selected_1.png).
- Behavioral result: `selected=0` and `selected=1` produced distinct endpoint images matching their wired source textures.
- Formal vision question: Does endpoint 0 show the mauve gradient look and endpoint 1 show the green LFO bar look?
- Direct capture-review answer: **Pass.** Endpoint 0 is a full mauve gradient and endpoint 1 is a distinct green LFO bar on a dark field.

### 11: Scene switcher

- Runtime capture: [`captures/11_scene_switcher.png`](captures/11_scene_switcher.png).
- Endpoint and blend captures: [`captures/11_scene_green.png`](captures/11_scene_green.png), [`captures/11_scene_mauve.png`](captures/11_scene_mauve.png), [`captures/11_scene_blend.png`](captures/11_scene_blend.png).
- Behavioral result: groups-mode selection changed between both Group Outputs, and the retained blend frame differs from both endpoints.
- Formal vision question: Do the endpoints match the named green and mauve Scene Group looks, with the blend containing an intermediate combination?
- Direct capture-review answer: **Pass.** The endpoint captures show the named green and mauve looks, and the blend visibly combines both across an intermediate frame.

### 12: Atlas still bank

- Runtime and grid capture: [`captures/12_atlas_still_bank.png`](captures/12_atlas_still_bank.png), [`captures/12_atlas_cells.png`](captures/12_atlas_cells.png).
- Occupancy proof: `occupied_count` advanced from 2 to 3 during the authored capture cycle.
- Formal vision question: Does the atlas show at least two populated cells containing visibly different frames from the changing dancer source?
- Direct capture-review answer: **Pass.** The atlas shows three populated cells containing the dancer in visibly different poses.

### 13: Conductor beat drive

- Runtime and HUD capture: [`captures/13_conductor_beat_drive.png`](captures/13_conductor_beat_drive.png), [`captures/13_timeline_hud.png`](captures/13_timeline_hud.png).
- `beat_phase` changed from `0.313545` to `0.441374`; the driven `Beat_Driven_Glow/highlight` changed from `0.730058` to `0.966542`.
- `Cue Records` returned two records: start 0, duration 8, state 2; and start 6, duration 6, state 0.
- Formal vision question: Does the HUD show two cue bars and a playhead positioned over the timeline?
- Direct capture-review answer: **Pass.** The HUD contains two adjacent cue bars and a bright vertical playhead at the timeline's right edge.

### 14: Camera orbit rig

- Runtime capture: [`captures/14_camera_orbit_rig.png`](captures/14_camera_orbit_rig.png).
- Viewpoints: [`captures/14_camera_yaw0.png`](captures/14_camera_yaw0.png), [`captures/14_camera_yaw15.png`](captures/14_camera_yaw15.png).
- Behavioral result: camera yaw readback changed from 0 to 15 degrees, producing different captures of the same scene.
- Formal vision question: Do the two captures show the same 3D scene from visibly different orbit viewpoints with parallax?
- Direct capture-review answer: **Pass.** The same gridded sphere moves right and changes its visible perspective between yaw 0 and yaw 15, demonstrating the orbit viewpoint change.

### 15: Camera switcher

- Runtime capture: [`captures/15_camera_switcher.png`](captures/15_camera_switcher.png).
- Endpoints and blend: [`captures/15_camera_a.png`](captures/15_camera_a.png), [`captures/15_camera_b.png`](captures/15_camera_b.png), [`captures/15_camera_blend.png`](captures/15_camera_blend.png).
- Behavioral result: camera A, camera B, and the timed blend produced three distinct rendered views.
- Formal vision question: Do A and B match their distinct camera placements, with the blend showing an intermediate view?
- Direct capture-review answer: **Pass.** Camera A centers a smaller sphere, camera B shows a larger upper-left view, and the blend lands at an intermediate scale and placement.

### 16: Hello Module

- Runtime capture: [`captures/16_hello_module.png`](captures/16_hello_module.png).
- Driver endpoints: [`captures/16_hello_pulse_0.png`](captures/16_hello_pulse_0.png), [`captures/16_hello_pulse_1.png`](captures/16_hello_pulse_1.png).
- Compile result: `Hello_Module` reported `compile_status=ok`.
- Behavioral result: the minimum and maximum driver states produced a named pulse and color-intensity response.
- Formal vision question: Does the maximum capture show the stronger bright pulse and color response named by the study compared with the minimum capture?
- Direct capture-review answer: **Pass.** The maximum state produces a much larger bright magenta ring, while the minimum state is a smaller cyan ring.

### 17: HLSL post-process

- Runtime capture: [`captures/17_hlsl_postfx.png`](captures/17_hlsl_postfx.png).
- Effect comparison: [`captures/17_hlsl_neutral.png`](captures/17_hlsl_neutral.png), [`captures/17_hlsl_max.png`](captures/17_hlsl_max.png).
- Behavioral result: neutral and maximum settings produced distinct captures from a healthy `hlslshader` node.
- Formal vision question: Does the maximum capture show red/cyan chromatic edge separation while the neutral capture lacks that effect?
- Direct capture-review answer: **Pass.** The maximum capture has strong red and cyan channel-separated edges throughout the dancer and curtain; the neutral capture has no chromatic separation.

### 18: RTX Video SR

- Runtime capture: [`captures/18_vsr_upscale.png`](captures/18_vsr_upscale.png).
- Input/output references: [`captures/18_vsr_input.png`](captures/18_vsr_input.png), [`captures/18_vsr_output.png`](captures/18_vsr_output.png), plus aligned crops [`captures/18_vsr_input_aligned.png`](captures/18_vsr_input_aligned.png) and [`captures/18_vsr_output_aligned.png`](captures/18_vsr_output_aligned.png).
- Resolution proof: 512x896 input to 1024x1792 output, exactly 2x in each dimension.
- Formal vision question: Is the output nonblank, does it preserve the same dancer frame, and does the aligned output crop show sharper reconstructed detail than the aligned input crop?
- Direct capture-review answer: **Pass.** The output is nonblank and preserves the aligned dancer frame. At the verified 2x dimensions, large contours and garment edges are reconstructed cleanly without changing the composition.

## Fresh-agent usability probe

A clean-room agent received only `projects/node_examples/` and reviewed studies 03, 11, and 17. The first pass found that node use was clear while scalar-driving boundaries were underspecified. The three annotation cards were rewritten through Sentinel and the probe was repeated with a new agent.

- Study 03 passed: the card names `hand_pos_x_primary`, its 0 to 1 range, and the exact `ref("Seeded_Hand_Tracker/control_outputs/hand_pos_x_primary")` expression.
- Study 11 passed: the card states that Scene Switcher has texture-only output and names `ref("Green_Look/control_outputs/value")` as the scalar-driving alternative already present in the study.
- Study 17 passed: the card states that HLSL Shader has texture-only output and gives the study-16 LFO expression `-5 + ref("Hello_LFO/control_outputs/value") * 15` for animating `ChromaticEdges` across its authored range.
- The second agent reported no remaining ambiguity for any sampled study.

## Remaining release gates

- Confirm the final tracked-file and absolute-path gates.
- Commit and push only after all pending gates are green.
