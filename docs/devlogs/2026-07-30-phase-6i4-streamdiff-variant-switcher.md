---
type: devlog
date: 2026-07-30
phase: 6
subphase: 6I.4
status: complete
approval: approved
summary: "Add and approve the StreamDiff direct-variant switcher"
---

## Done

- Added a responsive authored Canvas that keeps the live Mux program visible beneath a compact
  `AUTO / 1 / 2 / 3` switcher bar.
- Connected the panel's selected control output to the Mux and retained `solo_upstream`, so only
  the active StreamDiff variant continues processing.
- Verified manual selection, automatic cycling, healthy live output, and a clean Module compile.
- Saved the exact user-approved state and current layout with the Module bundled into the project.
  Proof: `captures/phase6_streamdiff_workflow_04_approved`.

## Next

- 6I.5 reviews the video-depth-control workflow in the existing Sentinel session.
