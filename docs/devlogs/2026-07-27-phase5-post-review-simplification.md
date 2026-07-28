---
type: devlog
date: 2026-07-27
phase: 5
subphase: post-review
status: complete
approval: pending
summary: "Remove redundant example control canvases and make standalone projects authoritative"
---

## Done

The user explicitly authorized a post-review Tier 3 override of Phase 5's
last-control and output-resolution gates: remove the Topographic Signal, Strata
Composition, and Desert Warp authored control canvases and replace them with
fixed 480 x 270 passive bus previews while retaining all real editing in
Properties. The user also reclassified the high-VRAM Showcase Gallery as an
internal review fixture, superseding its prior release-gallery role; standalone
projects are now the shipping authorities and promotion refuses the Gallery.

Proof: all three standalone modules passed real `compile_check` with two passes,
zero lints, and module-UI validation with zero controls. Fresh Sentinel sessions
loaded each standalone project only once; `signal`, `strata_control`, and
`dada_control` compiled healthy in Standard mode at 480 x 270 with advancing
frames. Pixel probes on `captures/phase5/minimal-bus-review/*_480x270.png`
confirmed black fields, white labels, and live warm markers. Three-way module
copy guards matched, `tools/test-official-examples.ps1` passed, and
`tools/validate-official-examples.ps1 -Projects
topographic_hud,strata,desert_totem,showcase_gallery` reported four passed and
zero failed.

## Next

No later phase starts here; retain the standalone projects for distribution and the Gallery only for internal review.

## Post-landing audit + fixes

Three parallel reviews covered code safety, contract alignment, and regression
coverage. After recognizing the user's explicit Tier 3 authorization, the
audit found zero remaining ship blockers. Safe fixes preserved the serialized
output-pin names, corrected the Gallery's `signal` resolution without altering
`signal_1`, aligned the release standard and historical plan wording, and
curated current passive-bus PNGs into each standalone proof folder.

The audit also added a machine-enforced `PassiveBuses` policy. Validation now
rejects a missing bus, project/module mismatch, saved or manifest resolution
drift, Canvas panel declaration, or reintroduced viewport controls. Promotion
fixtures prove both default Gallery omission and explicit Gallery refusal.

A dedicated zero-control header fixture and runtime marker-liveness automation
were considered and deferred: current generated-header hashing, real compile
checks, live captures, and structural passive-bus guards cover this revision
without expanding the release tooling further.
