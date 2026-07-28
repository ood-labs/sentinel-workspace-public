---
type: devlog
date: 2026-07-27
phase: 5
subphase: post-review-previews
status: complete
approval: pending
summary: "Make standalone example previews visible and remove Group Outputs"
---

## Done

Topographic HUD, Strata, Desert Totem, and Living Room SDF now serialize every
pipeline-node preview as visible by default and contain zero active Group Output
pipelines. Their READMEs name the direct final image nodes, and the official
validator now enforces both zero Group Outputs and visible default previews for
these standalone shipping projects.

Proof: all four project JSON files parse with `closed=[]` and
`groupoutputs=[]`; `tools/test-official-examples.ps1` passes, including watched
negative fixtures for both new guards. The four-project validator passes three
projects; Strata's only remaining error is the pre-existing five-control Scene
Group against the unrelated 6-10 release rule.

## Next

Continue standalone example review without loading the same project twice in one
Sentinel session; do not promote the internal Showcase Gallery.
