# Proof inventory

Captured from Sentinel 0.5.44 on 2026-07-22.

| File | Evidence |
| --- | --- |
| `massing-canvas.png` | Full-width massing editor with its compact tool strip and no duplicate parameter rail |
| `facade-canvas.png` | Centered facade field with rhythm and feature handles aligned to visible elements |
| `materials-canvas.png` | Twelve live material records rendered as a full-canvas swatch board |
| `lighting-canvas.png` | Full-width light plan with four selectable spatial controls |
| `renderer-srgb.png` | Primary deterministic 1920x1080 display-referred building output |
| `renderer-native-depth.png` | Camera-aligned 1920x1080 structural depth output |
| `streamdiff-reference.png` | Optional saved depth-ControlNet interpretation branch |

Runtime finalization checked all six pipelines for `healthy=true`, advancing frames, preview availability, and expected output formats. The five authored Module directories also passed `sentinel_pipeline compile_check` with no lints.
