---
type: devlog
date: 2026-07-05
phase: industrial-steel
subphase: camera-wip
status: paused
approval: pending
summary: "Pause industrial steel scene camera repair WIP"
---

**Done**

Created the modular industrial steel scene modules and project bundle, fixed the missing bundled `_shared/sdf` include path, and got the loaded graph back to a healthy compile/runtime state. Current proof captures include `captures/industrial_steel_greebled_live_fixed.png`, `captures/industrial_steel_inside_tuned.png`, and camera-debug captures under `captures/explicit_fly_pose_*.png`.

Camera repair is not complete. The duplicate `fly_position` controls were removed from source; the intended direction is to use the existing top camera parameters only (`camera_pos_x/y/z`, `camera_yaw`, `camera_pitch`, `camera_fov`). Sentinel repeatedly crashed on live reload of the camera-feature renderer, so resume from a clean app launch/load rather than hot reload.

**Next**

Resume by clean-loading `projects/industrial_steel_greebled/industrial_steel_greebled.sentinel`, verifying the renderer has no duplicate fly controls, and proving the top camera parameters visibly move the raymarched camera before continuing visual tuning.
