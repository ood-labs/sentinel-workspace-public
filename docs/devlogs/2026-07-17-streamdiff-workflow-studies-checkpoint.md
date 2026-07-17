---
type: devlog
date: 2026-07-17
session_end: "05:26"
phase: phase-1-official-examples-modernization
subphase: streamdiff-workflow-studies
status: in-progress
approval: pending
summary: "Packaged and runtime-proved six portable StreamDiff workflow studies"
note_created: true
updated: 2026-07-17
---

**Goal**

Turn the loose StreamDiff experiments into a compact, portable technique collection, document what each graph demonstrates, and preserve the media and Module dependencies needed to open the examples on another machine.

**Work Done**

- Added six focused projects under `projects/streamdiff_workflows/`: image-space feedback zoom, depth-parallax zoom, architectural flythrough tuning, direct variant Mux switching, video depth conditioning, and procedural warp-map displacement.
- Bundled the authored `Expressive_Flow_Layers` Module and its shared timeline include using project-relative paths.
- Bundled the actual dancer source used to author the Marble Dancer study so the example retains its intended motion rather than substituting a procedural placeholder.
- Linked the Marble Dancer study's Video source to `assets/dancer_vert.mp4`; verified the saved relative path resolves, the H.264 file is present, and Sentinel connects it at 512x896 and 25 fps.
- Added collection-level authoring notes, engine requirements, runtime acceptance checks, and a validation record.
- Extended `knowledge/streamdiff.md` with the isolated motion mechanisms, direct-Mux versus Scene-Switcher distinction, and an engine-safe review sequence.
- Updated the repository index and tracking rules so the collection and bundled MP4 are included in Git.

**Runtime Proof**

- All six projects parsed and passed graph/path portability validation.
- Each study produced a healthy live output and successful capture in Sentinel 0.5.38.
- The procedural flow Module passed the real offline compiler with one pass, 53 parameters, and no lints.
- The direct variant Mux proved `solo_upstream` by holding the non-selected StreamDiff nodes.
- A fresh-process Marble Dancer load proved the bundled video source, Depth Estimation, and 512x896 StreamDiff pipeline healthy together.

**Issues Encountered**

- Switching directly from a healthy 896x512 ControlNet graph to the 512x896 Marble Dancer graph crashed Sentinel twice. A fresh-process cold load of Marble Dancer succeeded, isolating the issue to the cross-profile engine transition rather than the project or MP4.
- Submitted the crash as [Sentinel bug #59](https://github.com/ood-labs/sentinel-bugs/issues/59) and added the successful fresh-load result to the report.
- `engine_precision=Auto` did not select the installed FP8 input-tier engine for the 896x512 studies in this build, so the saved precision now matches the engines actually used for proof.

**Remaining Work**

- Build the separate groups-mode Mux example that switches complete Scene Groups through Group Outputs; the existing direct-Mux study intentionally covers only individual texture variants.
- Investigate and fix bug #59 in the Sentinel application repository, then rerun the interrupted clean-public cold-load sequence for final Phase 1 approval.

**Cross-References**

- Collection: `projects/streamdiff_workflows/README.md`
- Validation: `projects/streamdiff_workflows/VALIDATION.md`
- Knowledge: `knowledge/streamdiff.md`
- Crash report: `https://github.com/ood-labs/sentinel-bugs/issues/59`
