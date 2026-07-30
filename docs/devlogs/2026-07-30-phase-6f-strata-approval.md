---
type: devlog
date: 2026-07-30
phase: 6
subphase: 6F
status: complete
approval: pending
summary: "Ship the approved simplified Strata instrument"
---

## Done

- Preserved the user's tuned Strata look while removing the redundant
  `strata_control` node, its backward link, and all fourteen expression
  drivers.
- Replaced the obsolete proxy node with the Features pipeline's built-in 4x
  analysis downsample, removed both dead bundled modules, and refreshed the
  public README.
- Verified a clean reload with ten healthy nodes at 60 Hz and recorded the
  approved evolving output. Proof: `captures/phase6_strata_approved`.

## Next

- G6 opens Face Collage for measured optimization and final review.
