---
type: devlog
date: 2026-07-27
phase: 5
subphase: post-review-performance
status: complete
approval: pending
summary: "Add a portrait analysis proxy before Strata Features"
---

## Done

Inserted a project-local 320 x 480 `Feature Downscale` between the full 720 x
1080 `plate_comp` output and `Features #0`, reducing the analysis input to one
fifth of the original pixel count while preserving the full-resolution Program
branch. Added an exact proxy-extent input to `corner_thread`, so 15 live corner
records are rescaled from analysis pixels across the full portrait. Proof:
real compile checks passed with zero lints, live nodes were healthy with
advancing frames, `projects/strata/proof/feature-analysis-proxy.png` shows the
portrait proxy, and the official validator reported 11 active modules, zero
orphans, and zero errors.

The lightweight profiler still attributes roughly 52 ms of wall time to
Features, so the node remains the graph hotspot despite the bounded input. The
proxy itself costs approximately 0.005 ms.

## Next

No later phase starts here; retain the 320 x 480 proxy as Strata's shipping
analysis contract.
